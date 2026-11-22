package main

import (
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"uuid"

	"github.com/gboncoffee/siga/auth/repository"
)

type AuthenticatedResponse struct {
	Username string
}

// GET /{uuid} answers whether the session exists and, if so, whose it is.
func authenticated(w http.ResponseWriter, r *http.Request) {
	token, err := uuid.Parse(r.PathValue("uuid"))
	if err != nil {
		http.Error(w, "invalid token", http.StatusBadRequest)
		return
	}

	username, err := repository.SessionUsername(token)
	if errors.Is(err, sql.ErrNoRows) {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}
	if err != nil {
		log.Println("session lookup:", err)
		http.Error(w, "internal server error", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(AuthenticatedResponse{Username: username})
}
