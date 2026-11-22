package main

import (
	"database/sql"
	"errors"
	"log"

	_ "modernc.org/sqlite"
)

// Fields are exported (and tagged) so they can be sent as JSON.
type Signup struct {
	ID                int64  `json:"id,omitempty"`
	Username          string `json:"username"`
	EventID           int32  `json:"event_id"`
	PresenceConfirmed int32  `json:"presence_confirmed"`
}

var errDuplicate = errors.New("already signed up")

var db *sql.DB

func init() {
	var err error
	db, err = sql.Open("sqlite", "db.db")
	if err != nil {
		log.Fatal(err)
	}

	// One connection: requests wait for each other instead of failing with
	// "database is locked".
	db.SetMaxOpenConns(1)

	_, err = db.Exec(`
		CREATE TABLE IF NOT EXISTS signups (
			id INTEGER PRIMARY KEY,
			username TEXT NOT NULL,
			event_id INTEGER NOT NULL,
			presence_confirmed INTEGER NOT NULL DEFAULT 0 CHECK (presence_confirmed IN (0, 1)),
			UNIQUE (event_id, username)
		)`)
	if err != nil {
		log.Fatal(err)
	}
}

// NewSignup returns the id of the new signup, or errDuplicate if the user is
// already signed up for that event.
func NewSignup(username string, event_id int32) (int64, error) {
	res, err := db.Exec(`
		INSERT INTO signups (username, event_id) VALUES (?, ?)
		ON CONFLICT (event_id, username) DO NOTHING`,
		username, event_id)
	if err != nil {
		return 0, err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}
	if n == 0 {
		return 0, errDuplicate
	}
	return res.LastInsertId()
}

func GetByID(id int32) (Signup, error) {
	var a Signup
	err := db.QueryRow(`SELECT id, username, event_id, presence_confirmed FROM signups WHERE id = ?`,
		id,
	).Scan(&a.ID, &a.Username, &a.EventID, &a.PresenceConfirmed)

	return a, err
}

// RegisterPresence returns sql.ErrNoRows if there is no such signup.
func RegisterPresence(a Signup) error {
	res, err := db.Exec(`UPDATE signups SET presence_confirmed = ? WHERE username = ? AND event_id = ?`,
		a.PresenceConfirmed, a.Username, a.EventID)
	if err != nil {
		return err
	}
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}
