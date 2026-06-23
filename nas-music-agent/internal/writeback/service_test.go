package writeback

import (
	"bytes"
	"encoding/binary"
	"errors"
	"os"
	"path/filepath"
	"testing"

	"nas-music-agent/internal/metadata"
)

func TestReadWriteMP3MetadataAndRollback(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "song.mp3")
	if err := os.WriteFile(path, []byte{0xff, 0xfb, 0x90, 0x64, 0, 1, 2, 3}, 0o644); err != nil {
		t.Fatal(err)
	}
	service := New(filepath.Join(root, "backup"))

	initial, err := service.Read("12345", path)
	if err != nil {
		t.Fatal(err)
	}
	title := "后来"
	artist := "刘若英"
	album := "我等你"
	year := 1999
	result, err := service.Write("12345", path, metadata.AudioMetadata{
		Title:  &title,
		Artist: &artist,
		Album:  &album,
		Year:   &year,
	}, initial.Revision)
	if err != nil {
		t.Fatal(err)
	}
	if !result.BackupCreated || result.OperationID == "" {
		t.Fatalf("missing backup operation: %+v", result)
	}
	after, err := service.Read("12345", path)
	if err != nil {
		t.Fatal(err)
	}
	if after.Metadata.Title == nil || *after.Metadata.Title != title {
		t.Fatalf("title = %+v, want %q", after.Metadata.Title, title)
	}
	if after.Metadata.Artist == nil || *after.Metadata.Artist != artist {
		t.Fatalf("artist = %+v, want %q", after.Metadata.Artist, artist)
	}
	if after.Metadata.Year == nil || *after.Metadata.Year != year {
		t.Fatalf("year = %+v, want %d", after.Metadata.Year, year)
	}
	if after.Revision == initial.Revision {
		t.Fatal("revision did not change after write")
	}
	if err := service.Rollback(result.OperationID); err != nil {
		t.Fatal(err)
	}
	rolledBack, err := service.Read("12345", path)
	if err != nil {
		t.Fatal(err)
	}
	if rolledBack.Metadata.Title != nil {
		t.Fatalf("rollback title = %+v, want nil", rolledBack.Metadata.Title)
	}
}

func TestWriteReturnsConflictForChangedRevision(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "song.mp3")
	if err := os.WriteFile(path, []byte{0xff, 0xfb, 0x90, 0x64}, 0o644); err != nil {
		t.Fatal(err)
	}
	service := New(filepath.Join(root, "backup"))
	envelope, err := service.Read("12345", path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte{0xff, 0xfb, 0x90, 0x64, 0x01}, 0o644); err != nil {
		t.Fatal(err)
	}
	title := "Changed"
	_, err = service.Write("12345", path, metadata.AudioMetadata{Title: &title}, envelope.Revision)
	if !errors.Is(err, ErrFileChanged) {
		t.Fatalf("error = %v, want ErrFileChanged", err)
	}
}

func TestUnsupportedFormatDoesNotModifyFile(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "song.wav")
	original := []byte("wav-data")
	if err := os.WriteFile(path, original, 0o644); err != nil {
		t.Fatal(err)
	}
	service := New(filepath.Join(root, "backup"))
	envelope, err := service.Read("12345", path)
	if err != nil {
		t.Fatal(err)
	}
	title := "Changed"
	_, err = service.Write("12345", path, metadata.AudioMetadata{Title: &title}, envelope.Revision)
	if !errors.Is(err, ErrUnsupportedFormat) {
		t.Fatalf("error = %v, want ErrUnsupportedFormat", err)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != string(original) {
		t.Fatal("unsupported write modified file")
	}
}

func TestReadWriteFLACMetadataAndRollback(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "song.flac")
	if err := os.WriteFile(path, makeTestFLAC(map[string]string{
		"TITLE":  "後來",
		"ARTIST": "劉若英",
	}), 0o644); err != nil {
		t.Fatal(err)
	}
	service := New(filepath.Join(root, "backup"))
	initial, err := service.Read("flac-1", path)
	if err != nil {
		t.Fatal(err)
	}
	if initial.Metadata.Title == nil || *initial.Metadata.Title != "後來" {
		t.Fatalf("initial title = %+v", initial.Metadata.Title)
	}
	title := "后来"
	artist := "刘若英"
	result, err := service.Write("flac-1", path, metadata.AudioMetadata{Title: &title, Artist: &artist}, initial.Revision)
	if err != nil {
		t.Fatal(err)
	}
	after, err := service.Read("flac-1", path)
	if err != nil {
		t.Fatal(err)
	}
	if after.Metadata.Title == nil || *after.Metadata.Title != title {
		t.Fatalf("title = %+v, want %q", after.Metadata.Title, title)
	}
	if after.Metadata.Artist == nil || *after.Metadata.Artist != artist {
		t.Fatalf("artist = %+v, want %q", after.Metadata.Artist, artist)
	}
	if err := service.Rollback(result.OperationID); err != nil {
		t.Fatal(err)
	}
	rolledBack, err := service.Read("flac-1", path)
	if err != nil {
		t.Fatal(err)
	}
	if rolledBack.Metadata.Title == nil || *rolledBack.Metadata.Title != "後來" {
		t.Fatalf("rollback title = %+v, want 後來", rolledBack.Metadata.Title)
	}
}

func makeTestFLAC(comments map[string]string) []byte {
	var output bytes.Buffer
	output.WriteString("fLaC")
	streamInfo := make([]byte, 34)
	output.Write([]byte{0x00, 0x00, 0x00, byte(len(streamInfo))})
	output.Write(streamInfo)
	commentBlock := buildTestVorbisComment(comments)
	output.Write([]byte{0x80 | flacBlockVorbisComment, byte(len(commentBlock) >> 16), byte(len(commentBlock) >> 8), byte(len(commentBlock))})
	output.Write(commentBlock)
	output.Write([]byte{0xff, 0xf8, 0x69, 0x00})
	return output.Bytes()
}

func buildTestVorbisComment(comments map[string]string) []byte {
	var output bytes.Buffer
	writeString := func(value string) {
		_ = binary.Write(&output, binary.LittleEndian, uint32(len([]byte(value))))
		output.WriteString(value)
	}
	writeString("test")
	_ = binary.Write(&output, binary.LittleEndian, uint32(len(comments)))
	for key, value := range comments {
		writeString(key + "=" + value)
	}
	return output.Bytes()
}
