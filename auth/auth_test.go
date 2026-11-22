package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"uuid"

	"github.com/gboncoffee/siga/auth/repository"
)

// server answers requests through the real routes of the service, backed by
// a temporary database.
var server *httptest.Server

func TestMain(m *testing.M) {
	dir, err := os.MkdirTemp("", "siga-auth")
	if err != nil {
		panic(err)
	}
	if err := repository.Open(filepath.Join(dir, "test.db")); err != nil {
		panic(err)
	}
	router()
	server = httptest.NewServer(http.DefaultServeMux)

	code := m.Run()

	server.Close()
	repository.Close()
	os.RemoveAll(dir)
	os.Exit(code)
}

func request(t *testing.T, method, path, body string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(method, server.URL+path, strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
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

func createCredentials(t *testing.T, username, password string) {
	t.Helper()
	body := `{"Username": "` + username + `", "Password": "` + password + `"}`
	expectStatus(t, request(t, "POST", "/credentials", body), http.StatusOK)
}

// loginAs logs in and returns the session token.
func loginAs(t *testing.T, username, password string) string {
	t.Helper()
	body := `{"Username": "` + username + `", "Password": "` + password + `"}`
	res := request(t, "POST", "/login", body)
	expectStatus(t, res, http.StatusOK)

	if ct := res.Header.Get("Content-Type"); ct != "application/json" {
		t.Errorf("Content-Type = %q, want application/json", ct)
	}
	var out LoginResponse
	if err := json.NewDecoder(res.Body).Decode(&out); err != nil {
		t.Fatalf("decoding login response: %v", err)
	}
	return out.Token.String()
}

func TestLoginLogoutFlow(t *testing.T) {
	createCredentials(t, "ana", "segredo")
	token := loginAs(t, "ana", "segredo")

	res := request(t, "GET", "/"+token, "")
	expectStatus(t, res, http.StatusOK)
	var out AuthenticatedResponse
	if err := json.NewDecoder(res.Body).Decode(&out); err != nil {
		t.Fatalf("decoding GET /{uuid} response: %v", err)
	}
	if out.Username != "ana" {
		t.Errorf("GET /{uuid}: Username = %q, want %q", out.Username, "ana")
	}

	expectStatus(t, request(t, "POST", "/logout/"+token, ""), http.StatusOK)
	expectStatus(t, request(t, "GET", "/"+token, ""), http.StatusUnauthorized)
}

func TestEachLoginOpensItsOwnSession(t *testing.T) {
	createCredentials(t, "bia", "segredo")
	first := loginAs(t, "bia", "segredo")
	second := loginAs(t, "bia", "segredo")
	if first == second {
		t.Fatal("two logins returned the same token")
	}

	expectStatus(t, request(t, "POST", "/logout/"+first, ""), http.StatusOK)
	expectStatus(t, request(t, "GET", "/"+second, ""), http.StatusOK)
}

func TestLoginWithWrongPassword(t *testing.T) {
	createCredentials(t, "caio", "certa")
	res := request(t, "POST", "/login", `{"Username": "caio", "Password": "errada"}`)
	expectStatus(t, res, http.StatusUnauthorized)
}

func TestLoginWithUnknownUser(t *testing.T) {
	res := request(t, "POST", "/login", `{"Username": "ninguem", "Password": "x"}`)
	expectStatus(t, res, http.StatusUnauthorized)
}

func TestInvalidJSON(t *testing.T) {
	for _, path := range []string{"/login", "/credentials"} {
		expectStatus(t, request(t, "POST", path, "{"), http.StatusBadRequest)
	}
}

func TestDuplicateCredentials(t *testing.T) {
	createCredentials(t, "duda", "a")
	res := request(t, "POST", "/credentials", `{"Username": "duda", "Password": "b"}`)
	expectStatus(t, res, http.StatusInternalServerError)

	// The original password must still work.
	loginAs(t, "duda", "a")
}

func TestUnknownTokenIsUnauthorized(t *testing.T) {
	expectStatus(t, request(t, "GET", "/"+uuid.New().String(), ""), http.StatusUnauthorized)
}

func TestMalformedToken(t *testing.T) {
	expectStatus(t, request(t, "GET", "/nao-e-uuid", ""), http.StatusBadRequest)
	expectStatus(t, request(t, "POST", "/logout/nao-e-uuid", ""), http.StatusBadRequest)
}

func TestWrongMethod(t *testing.T) {
	// GET /login is not here: it matches GET /{uuid} and answers 400.
	expectStatus(t, request(t, "DELETE", "/login", ""), http.StatusMethodNotAllowed)
	expectStatus(t, request(t, "PUT", "/credentials", ""), http.StatusMethodNotAllowed)
}
