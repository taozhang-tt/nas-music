package config

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

type Config struct {
	ListenAddr   string
	APIToken     string
	MusicRoots   []string
	LibraryIndex string
	BackupDir    string
}

func FromEnv() (Config, error) {
	cfg := Config{
		ListenAddr:   getenv("NASMUSIC_AGENT_ADDR", "127.0.0.1:8088"),
		APIToken:     os.Getenv("NASMUSIC_AGENT_TOKEN"),
		LibraryIndex: os.Getenv("NASMUSIC_LIBRARY_INDEX"),
		BackupDir:    getenv("NASMUSIC_BACKUP_DIR", ".nasmusic-backup"),
	}
	roots := strings.Split(os.Getenv("NASMUSIC_MUSIC_ROOTS"), ":")
	for _, root := range roots {
		root = strings.TrimSpace(root)
		if root != "" {
			cfg.MusicRoots = append(cfg.MusicRoots, root)
		}
	}
	if cfg.APIToken == "" {
		return cfg, errors.New("NASMUSIC_AGENT_TOKEN is required")
	}
	if len(cfg.MusicRoots) == 0 {
		return cfg, errors.New("NASMUSIC_MUSIC_ROOTS is required")
	}
	if cfg.LibraryIndex == "" {
		return cfg, errors.New("NASMUSIC_LIBRARY_INDEX is required")
	}
	return cfg, nil
}

func Load(path string) (Config, string, error) {
	if path != "" {
		cfg, err := FromFile(path)
		return cfg, path, err
	}
	if envPath := os.Getenv("NASMUSIC_AGENT_CONFIG"); envPath != "" {
		cfg, err := FromFile(envPath)
		return cfg, envPath, err
	}
	for _, candidate := range defaultConfigCandidates() {
		if _, err := os.Stat(candidate); err == nil {
			cfg, err := FromFile(candidate)
			return cfg, candidate, err
		}
	}
	cfg, err := FromEnv()
	return cfg, "environment", err
}

func FromFile(path string) (Config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return Config{}, err
	}
	var cfg Config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return Config{}, err
	}
	applyDefaults(&cfg)
	if err := validate(cfg); err != nil {
		return cfg, fmt.Errorf("%s: %w", path, err)
	}
	return cfg, nil
}

func applyDefaults(cfg *Config) {
	if cfg.ListenAddr == "" {
		cfg.ListenAddr = "127.0.0.1:8088"
	}
	if cfg.BackupDir == "" {
		cfg.BackupDir = ".nasmusic-backup"
	}
}

func validate(cfg Config) error {
	if cfg.APIToken == "" {
		return errors.New("apiToken is required")
	}
	if len(cfg.MusicRoots) == 0 {
		return errors.New("musicRoots is required")
	}
	if cfg.LibraryIndex == "" {
		return errors.New("libraryIndex is required")
	}
	return nil
}

func defaultConfigCandidates() []string {
	candidates := []string{
		"nasmusic-agent.json",
		"config.json",
	}
	if executable, err := os.Executable(); err == nil {
		dir := filepath.Dir(executable)
		candidates = append(candidates,
			filepath.Join(dir, "nasmusic-agent.json"),
			filepath.Join(dir, "config.json"),
		)
	}
	return candidates
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}
