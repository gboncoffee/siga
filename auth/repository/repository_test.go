package repository

import (
	"crypto/sha512"
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
	if err := SessionExists(token); err == nil {
		t.Fatal("session exists before being created")
	}

	if err := NewSession(token); err != nil {
		t.Fatalf("NewSession: %v", err)
	}
	if err := SessionExists(token); err != nil {
		t.Fatalf("SessionExists after NewSession: %v", err)
	}

	if err := DeleteSession(token); err != nil {
		t.Fatalf("DeleteSession: %v", err)
	}
	if err := SessionExists(token); err == nil {
		t.Fatal("session still exists after DeleteSession")
	}
}

func TestDeletingOneSessionKeepsOthers(t *testing.T) {
	a, b := uuid.New(), uuid.New()
	for _, token := range []uuid.UUID{a, b} {
		if err := NewSession(token); err != nil {
			t.Fatalf("NewSession: %v", err)
		}
	}

	if err := DeleteSession(a); err != nil {
		t.Fatalf("DeleteSession: %v", err)
	}
	if err := SessionExists(b); err != nil {
		t.Errorf("other session was removed: %v", err)
	}
}
