package repository

import (
	"crypto/sha512"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"uuid"
)

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "siga-auth-repository")
	if err != nil {
		panic(err)
	}
	if err := Open(filepath.Join(dir, "test.db")); err != nil {
		panic(err)
	}
	code := m.Run()
	Close()
	os.RemoveAll(dir)
	os.Exit(code)
}

func TestCredentialRoundTrip(t *testing.T) {
	c := Credential{Username: "ana", Password: sha512.Sum512([]byte("segredo"))}
	if err := NewCredential(c); err != nil {
		t.Fatalf("NewCredential: %v", err)
	}

	got, err := GetByUsername("ana")
	if err != nil {
		t.Fatalf("GetByUsername: %v", err)
	}
	if got != c {
		t.Errorf("GetByUsername = %+v, want %+v", got, c)
	}
}

func TestDuplicateUsernameIsRejected(t *testing.T) {
	c := Credential{Username: "bia", Password: sha512.Sum512([]byte("a"))}
	if err := NewCredential(c); err != nil {
		t.Fatalf("first NewCredential: %v", err)
	}
	c.Password = sha512.Sum512([]byte("b"))
	if err := NewCredential(c); err == nil {
		t.Fatal("second NewCredential with the same username succeeded")
	}

	got, err := GetByUsername("bia")
	if err != nil {
		t.Fatalf("GetByUsername: %v", err)
	}
	if got.Password != sha512.Sum512([]byte("a")) {
		t.Error("the duplicate overwrote the original password")
	}
}

func TestGetByUnknownUsername(t *testing.T) {
	if _, err := GetByUsername("ninguem"); err == nil {
		t.Fatal("GetByUsername of an unknown user returned no error")
	}
}

func TestSessionLifecycle(t *testing.T) {
	token := uuid.New()
	if _, err := SessionUsername(token); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("SessionUsername before NewSession: %v, want sql.ErrNoRows", err)
	}

	if err := NewSession(token, "ana"); err != nil {
		t.Fatalf("NewSession: %v", err)
	}
	username, err := SessionUsername(token)
	if err != nil {
		t.Fatalf("SessionUsername after NewSession: %v", err)
	}
	if username != "ana" {
		t.Errorf("SessionUsername = %q, want %q", username, "ana")
	}

	if err := DeleteSession(token); err != nil {
		t.Fatalf("DeleteSession: %v", err)
	}
	if _, err := SessionUsername(token); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("SessionUsername after DeleteSession: %v, want sql.ErrNoRows", err)
	}
}

func TestDeletingOneSessionKeepsOthers(t *testing.T) {
	a, b := uuid.New(), uuid.New()
	for _, token := range []uuid.UUID{a, b} {
		if err := NewSession(token, "ana"); err != nil {
			t.Fatalf("NewSession: %v", err)
		}
	}

	if err := DeleteSession(a); err != nil {
		t.Fatalf("DeleteSession: %v", err)
	}
	if _, err := SessionUsername(b); err != nil {
		t.Errorf("other session was removed: %v", err)
	}
}

func TestOldSessionsTableIsReplaced(t *testing.T) {
	path := filepath.Join(t.TempDir(), "old.db")
	old, err := sql.Open("sqlite", path)
	if err != nil {
		t.Fatal(err)
	}
	_, err = old.Exec(`CREATE TABLE sessions (token BLOB CHECK (LENGTH(token) == 16))`)
	old.Close()
	if err != nil {
		t.Fatal(err)
	}

	// Open sets the package database; put the test one back afterwards.
	saved := db
	defer func() { db = saved }()
	if err := Open(path); err != nil {
		t.Fatalf("Open with an old sessions table: %v", err)
	}
	defer Close()

	if err := NewSession(uuid.New(), "ana"); err != nil {
		t.Errorf("NewSession on the migrated table: %v", err)
	}
}
