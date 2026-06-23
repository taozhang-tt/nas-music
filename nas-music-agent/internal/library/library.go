package library

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

var ErrSongNotFound = errors.New("song not found")
var ErrPathNotAllowed = errors.New("path not allowed")

type Library struct {
	roots     []string
	indexPath string
	mu        sync.RWMutex
	entries   map[string]string
}

type IndexSong struct {
	SourceID string `json:"sourceId"`
	Path     string `json:"path"`
	Title    string `json:"title,omitempty"`
	Artist   string `json:"artist,omitempty"`
	Album    string `json:"album,omitempty"`
}

type IndexRejectedSong struct {
	SourceID string `json:"sourceId"`
	Reason   string `json:"reason"`
}

type IndexUpdateResult struct {
	AcceptedCount int                 `json:"acceptedCount"`
	RejectedCount int                 `json:"rejectedCount"`
	Rejected      []IndexRejectedSong `json:"rejected,omitempty"`
	SongCount     int                 `json:"songCount"`
}

type IndexStatus struct {
	SongCount int        `json:"songCount"`
	UpdatedAt *time.Time `json:"updatedAt,omitempty"`
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
	l := &Library{roots: resolved, indexPath: indexPath, entries: map[string]string{}}
	if err := l.loadIndex(indexPath); err != nil {
		return nil, err
	}
	return l, nil
}

func (l *Library) Resolve(sourceID string) (string, error) {
	if strings.Contains(sourceID, "..") || strings.ContainsAny(sourceID, `/\`) {
		return "", ErrPathNotAllowed
	}
	l.mu.RLock()
	path, ok := l.entries[sourceID]
	l.mu.RUnlock()
	if !ok {
		return "", ErrSongNotFound
	}
	return l.ensureAllowed(path)
}

func (l *Library) Update(songs []IndexSong) (IndexUpdateResult, error) {
	result := IndexUpdateResult{}
	l.mu.Lock()
	defer l.mu.Unlock()

	next := make(map[string]string, len(l.entries)+len(songs))
	for sourceID, path := range l.entries {
		next[sourceID] = path
	}

	for _, song := range songs {
		sourceID := strings.TrimSpace(song.SourceID)
		path := strings.TrimSpace(song.Path)
		if sourceID == "" || path == "" || strings.Contains(sourceID, "..") || strings.ContainsAny(sourceID, `/\`) {
			result.Rejected = append(result.Rejected, IndexRejectedSong{SourceID: sourceID, Reason: "invalid sourceId or path"})
			continue
		}
		resolved, err := l.ensureAllowed(path)
		if err != nil {
			result.Rejected = append(result.Rejected, IndexRejectedSong{SourceID: sourceID, Reason: err.Error()})
			continue
		}
		next[sourceID] = resolved
		result.AcceptedCount++
	}

	if result.AcceptedCount > 0 {
		if err := writeIndexAtomic(l.indexPath, next); err != nil {
			return result, err
		}
		l.entries = next
	}
	result.RejectedCount = len(result.Rejected)
	result.SongCount = len(l.entries)
	return result, nil
}

func (l *Library) Status() IndexStatus {
	l.mu.RLock()
	count := len(l.entries)
	l.mu.RUnlock()
	status := IndexStatus{SongCount: count}
	if info, err := os.Stat(l.indexPath); err == nil {
		updatedAt := info.ModTime().UTC()
		status.UpdatedAt = &updatedAt
	}
	return status
}

func (l *Library) ensureAllowed(path string) (string, error) {
	for _, candidate := range l.pathCandidates(path) {
		abs, err := filepath.Abs(candidate)
		if err != nil {
			continue
		}
		abs, err = filepath.EvalSymlinks(abs)
		if err != nil {
			continue
		}
		for _, root := range l.roots {
			rel, err := filepath.Rel(root, abs)
			if err == nil && rel != "." && rel != ".." && !strings.HasPrefix(rel, ".."+string(os.PathSeparator)) {
				return abs, nil
			}
		}
	}
	return "", ErrPathNotAllowed
}

func (l *Library) pathCandidates(path string) []string {
	candidates := []string{path}
	clean := filepath.Clean(path)
	trimmed := strings.TrimLeft(clean, `/\`)
	if trimmed != "" && trimmed != "." {
		for _, root := range l.roots {
			candidates = append(candidates, filepath.Join(root, trimmed))
			rootBase := filepath.Base(root)
			if trimmed == rootBase {
				continue
			}
			prefix := rootBase + string(os.PathSeparator)
			if strings.HasPrefix(trimmed, prefix) {
				candidates = append(candidates, filepath.Join(root, strings.TrimPrefix(trimmed, prefix)))
			}
		}
	}
	return uniqueStrings(candidates)
}

func uniqueStrings(values []string) []string {
	seen := map[string]bool{}
	unique := make([]string, 0, len(values))
	for _, value := range values {
		if value == "" || seen[value] {
			continue
		}
		seen[value] = true
		unique = append(unique, value)
	}
	return unique
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

func writeIndexAtomic(indexPath string, entries map[string]string) error {
	if err := os.MkdirAll(filepath.Dir(indexPath), 0o755); err != nil {
		return err
	}
	songs := make([]IndexSong, 0, len(entries))
	for sourceID, path := range entries {
		songs = append(songs, IndexSong{SourceID: sourceID, Path: path})
	}
	sort.Slice(songs, func(i, j int) bool {
		return songs[i].SourceID < songs[j].SourceID
	})
	payload, err := json.MarshalIndent(struct {
		Songs []IndexSong `json:"songs"`
	}{Songs: songs}, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(indexPath), ".library-index-*.json")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()
	defer os.Remove(tmpPath)
	if _, err := tmp.Write(append(payload, '\n')); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if err := os.Chmod(tmpPath, 0o600); err != nil {
		return err
	}
	return os.Rename(tmpPath, indexPath)
}
