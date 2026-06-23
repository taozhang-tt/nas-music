package main

import (
	"flag"
	"log"
	"net/http"

	"nas-music-agent/internal/api"
	"nas-music-agent/internal/config"
	"nas-music-agent/internal/library"
	"nas-music-agent/internal/writeback"
)

func main() {
	configPath := flag.String("config", "", "path to NASMusic Agent JSON config")
	flag.Parse()

	cfg, source, err := config.Load(*configPath)
	if err != nil {
		log.Fatal(err)
	}
	lib, err := library.New(cfg.MusicRoots, cfg.LibraryIndex)
	if err != nil {
		log.Fatal(err)
	}
	server := api.New(cfg, lib, writeback.New(cfg.BackupDir))
	log.Printf("NASMusic Agent config source: %s", source)
	log.Printf("NASMusic Agent listening on %s", cfg.ListenAddr)
	log.Fatal(http.ListenAndServe(cfg.ListenAddr, server.Handler()))
}
