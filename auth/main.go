package main

import (
	"flag"
	"log"
	"net/http"

	"github.com/gboncoffee/siga/auth/repository"
)

func main() {
	var port string
	var addr string

	flag.StringVar(&port, "port", "8080", "port to listen to")
	flag.StringVar(&addr, "address", "localhost", "address to listen to")

	var dbPath string
	flag.StringVar(&dbPath, "db", "db.db", "path of the SQLite database")

	flag.Parse()

	if err := repository.Open(dbPath); err != nil {
		log.Fatal(err)
	}

	router()

	log.Println("Listening on " + addr + ":" + port)
	log.Fatal(http.ListenAndServe(addr+":"+port, nil))
}
