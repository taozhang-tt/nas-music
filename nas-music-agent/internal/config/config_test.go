package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFromFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nasmusic-agent.json")
	data := `{
  "listenAddr": "0.0.0.0:2302",
  "apiToken": "secret",
  "musicRoots": ["/volume2/music"],
  "libraryIndex": "/var/services/homes/admin/nasmusic-agent-test/library-index.json",
  "backupDir": "/var/services/homes/admin/nasmusic-agent-test/backup"
}`
	if err := os.WriteFile(path, []byte(data), 0o600); err != nil {
		t.Fatal(err)
	}

	cfg, err := FromFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.ListenAddr != "0.0.0.0:2302" {
		t.Fatalf("ListenAddr = %q", cfg.ListenAddr)
	}
	if cfg.APIToken != "secret" {
		t.Fatalf("APIToken = %q", cfg.APIToken)
	}
	if len(cfg.MusicRoots) != 1 || cfg.MusicRoots[0] != "/volume2/music" {
		t.Fatalf("MusicRoots = %#v", cfg.MusicRoots)
	}
}

func TestFromFileValidatesRequiredFields(t *testing.T) {
	path := filepath.Join(t.TempDir(), "nasmusic-agent.json")
	if err := os.WriteFile(path, []byte(`{"listenAddr":"0.0.0.0:2302"}`), 0o600); err != nil {
		t.Fatal(err)
	}

	_, err := FromFile(path)
	if err == nil {
		t.Fatal("expected validation error")
	}
	if !strings.Contains(err.Error(), "apiToken is required") {
		t.Fatalf("unexpected error: %v", err)
	}
}
