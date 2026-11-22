package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

// Tokens known by the fake auth service, and the users that own them.
var sessions = map[string]string{
	"token-ana": "ana",
	"token-bob": "bob",
}

// The fake event service knows only this event.
const knownEvent = 1

var server *httptest.Server

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "siga-signups")
	if err != nil {
		panic(err)
	}
	if err := openDB(filepath.Join(dir, "test.db")); err != nil {
		panic(err)
	}

	fakeAuth := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		username, ok := sessions[strings.TrimPrefix(r.URL.Path, "/")]
		if !ok {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}
		json.NewEncoder(w).Encode(map[string]string{"Username": username})
	}))
	fakeEvents := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if _, ok := sessions[bearer(r)]; !ok {
			http.Error(w, "invalid token", http.StatusUnauthorized)
			return
		}
		if r.URL.Path != "/event/1" {
			http.NotFound(w, r)
			return
		}
		w.Write([]byte(`{"id": 1, "name": "Semana"}`))
	}))
	authURL, eventURL = fakeAuth.URL, fakeEvents.URL

	router()
	server = httptest.NewServer(http.DefaultServeMux)

	code := m.Run()

	server.Close()
	fakeAuth.Close()
	fakeEvents.Close()
	db.Close()
	os.RemoveAll(dir)
	os.Exit(code)
}

func request(t *testing.T, method, path, token, body string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(method, server.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := server.Client().Do(req)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { res.Body.Close() })
	return res
}

func expectStatus(t *testing.T, res *http.Response, want int) {
	t.Helper()
	if res.StatusCode != want {
		t.Fatalf("%s %s: status %d, want %d",
			res.Request.Method, res.Request.URL.Path, res.StatusCode, want)
	}
}

func decodeSignup(t *testing.T, res *http.Response) Signup {
	t.Helper()
	var s Signup
	if err := json.NewDecoder(res.Body).Decode(&s); err != nil {
		t.Fatalf("decoding signup: %v", err)
	}
	return s
}

func TestSignupUsesTheOwnerOfTheToken(t *testing.T) {
	res := request(t, "POST", "/signup", "token-ana", `{"event_id": 1}`)
	expectStatus(t, res, http.StatusCreated)
	s := decodeSignup(t, res)
	if s.Username != "ana" || s.EventID != knownEvent || s.PresenceConfirmed != 0 {
		t.Fatalf("created %+v, want ana in event 1 without presence", s)
	}

	res = request(t, "GET", "/signup/"+strconv.FormatInt(s.ID, 10), "token-ana", "")
	expectStatus(t, res, http.StatusOK)
	if got := decodeSignup(t, res); got != s {
		t.Errorf("GET returned %+v, want %+v", got, s)
	}

	// Same user and event again.
	expectStatus(t, request(t, "POST", "/signup", "token-ana", `{"event_id": 1}`), http.StatusConflict)
}

func TestCannotSignUpAnotherUser(t *testing.T) {
	res := request(t, "POST", "/signup", "token-bob", `{"username": "ana", "event_id": 1}`)
	expectStatus(t, res, http.StatusForbidden)

	// Naming yourself is fine.
	res = request(t, "POST", "/signup", "token-bob", `{"username": "bob", "event_id": 1}`)
	expectStatus(t, res, http.StatusCreated)
	if s := decodeSignup(t, res); s.Username != "bob" {
		t.Errorf("signed up %q, want bob", s.Username)
	}
}

func TestPresenceOnlyOnOwnSignup(t *testing.T) {
	res := request(t, "POST", "/signup", "token-ana", `{"event_id": 1}`)
	if res.StatusCode != http.StatusCreated && res.StatusCode != http.StatusConflict {
		t.Fatalf("signing ana up: status %d", res.StatusCode)
	}

	body := `{"username": "ana", "event_id": 1, "presence_confirmed": 1}`
	expectStatus(t, request(t, "PUT", "/presence", "token-bob", body), http.StatusForbidden)

	expectStatus(t, request(t, "PUT", "/presence", "token-ana", `{"event_id": 1, "presence_confirmed": 1}`), http.StatusOK)
	expectStatus(t, request(t, "PUT", "/presence", "token-ana", `{"event_id": 1, "presence_confirmed": 2}`), http.StatusBadRequest)
}

func TestPresenceWithoutSignup(t *testing.T) {
	// bob has a token but no signup in event 2.
	body := `{"event_id": 2, "presence_confirmed": 1}`
	expectStatus(t, request(t, "PUT", "/presence", "token-bob", body), http.StatusNotFound)
}

func TestAuthentication(t *testing.T) {
	expectStatus(t, request(t, "POST", "/signup", "", `{"event_id": 1}`), http.StatusUnauthorized)
	expectStatus(t, request(t, "POST", "/signup", "lixo", `{"event_id": 1}`), http.StatusUnauthorized)
	expectStatus(t, request(t, "GET", "/signup/1", "lixo", ""), http.StatusUnauthorized)
}

func TestInvalidRequests(t *testing.T) {
	expectStatus(t, request(t, "POST", "/signup", "token-ana", `{"event_id": 99}`), http.StatusNotFound)
	expectStatus(t, request(t, "POST", "/signup", "token-ana", `{"event_id": "1"}`), http.StatusBadRequest)
	expectStatus(t, request(t, "GET", "/signup/abc", "token-ana", ""), http.StatusBadRequest)
	expectStatus(t, request(t, "GET", "/signup/9999", "token-ana", ""), http.StatusNotFound)
}

func TestAuthUnavailable(t *testing.T) {
	saved := authURL
	authURL = "http://127.0.0.1:1"
	defer func() { authURL = saved }()

	expectStatus(t, request(t, "POST", "/signup", "token-ana", `{"event_id": 1}`), http.StatusServiceUnavailable)
}
