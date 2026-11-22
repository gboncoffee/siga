package main

import (
	"flag"
	"log"
	"net/http"
	"strings"
)

var authURL string
var eventURL string

func main() {
	var port string
	var addr string

	flag.StringVar(&port, "port", "8081", "port to listen to")
	flag.StringVar(&addr, "address", "localhost", "address to listen to")
	flag.StringVar(&authURL, "auth-url", "http://localhost:8080", "base URL of the auth service")
	flag.StringVar(&eventURL, "event-url", "http://localhost:16000", "base URL of the event service")

	var dbPath string
	flag.StringVar(&dbPath, "db", "db.db", "path of the SQLite database")

	flag.Parse()

	authURL = strings.TrimRight(authURL, "/")
	eventURL = strings.TrimRight(eventURL, "/")

	if err := openDB(dbPath); err != nil {
		log.Fatal(err)
	}

	router()

	log.Println("Listening on " + addr + ":" + port)
	log.Fatal(http.ListenAndServe(addr+":"+port, nil))
}

func router() {
	http.HandleFunc("POST /signup", signup)
	http.HandleFunc("PUT /presence", presence)
	http.HandleFunc("GET /signup/{id}", check_signup)
}
