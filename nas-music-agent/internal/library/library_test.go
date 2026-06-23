package library

import (
	"os"
	"path/filepath"
	"testing"
)

func TestResolveUsesIndexAndRejectsMissingSong(t *testing.T) {
	root := t.TempDir()
	audio := filepath.Join(root, "song.mp3")
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	index := filepath.Join(root, "index.json")
	if err := os.WriteFile(index, []byte(`{"songs":[{"sourceId":"12345","path":"`+audio+`"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	lib, err := New([]string{root}, index)
	if err != nil {
		t.Fatal(err)
	}
	resolved, err := lib.Resolve("12345")
	if err != nil {
		t.Fatal(err)
	}
	expected, err := filepath.EvalSymlinks(audio)
	if err != nil {
		t.Fatal(err)
	}
	if resolved != expected {
		t.Fatalf("resolved %q, want %q", resolved, expected)
	}
	if _, err := lib.Resolve("missing"); err != ErrSongNotFound {
		t.Fatalf("missing error = %v, want ErrSongNotFound", err)
	}
}

func TestResolveRejectsTraversalAndPathsOutsideRoot(t *testing.T) {
	root := t.TempDir()
	outside := filepath.Join(t.TempDir(), "song.mp3")
	if err := os.WriteFile(outside, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	index := filepath.Join(root, "index.json")
	if err := os.WriteFile(index, []byte(`{"songs":[{"sourceId":"safe","path":"`+outside+`"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	lib, err := New([]string{root}, index)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := lib.Resolve("../safe"); err != ErrPathNotAllowed {
		t.Fatalf("traversal error = %v, want ErrPathNotAllowed", err)
	}
	if _, err := lib.Resolve("safe"); err != ErrPathNotAllowed {
		t.Fatalf("outside root error = %v, want ErrPathNotAllowed", err)
	}
}
