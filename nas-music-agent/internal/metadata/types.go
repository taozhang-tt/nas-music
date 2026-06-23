package metadata

import "time"

type AudioMetadata struct {
	Title       *string `json:"title,omitempty"`
	Artist      *string `json:"artist,omitempty"`
	Album       *string `json:"album,omitempty"`
	AlbumArtist *string `json:"albumArtist,omitempty"`
	Genre       *string `json:"genre,omitempty"`
	Year        *int    `json:"year,omitempty"`
	TrackNumber *int    `json:"trackNumber,omitempty"`
	TrackTotal  *int    `json:"trackTotal,omitempty"`
	DiscNumber  *int    `json:"discNumber,omitempty"`
	DiscTotal   *int    `json:"discTotal,omitempty"`
	Comment     *string `json:"comment,omitempty"`
	Composer    *string `json:"composer,omitempty"`
}

type Envelope struct {
	SourceID       string        `json:"sourceId"`
	Revision       string        `json:"revision"`
	Format         string        `json:"format"`
	FileSize       int64         `json:"fileSize"`
	ModifiedAt     time.Time     `json:"modifiedAt"`
	Metadata       AudioMetadata `json:"metadata"`
	WriteSupported bool          `json:"writeSupported"`
}

type Preview struct {
	Before   AudioMetadata `json:"before"`
	After    AudioMetadata `json:"after"`
	Warnings []string      `json:"warnings"`
}

type WriteResult struct {
	OperationID   string        `json:"operationId"`
	NewRevision   string        `json:"newRevision"`
	BackupCreated bool          `json:"backupCreated"`
	IndexStatus   string        `json:"indexStatus"`
	Metadata      AudioMetadata `json:"metadata"`
}
