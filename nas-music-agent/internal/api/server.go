package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"nas-music-agent/internal/config"
	"nas-music-agent/internal/library"
	"nas-music-agent/internal/metadata"
	"nas-music-agent/internal/opencc"
	"nas-music-agent/internal/writeback"
)

type Server struct {
	cfg       config.Config
	library   *library.Library
	writeback *writeback.Service
}

func New(cfg config.Config, lib *library.Library, wb *writeback.Service) *Server {
	return &Server{cfg: cfg, library: lib, writeback: wb}
}

func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", s.health)
	mux.HandleFunc("GET /v1/songs/{sourceId}/metadata", s.withAuth(s.readMetadata))
	mux.HandleFunc("POST /v1/songs/{sourceId}/metadata/preview", s.withAuth(s.previewMetadata))
	mux.HandleFunc("PATCH /v1/songs/{sourceId}/metadata", s.withAuth(s.writeMetadata))
	mux.HandleFunc("POST /v1/operations/{operationId}/rollback", s.withAuth(s.rollback))
	return mux
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"status":                  "ok",
		"version":                 "0.1.0",
		"tagWriterAvailable":      true,
		"openCCAvailable":         false,
		"musicDirectoryWritable":  true,
		"backupDirectoryWritable": true,
	})
}

func (s *Server) readMetadata(w http.ResponseWriter, r *http.Request) {
	sourceID := r.PathValue("sourceId")
	path, err := s.library.Resolve(sourceID)
	if err != nil {
		writeError(w, err)
		return
	}
	envelope, err := s.writeback.Read(sourceID, path)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, envelope)
}

func (s *Server) previewMetadata(w http.ResponseWriter, r *http.Request) {
	sourceID := r.PathValue("sourceId")
	path, err := s.library.Resolve(sourceID)
	if err != nil {
		writeError(w, err)
		return
	}
	envelope, err := s.writeback.Read(sourceID, path)
	if err != nil {
		writeError(w, err)
		return
	}
	var req struct {
		ConvertToSimplified bool                   `json:"convertToSimplified"`
		Fields              []string               `json:"fields"`
		ManualPatch         metadata.AudioMetadata `json:"manualPatch"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	if req.ConvertToSimplified {
		req.ManualPatch = applySimplified(envelope.Metadata, req.ManualPatch, req.Fields)
	}
	writeJSON(w, http.StatusOK, s.writeback.Preview(envelope.Metadata, req.ManualPatch))
}

func (s *Server) writeMetadata(w http.ResponseWriter, r *http.Request) {
	sourceID := r.PathValue("sourceId")
	path, err := s.library.Resolve(sourceID)
	if err != nil {
		writeError(w, err)
		return
	}
	var req struct {
		ExpectedRevision string                 `json:"expectedRevision"`
		Patch            metadata.AudioMetadata `json:"patch"`
		CreateBackup     bool                   `json:"createBackup"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid json", http.StatusBadRequest)
		return
	}
	result, err := s.writeback.Write(sourceID, path, req.Patch, req.ExpectedRevision)
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) rollback(w http.ResponseWriter, r *http.Request) {
	if err := s.writeback.Rollback(r.PathValue("operationId")); err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *Server) withAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := strings.TrimPrefix(r.Header.Get("Authorization"), "Bearer ")
		if token == "" || token != s.cfg.APIToken {
			writeErrorResponse(w, http.StatusUnauthorized, "unauthorized", "unauthorized")
			return
		}
		next(w, r)
	}
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, library.ErrSongNotFound):
		writeErrorResponse(w, http.StatusNotFound, "songNotFound", "song not found")
	case errors.Is(err, library.ErrPathNotAllowed):
		writeErrorResponse(w, http.StatusForbidden, "pathNotAllowed", "path not allowed")
	case errors.Is(err, writeback.ErrUnsupportedFormat):
		writeErrorResponse(w, http.StatusUnsupportedMediaType, "unsupportedFormat", "unsupported format")
	case errors.Is(err, writeback.ErrFileChanged):
		writeErrorResponse(w, http.StatusConflict, "fileChanged", "file changed")
	case errors.Is(err, writeback.ErrFileLocked):
		writeErrorResponse(w, http.StatusLocked, "fileLocked", "file locked")
	case errors.Is(err, writeback.ErrValidationFailed):
		writeErrorResponse(w, http.StatusInternalServerError, "validationFailed", "validation failed")
	case errors.Is(err, writeback.ErrRollbackFailed):
		writeErrorResponse(w, http.StatusInternalServerError, "rollbackFailed", "rollback failed")
	case errors.Is(err, writeback.ErrOperationNotFound):
		writeErrorResponse(w, http.StatusNotFound, "operationNotFound", "operation not found")
	default:
		writeErrorResponse(w, http.StatusInternalServerError, "unknown", "internal error")
	}
}

func writeErrorResponse(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]string{
		"error":   code,
		"message": message,
	})
}

func applySimplified(before metadata.AudioMetadata, patch metadata.AudioMetadata, fields []string) metadata.AudioMetadata {
	selected := map[string]bool{}
	for _, field := range fields {
		selected[field] = true
	}
	convert := func(field string, patched *string, current *string) *string {
		if !selected[field] {
			return patched
		}
		if patched != nil {
			value := opencc.T2S(*patched)
			return &value
		}
		if current == nil {
			return nil
		}
		value := opencc.T2S(*current)
		return &value
	}
	patch.Title = convert("title", patch.Title, before.Title)
	patch.Artist = convert("artist", patch.Artist, before.Artist)
	patch.Album = convert("album", patch.Album, before.Album)
	patch.AlbumArtist = convert("albumArtist", patch.AlbumArtist, before.AlbumArtist)
	patch.Genre = convert("genre", patch.Genre, before.Genre)
	patch.Composer = convert("composer", patch.Composer, before.Composer)
	return patch
}
