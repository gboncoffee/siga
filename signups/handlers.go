package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// Used for the calls to the other services, so a hung one cannot hang us.
var client = &http.Client{Timeout: 5 * time.Second}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

// bearer returns the token of an "Authorization: Bearer <token>" header, or "".
func bearer(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if len(h) > 7 && strings.EqualFold(h[:7], "bearer ") {
		return strings.TrimSpace(h[7:])
	}
	return ""
}

// session is an authenticated request: its token and the user that owns it.
type session struct {
	token    string
	username string
}

// authenticate asks the auth service whose session the token of the request
// is. It returns ok == false after writing the error response.
func authenticate(w http.ResponseWriter, r *http.Request) (s session, ok bool) {
	token := bearer(r)
	if token == "" {
		http.Error(w, "missing bearer token", http.StatusUnauthorized)
		return s, false
	}

	resp, err := client.Get(authURL + "/" + url.PathEscape(token))
	if err != nil {
		log.Println("auth request:", err)
		http.Error(w, "auth service unavailable", http.StatusServiceUnavailable)
		return s, false
	}
	defer resp.Body.Close()

	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusBadRequest, http.StatusUnauthorized:
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return s, false
	default:
		http.Error(w, "auth service error: "+resp.Status, http.StatusServiceUnavailable)
		return s, false
	}

	var body struct{ Username string }
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil || body.Username == "" {
		log.Println("auth response without username:", err)
		http.Error(w, "auth service error: bad response", http.StatusServiceUnavailable)
		return s, false
	}
	return session{token: token, username: body.Username}, true
}

// ownUsername checks that the username of the body, if any, is the one of the
// session: a user can only act on their own signups. It returns the username
// to use, or ok == false after writing the error response.
func ownUsername(w http.ResponseWriter, s session, fromBody string) (string, bool) {
	if fromBody != "" && fromBody != s.username {
		http.Error(w, "cannot act on behalf of another user", http.StatusForbidden)
		return "", false
	}
	return s.username, true
}

// eventExists asks the event service (with the caller's token) if the event
// exists. It returns false after writing the error response.
func eventExists(w http.ResponseWriter, token string, id int32) bool {
	req, err := http.NewRequest("GET", fmt.Sprintf("%s/event/%d", eventURL, id), nil)
	if err != nil {
		log.Println("event request:", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return false
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := client.Do(req)
	if err != nil {
		log.Println("event request:", err)
		http.Error(w, "event service unavailable", http.StatusServiceUnavailable)
		return false
	}
	defer resp.Body.Close()

	if resp.StatusCode == http.StatusOK {
		return true
	}
	// 4xx (e.g. 404, event not found) goes back to the caller as is.
	if resp.StatusCode >= 400 && resp.StatusCode < 500 {
		http.Error(w, "event service: "+resp.Status, resp.StatusCode)
	} else {
		http.Error(w, "event service: "+resp.Status, http.StatusServiceUnavailable)
	}
	return false
}

// POST /signup  {"event_id": 1}
// Signs up the owner of the token. "username" may be in the body, but it must
// be the owner's.
func signup(w http.ResponseWriter, r *http.Request) {
	sess, ok := authenticate(w, r)
	if !ok {
		return
	}

	var s Signup
	if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if s.Username, ok = ownUsername(w, sess, s.Username); !ok {
		return
	}
	if !eventExists(w, sess.token, s.EventID) {
		return
	}

	id, err := NewSignup(s.Username, s.EventID)
	if errors.Is(err, errDuplicate) {
		http.Error(w, "already signed up for this event", http.StatusConflict)
		return
	}
	if err != nil {
		log.Println("new signup:", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	s.ID, s.PresenceConfirmed = id, 0
	writeJSON(w, http.StatusCreated, s)
}

// PUT /presence  {"event_id": 1, "presence_confirmed": 1}
// presence_confirmed is 1 to confirm and 0 to unconfirm. Changes the signup of
// the owner of the token; "username" may be in the body, but it must be the
// owner's.
func presence(w http.ResponseWriter, r *http.Request) {
	sess, ok := authenticate(w, r)
	if !ok {
		return
	}

	var s Signup
	if err := json.NewDecoder(r.Body).Decode(&s); err != nil {
		http.Error(w, "invalid JSON", http.StatusBadRequest)
		return
	}
	if s.Username, ok = ownUsername(w, sess, s.Username); !ok {
		return
	}
	if s.PresenceConfirmed != 0 && s.PresenceConfirmed != 1 {
		http.Error(w, "presence_confirmed must be 0 or 1", http.StatusBadRequest)
		return
	}

	err := RegisterPresence(s)
	if errors.Is(err, sql.ErrNoRows) {
		http.Error(w, "signup not found", http.StatusNotFound)
		return
	}
	if err != nil {
		log.Println("register presence:", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
}

// GET /signup/{id}
func check_signup(w http.ResponseWriter, r *http.Request) {
	if _, ok := authenticate(w, r); !ok {
		return
	}

	id, err := strconv.ParseInt(r.PathValue("id"), 10, 32)
	if err != nil {
		http.Error(w, "invalid id", http.StatusBadRequest)
		return
	}

	s, err := GetByID(int32(id))
	if errors.Is(err, sql.ErrNoRows) {
		http.Error(w, "signup not found", http.StatusNotFound)
		return
	}
	if err != nil {
		log.Println("get signup:", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	writeJSON(w, http.StatusOK, s)
}
