package main

import {
	"flag"
	"log"
	"net/http"
}

// Adapt to my implementation
func main() {
	var port string
	var addr string

	flag.StringVar(&port, "port", "8080", "port to listen to")
	flag.StringVar(&addr, "address", "localhost", "address to listen to")

	flag.Parse()

	router()

	log.Println("Listening on " + addr + ":" + port)
	log.Fatal(http.ListenAndServe(addr+":"+port, nil))
}
