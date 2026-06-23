package writeback

import (
	"bytes"
	"encoding/binary"
	"io"
	"os"
	"strconv"
	"strings"

	"nas-music-agent/internal/metadata"
)

var textFrameToField = map[string]string{
	"TIT2": "title",
	"TPE1": "artist",
	"TALB": "album",
	"TPE2": "albumArtist",
	"TCON": "genre",
	"TDRC": "year",
	"TRCK": "track",
	"TPOS": "disc",
	"TCOM": "composer",
	"COMM": "comment",
}

var fieldToTextFrame = map[string]string{
	"title":       "TIT2",
	"artist":      "TPE1",
	"album":       "TALB",
	"albumArtist": "TPE2",
	"genre":       "TCON",
	"year":        "TDRC",
	"track":       "TRCK",
	"disc":        "TPOS",
	"composer":    "TCOM",
	"comment":     "COMM",
}

type id3Tag struct {
	versionMajor byte
	frames       []id3Frame
	audioOffset  int64
}

type id3Frame struct {
	id   string
	data []byte
}

func readMP3Metadata(path string) (metadata.AudioMetadata, error) {
	tag, err := readID3Tag(path)
	if err != nil {
		return metadata.AudioMetadata{}, err
	}
	var md metadata.AudioMetadata
	for _, frame := range tag.frames {
		value := readTextFrame(frame)
		switch textFrameToField[frame.id] {
		case "title":
			md.Title = stringPtr(value)
		case "artist":
			md.Artist = stringPtr(value)
		case "album":
			md.Album = stringPtr(value)
		case "albumArtist":
			md.AlbumArtist = stringPtr(value)
		case "genre":
			md.Genre = stringPtr(value)
		case "year":
			if year, ok := parseInt(value); ok {
				md.Year = &year
			}
		case "track":
			number, total := parsePair(value)
			md.TrackNumber = number
			md.TrackTotal = total
		case "disc":
			number, total := parsePair(value)
			md.DiscNumber = number
			md.DiscTotal = total
		case "composer":
			md.Composer = stringPtr(value)
		case "comment":
			md.Comment = stringPtr(value)
		}
	}
	return md, nil
}

func writeMP3Metadata(path string, patch metadata.AudioMetadata) error {
	tag, err := readID3Tag(path)
	if err != nil {
		return err
	}
	audio, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	audio = audio[tag.audioOffset:]

	frameMap := map[string]id3Frame{}
	order := make([]string, 0, len(tag.frames))
	for _, frame := range tag.frames {
		frameMap[frame.id] = frame
		order = append(order, frame.id)
	}
	setText := func(field string, value *string) {
		if value == nil {
			return
		}
		id := fieldToTextFrame[field]
		if _, ok := frameMap[id]; !ok {
			order = append(order, id)
		}
		frameMap[id] = id3Frame{id: id, data: encodeTextFrame(*value)}
	}
	setInt := func(field string, value *int) {
		if value == nil {
			return
		}
		text := strconv.Itoa(*value)
		setText(field, &text)
	}
	setPair := func(field string, number, total *int) {
		if number == nil && total == nil {
			return
		}
		left := ""
		if number != nil {
			left = strconv.Itoa(*number)
		}
		if total != nil {
			left += "/" + strconv.Itoa(*total)
		}
		setText(field, &left)
	}

	setText("title", patch.Title)
	setText("artist", patch.Artist)
	setText("album", patch.Album)
	setText("albumArtist", patch.AlbumArtist)
	setText("genre", patch.Genre)
	setInt("year", patch.Year)
	setPair("track", patch.TrackNumber, patch.TrackTotal)
	setPair("disc", patch.DiscNumber, patch.DiscTotal)
	setText("comment", patch.Comment)
	setText("composer", patch.Composer)

	var frames bytes.Buffer
	seen := map[string]bool{}
	for _, id := range order {
		if seen[id] {
			continue
		}
		seen[id] = true
		frame := frameMap[id]
		if len(frame.id) != 4 || len(frame.data) == 0 {
			continue
		}
		frames.WriteString(frame.id)
		frames.Write(encodeSynchsafe(len(frame.data)))
		frames.Write([]byte{0, 0})
		frames.Write(frame.data)
	}
	header := []byte{'I', 'D', '3', 4, 0, 0}
	header = append(header, encodeSynchsafe(frames.Len())...)
	output := append(header, frames.Bytes()...)
	output = append(output, audio...)
	return os.WriteFile(path, output, 0o644)
}

func readID3Tag(path string) (id3Tag, error) {
	file, err := os.Open(path)
	if err != nil {
		return id3Tag{}, err
	}
	defer file.Close()
	header := make([]byte, 10)
	if _, err := io.ReadFull(file, header); err != nil {
		return id3Tag{versionMajor: 4, audioOffset: 0}, nil
	}
	if string(header[:3]) != "ID3" {
		return id3Tag{versionMajor: 4, audioOffset: 0}, nil
	}
	size := decodeSynchsafe(header[6:10])
	body := make([]byte, size)
	if _, err := io.ReadFull(file, body); err != nil {
		return id3Tag{}, err
	}
	tag := id3Tag{versionMajor: header[3], audioOffset: int64(10 + size)}
	offset := 0
	for offset+10 <= len(body) {
		id := string(body[offset : offset+4])
		if strings.Trim(id, "\x00") == "" {
			break
		}
		var frameSize int
		if tag.versionMajor == 4 {
			frameSize = decodeSynchsafe(body[offset+4 : offset+8])
		} else {
			frameSize = int(binary.BigEndian.Uint32(body[offset+4 : offset+8]))
		}
		if frameSize <= 0 || offset+10+frameSize > len(body) {
			break
		}
		data := make([]byte, frameSize)
		copy(data, body[offset+10:offset+10+frameSize])
		tag.frames = append(tag.frames, id3Frame{id: id, data: data})
		offset += 10 + frameSize
	}
	return tag, nil
}

func readTextFrame(frame id3Frame) string {
	if len(frame.data) == 0 {
		return ""
	}
	switch frame.data[0] {
	case 3:
		return strings.TrimRight(string(frame.data[1:]), "\x00")
	case 0:
		return strings.TrimRight(string(frame.data[1:]), "\x00")
	default:
		return strings.TrimRight(string(frame.data[1:]), "\x00")
	}
}

func encodeTextFrame(value string) []byte {
	return append([]byte{3}, []byte(value)...)
}

func encodeSynchsafe(value int) []byte {
	return []byte{
		byte((value >> 21) & 0x7f),
		byte((value >> 14) & 0x7f),
		byte((value >> 7) & 0x7f),
		byte(value & 0x7f),
	}
}

func decodeSynchsafe(value []byte) int {
	if len(value) != 4 {
		return 0
	}
	return int(value[0])<<21 | int(value[1])<<14 | int(value[2])<<7 | int(value[3])
}

func parseInt(value string) (int, bool) {
	value = strings.TrimSpace(value)
	if len(value) >= 4 {
		value = value[:4]
	}
	parsed, err := strconv.Atoi(value)
	return parsed, err == nil
}

func parsePair(value string) (*int, *int) {
	parts := strings.SplitN(value, "/", 2)
	var number, total *int
	if parsed, ok := parseInt(parts[0]); ok {
		number = &parsed
	}
	if len(parts) == 2 {
		if parsed, ok := parseInt(parts[1]); ok {
			total = &parsed
		}
	}
	return number, total
}

func stringPtr(value string) *string {
	value = strings.TrimSpace(value)
	if value == "" {
		return nil
	}
	return &value
}
