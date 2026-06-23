package library

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
)

var ErrSongNotFound = errors.New("song not found")
var ErrPathNotAllowed = errors.New("path not allowed")

type Library struct {
	roots   []string
	entries map[string]string
}

func New(roots []string, indexPath string) (*Library, error) {
	resolved := make([]string, 0, len(roots))
	for _, root := range roots {
		abs, err := filepath.Abs(root)
		if err != nil {
			return nil, err
		}
		abs, err = filepath.EvalSymlinks(abs)
		if err != nil {
			return nil, err
		}
		info, err := os.Stat(abs)
		if err != nil {
			return nil, err
		}
		if !info.IsDir() {
			return nil, ErrPathNotAllowed
		}
		resolved = append(resolved, abs)
	}
	l := &Library{roots: resolved, entries: map[string]string{}}
	if err := l.loadIndex(indexPath); err != nil {
		return nil, err
	}
	return l, nil
}

func (l *Library) Resolve(sourceID string) (string, error) {
	if strings.Contains(sourceID, "..") || strings.ContainsAny(sourceID, `/\`) {
		return "", ErrPathNotAllowed
	}
	path, ok := l.entries[sourceID]
	if !ok {
		return "", ErrSongNotFound
	}
	return l.ensureAllowed(path)
}

func (l *Library) ensureAllowed(path string) (string, error) {
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", err
	}
	abs, err = filepath.EvalSymlinks(abs)
	if err != nil {
		return "", err
	}
	for _, root := range l.roots {
		rel, err := filepath.Rel(root, abs)
		if err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
			return abs, nil
		}
	}
	return "", ErrPathNotAllowed
}

func (l *Library) loadIndex(indexPath string) error {
	data, err := os.ReadFile(indexPath)
	if err != nil {
		return err
	}
	var index struct {
		Songs []struct {
			SourceID string `json:"sourceId"`
			Path     string `json:"path"`
		} `json:"songs"`
	}
	if err := json.Unmarshal(data, &index); err != nil {
		return err
	}
	for _, song := range index.Songs {
		if song.SourceID == "" || song.Path == "" {
			continue
		}
		l.entries[song.SourceID] = song.Path
	}
	return nil
}
