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

func TestUpdateAcceptsAudioStationVirtualMusicPath(t *testing.T) {
	parent := t.TempDir()
	root := filepath.Join(parent, "music")
	if err := os.Mkdir(root, 0o755); err != nil {
		t.Fatal(err)
	}
	audio := filepath.Join(root, "artist", "song.flac")
	if err := os.MkdirAll(filepath.Dir(audio), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(audio, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	index := filepath.Join(t.TempDir(), "index.json")
	if err := os.WriteFile(index, []byte(`{"songs":[]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	lib, err := New([]string{root}, index)
	if err != nil {
		t.Fatal(err)
	}
	result, err := lib.Update([]IndexSong{
		{SourceID: "relative", Path: "music/artist/song.flac"},
		{SourceID: "absolute-virtual", Path: "/music/artist/song.flac"},
	})
	if err != nil {
		t.Fatal(err)
	}
	if result.AcceptedCount != 2 || result.RejectedCount != 0 {
		t.Fatalf("result = %+v", result)
	}
	for _, sourceID := range []string{"relative", "absolute-virtual"} {
		resolved, err := lib.Resolve(sourceID)
		if err != nil {
			t.Fatal(err)
		}
		expected, err := filepath.EvalSymlinks(audio)
		if err != nil {
			t.Fatal(err)
		}
		if resolved != expected {
			t.Fatalf("%s resolved %q, want %q", sourceID, resolved, expected)
		}
	}
}
