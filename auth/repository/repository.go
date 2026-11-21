package repository

import (
	"crypto/sha512"
	"database/sql"
	"uuid"

	_ "modernc.org/sqlite"
)

type Credential struct {
	Username string
	Password [sha512.Size]byte
}

var db *sql.DB

// Open opens (creating if needed) the SQLite database at path. It must be
// called before any other function of this package.
func Open(path string) error {
	conn, err := sql.Open("sqlite", path)
	if err != nil {
		return err
	}
	_, err = conn.Exec(`
		CREATE TABLE IF NOT EXISTS credentials (
			username TEXT NOT NULL UNIQUE,
			password BLOB NOT NULL CHECK (LENGTH(password) == 64)
		)`)
	if err != nil {
		conn.Close()
		return err
	}
	_, err = conn.Exec(`
		CREATE TABLE IF NOT EXISTS sessions (
            token BLOB CHECK (LENGTH(token) == 16)
		)`)
	if err != nil {
		conn.Close()
		return err
	}
	db = conn
	return nil
}

// Close closes the database opened by Open.
func Close() error {
	return db.Close()
}

func NewCredential(c Credential) error {
	_, err := db.Exec(
		`INSERT INTO credentials (username, password) VALUES (?, ?)`,
		c.Username, c.Password[:],
	)
	return err
}

func GetByUsername(username string) (Credential, error) {
	var c Credential
	var password []byte
	err := db.QueryRow(
		`SELECT username, password FROM credentials WHERE username = ?`,
		username,
	).Scan(&c.Username, &password)
	copy(c.Password[:], password)
	return c, err
}

func NewSession(token uuid.UUID) error {
	_, err := db.Exec(
		`INSERT INTO sessions (token) VALUES (?)`, token[:],
	)
	return err
}

func SessionExists(token uuid.UUID) error {
	var t uuid.UUID
	err := db.QueryRow(
		`SELECT token FROM sessions WHERE token = ?`,
		token[:],
	).Scan(&t)
	return err
}

func DeleteSession(token uuid.UUID) error {
	_, err := db.Exec(
		`DELETE FROM sessions WHERE token = ?`, token[:],
	)
	return err
}
