package api

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"nas-music-agent/internal/config"
	"nas-music-agent/internal/library"
	"nas-music-agent/internal/metadata"
	"nas-music-agent/internal/writeback"
)

func TestAPIRequiresAuthAndReturnsMetadata(t *testing.T) {
	server := newTestServer(t)
	request := httptest.NewRequest(http.MethodGet, "/v1/songs/12345/metadata", nil)
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", response.Code)
	}

	request = httptest.NewRequest(http.MethodGet, "/v1/songs/12345/metadata", nil)
	request.Header.Set("Authorization", "Bearer token")
	response = httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", response.Code, response.Body.String())
	}
}

func TestAPIPreviewConvertsSelectedTraditionalFields(t *testing.T) {
	server := newTestServer(t)
	body := bytes.NewBufferString(`{"convertToSimplified":true,"fields":["title","artist"],"manualPatch":{}}`)
	request := httptest.NewRequest(http.MethodPost, "/v1/songs/12345/metadata/preview", body)
	request.Header.Set("Authorization", "Bearer token")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, body=%s", response.Code, response.Body.String())
	}
	var decoded struct {
		After struct {
			Title  *string `json:"title"`
			Artist *string `json:"artist"`
		} `json:"after"`
	}
	if err := json.Unmarshal(response.Body.Bytes(), &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.After.Title == nil || *decoded.After.Title != "后来" {
		t.Fatalf("title = %+v, want 后来", decoded.After.Title)
	}
	if decoded.After.Artist == nil || *decoded.After.Artist != "刘若英" {
		t.Fatalf("artist = %+v, want 刘若英", decoded.After.Artist)
	}
}

func TestAPIWriteConflictReturns409(t *testing.T) {
	server := newTestServer(t)
	body := bytes.NewBufferString(`{"expectedRevision":"stale","patch":{"title":"Changed"},"createBackup":true}`)
	request := httptest.NewRequest(http.MethodPatch, "/v1/songs/12345/metadata", body)
	request.Header.Set("Authorization", "Bearer token")
	response := httptest.NewRecorder()
	server.Handler().ServeHTTP(response, request)
	if response.Code != http.StatusConflict {
		t.Fatalf("status = %d, body=%s", response.Code, response.Body.String())
	}
}

func newTestServer(t *testing.T) *Server {
	t.Helper()
	root := t.TempDir()
	audio := filepath.Join(root, "song.mp3")
	title := "後來"
	artist := "劉若英"
	if err := os.WriteFile(audio, []byte{0xff, 0xfb, 0x90, 0x64}, 0o644); err != nil {
		t.Fatal(err)
	}
	wb := writeback.New(filepath.Join(root, "backup"))
	envelope, err := wb.Read("12345", audio)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := wb.Write("12345", audio, metadata.AudioMetadata{Title: &title, Artist: &artist}, envelope.Revision); err != nil {
		t.Fatal(err)
	}
	index := filepath.Join(root, "index.json")
	if err := os.WriteFile(index, []byte(`{"songs":[{"sourceId":"12345","path":"`+audio+`"}]}`), 0o644); err != nil {
		t.Fatal(err)
	}
	lib, err := library.New([]string{root}, index)
	if err != nil {
		t.Fatal(err)
	}
	return New(config.Config{APIToken: "token"}, lib, wb)
}
