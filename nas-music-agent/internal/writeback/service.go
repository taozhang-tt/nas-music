package writeback

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"nas-music-agent/internal/metadata"
)

type Service struct {
	backupDir  string
	locksMu    sync.Mutex
	locks      map[string]*sync.Mutex
	operations map[string]OperationRecord
}

type OperationRecord struct {
	OperationID    string                 `json:"operationId"`
	SourceID       string                 `json:"sourceId"`
	OriginalPath   string                 `json:"originalPath"`
	BackupPath     string                 `json:"backupPath"`
	OldRevision    string                 `json:"oldRevision"`
	NewRevision    string                 `json:"newRevision"`
	BeforeMetadata metadata.AudioMetadata `json:"beforeMetadata"`
	AfterMetadata  metadata.AudioMetadata `json:"afterMetadata"`
	CreatedAt      time.Time              `json:"createdAt"`
}

func New(backupDir string) *Service {
	return &Service{
		backupDir:  backupDir,
		locks:      map[string]*sync.Mutex{},
		operations: map[string]OperationRecord{},
	}
}

func (s *Service) Read(sourceID, path string) (metadata.Envelope, error) {
	revision, info, err := fileRevision(path)
	if err != nil {
		return metadata.Envelope{}, err
	}
	format := strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	md, writeSupported, err := s.readMetadata(format, path)
	if err != nil {
		return metadata.Envelope{}, err
	}
	return metadata.Envelope{
		SourceID:       sourceID,
		Revision:       revision,
		Format:         format,
		FileSize:       info.Size(),
		ModifiedAt:     info.ModTime().UTC(),
		Metadata:       md,
		WriteSupported: writeSupported,
	}, nil
}

func (s *Service) Preview(before metadata.AudioMetadata, patch metadata.AudioMetadata) metadata.Preview {
	return metadata.Preview{
		Before:   before,
		After:    merge(before, patch),
		Warnings: nil,
	}
}

func (s *Service) Write(sourceID, path string, patch metadata.AudioMetadata, expectedRevision string) (metadata.WriteResult, error) {
	lock := s.lockFor(path)
	if !lock.TryLock() {
		return metadata.WriteResult{}, ErrFileLocked
	}
	defer lock.Unlock()

	oldRevision, beforeInfo, err := fileRevision(path)
	if err != nil {
		return metadata.WriteResult{}, err
	}
	if expectedRevision != "" && oldRevision != expectedRevision {
		return metadata.WriteResult{}, ErrFileChanged
	}
	format := strings.TrimPrefix(strings.ToLower(filepath.Ext(path)), ".")
	beforeMetadata, supported, err := s.readMetadata(format, path)
	if err != nil {
		return metadata.WriteResult{}, err
	}
	if !supported {
		return metadata.WriteResult{}, ErrUnsupportedFormat
	}

	tempPath := filepath.Join(filepath.Dir(path), fmt.Sprintf(".%s.nasmusic.tmp", filepath.Base(path)))
	backupPath, operationID := s.backupPath(sourceID, filepath.Base(path))
	defer os.Remove(tempPath)

	if err := copyFile(path, tempPath, beforeInfo.Mode()); err != nil {
		return metadata.WriteResult{}, err
	}
	if err := s.writeMetadata(format, tempPath, patch); err != nil {
		return metadata.WriteResult{}, err
	}
	afterMetadata, _, err := s.readMetadata(format, tempPath)
	if err != nil {
		return metadata.WriteResult{}, err
	}
	if !metadataContains(afterMetadata, patch) {
		return metadata.WriteResult{}, ErrValidationFailed
	}
	tempInfo, err := os.Stat(tempPath)
	if err != nil {
		return metadata.WriteResult{}, err
	}
	if tempInfo.Size() == 0 {
		return metadata.WriteResult{}, ErrValidationFailed
	}
	if err := os.MkdirAll(filepath.Dir(backupPath), 0o755); err != nil {
		return metadata.WriteResult{}, err
	}
	if err := copyFile(path, backupPath, beforeInfo.Mode()); err != nil {
		return metadata.WriteResult{}, err
	}
	if err := os.Rename(tempPath, path); err != nil {
		return metadata.WriteResult{}, err
	}
	_ = os.Chmod(path, beforeInfo.Mode())
	newRevision, _, err := fileRevision(path)
	if err != nil {
		return metadata.WriteResult{}, err
	}
	record := OperationRecord{
		OperationID:    operationID,
		SourceID:       sourceID,
		OriginalPath:   path,
		BackupPath:     backupPath,
		OldRevision:    oldRevision,
		NewRevision:    newRevision,
		BeforeMetadata: beforeMetadata,
		AfterMetadata:  afterMetadata,
		CreatedAt:      time.Now().UTC(),
	}
	s.operations[operationID] = record
	_ = s.writeOperationRecord(record)

	return metadata.WriteResult{
		OperationID:   operationID,
		NewRevision:   newRevision,
		BackupCreated: true,
		IndexStatus:   "pending",
		Metadata:      afterMetadata,
	}, nil
}

func (s *Service) Rollback(operationID string) error {
	record, ok := s.operations[operationID]
	if !ok {
		loaded, err := s.readOperationRecord(operationID)
		if err != nil {
			return ErrOperationNotFound
		}
		record = loaded
	}
	lock := s.lockFor(record.OriginalPath)
	lock.Lock()
	defer lock.Unlock()

	tempCurrent := record.OriginalPath + ".nasmusic.rollback-current"
	_ = os.Remove(tempCurrent)
	if err := os.Rename(record.OriginalPath, tempCurrent); err != nil {
		return err
	}
	if err := copyFile(record.BackupPath, record.OriginalPath, 0o644); err != nil {
		_ = os.Rename(tempCurrent, record.OriginalPath)
		return ErrRollbackFailed
	}
	_ = os.Remove(tempCurrent)
	return nil
}

func (s *Service) readMetadata(format, path string) (metadata.AudioMetadata, bool, error) {
	switch format {
	case "mp3":
		md, err := readMP3Metadata(path)
		return md, true, err
	case "flac":
		md, err := readFLACMetadata(path)
		return md, true, err
	default:
		return metadata.AudioMetadata{}, false, nil
	}
}

func (s *Service) writeMetadata(format, path string, patch metadata.AudioMetadata) error {
	switch format {
	case "mp3":
		return writeMP3Metadata(path, patch)
	case "flac":
		return writeFLACMetadata(path, patch)
	default:
		return ErrUnsupportedFormat
	}
}

func (s *Service) lockFor(path string) *sync.Mutex {
	s.locksMu.Lock()
	defer s.locksMu.Unlock()
	lock := s.locks[path]
	if lock == nil {
		lock = &sync.Mutex{}
		s.locks[path] = lock
	}
	return lock
}

func (s *Service) backupPath(sourceID, baseName string) (string, string) {
	now := time.Now().UTC()
	operationID := fmt.Sprintf("%s-%d", sourceID, now.UnixNano())
	return filepath.Join(s.backupDir, now.Format("2006-01-02"), operationID+"-"+baseName), operationID
}

func (s *Service) writeOperationRecord(record OperationRecord) error {
	data, err := json.MarshalIndent(record, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(s.backupDir, "operations", record.OperationID+".json")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o600)
}

func (s *Service) readOperationRecord(operationID string) (OperationRecord, error) {
	data, err := os.ReadFile(filepath.Join(s.backupDir, "operations", operationID+".json"))
	if err != nil {
		return OperationRecord{}, err
	}
	var record OperationRecord
	return record, json.Unmarshal(data, &record)
}

func copyFile(source, destination string, mode os.FileMode) error {
	input, err := os.ReadFile(source)
	if err != nil {
		return err
	}
	if mode == 0 {
		mode = 0o644
	}
	return os.WriteFile(destination, input, mode)
}

func metadataContains(md metadata.AudioMetadata, patch metadata.AudioMetadata) bool {
	checkString := func(actual, expected *string) bool {
		return expected == nil || (actual != nil && *actual == *expected)
	}
	checkInt := func(actual, expected *int) bool {
		return expected == nil || (actual != nil && *actual == *expected)
	}
	return checkString(md.Title, patch.Title) &&
		checkString(md.Artist, patch.Artist) &&
		checkString(md.Album, patch.Album) &&
		checkString(md.AlbumArtist, patch.AlbumArtist) &&
		checkString(md.Genre, patch.Genre) &&
		checkString(md.Comment, patch.Comment) &&
		checkString(md.Composer, patch.Composer) &&
		checkInt(md.Year, patch.Year) &&
		checkInt(md.TrackNumber, patch.TrackNumber) &&
		checkInt(md.TrackTotal, patch.TrackTotal) &&
		checkInt(md.DiscNumber, patch.DiscNumber) &&
		checkInt(md.DiscTotal, patch.DiscTotal)
}

func merge(before metadata.AudioMetadata, patch metadata.AudioMetadata) metadata.AudioMetadata {
	after := before
	if patch.Title != nil {
		after.Title = patch.Title
	}
	if patch.Artist != nil {
		after.Artist = patch.Artist
	}
	if patch.Album != nil {
		after.Album = patch.Album
	}
	if patch.AlbumArtist != nil {
		after.AlbumArtist = patch.AlbumArtist
	}
	if patch.Genre != nil {
		after.Genre = patch.Genre
	}
	if patch.Year != nil {
		after.Year = patch.Year
	}
	if patch.TrackNumber != nil {
		after.TrackNumber = patch.TrackNumber
	}
	if patch.TrackTotal != nil {
		after.TrackTotal = patch.TrackTotal
	}
	if patch.DiscNumber != nil {
		after.DiscNumber = patch.DiscNumber
	}
	if patch.DiscTotal != nil {
		after.DiscTotal = patch.DiscTotal
	}
	if patch.Comment != nil {
		after.Comment = patch.Comment
	}
	if patch.Composer != nil {
		after.Composer = patch.Composer
	}
	return after
}

func IsWritebackError(err error) bool {
	return errors.Is(err, ErrUnsupportedFormat) ||
		errors.Is(err, ErrFileChanged) ||
		errors.Is(err, ErrFileLocked) ||
		errors.Is(err, ErrValidationFailed) ||
		errors.Is(err, ErrRollbackFailed) ||
		errors.Is(err, ErrOperationNotFound)
}
