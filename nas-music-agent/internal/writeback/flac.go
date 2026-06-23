package writeback

import (
	"bytes"
	"encoding/binary"
	"errors"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"

	"nas-music-agent/internal/metadata"
)

const flacBlockVorbisComment = 4

type flacBlock struct {
	blockType byte
	isLast    bool
	data      []byte
}

func readFLACMetadata(path string) (metadata.AudioMetadata, error) {
	blocks, _, err := readFLACBlocks(path)
	if err != nil {
		return metadata.AudioMetadata{}, err
	}
	for _, block := range blocks {
		if block.blockType == flacBlockVorbisComment {
			return parseVorbisComments(block.data), nil
		}
	}
	return metadata.AudioMetadata{}, nil
}

func writeFLACMetadata(path string, patch metadata.AudioMetadata) error {
	blocks, audio, err := readFLACBlocks(path)
	if err != nil {
		return err
	}
	found := false
	for index, block := range blocks {
		if block.blockType == flacBlockVorbisComment {
			comments := parseVorbisCommentMap(block.data)
			applyVorbisPatch(comments, patch)
			blocks[index].data = buildVorbisComments(comments)
			found = true
			break
		}
	}
	if !found {
		comments := map[string][]string{}
		applyVorbisPatch(comments, patch)
		insertAt := 1
		if len(blocks) == 0 {
			insertAt = 0
		}
		newBlock := flacBlock{blockType: flacBlockVorbisComment, data: buildVorbisComments(comments)}
		blocks = append(blocks[:insertAt], append([]flacBlock{newBlock}, blocks[insertAt:]...)...)
	}

	for index := range blocks {
		blocks[index].isLast = index == len(blocks)-1
	}
	var output bytes.Buffer
	output.WriteString("fLaC")
	for _, block := range blocks {
		if len(block.data) > 0xffffff {
			return ErrValidationFailed
		}
		header := []byte{block.blockType & 0x7f, byte(len(block.data) >> 16), byte(len(block.data) >> 8), byte(len(block.data))}
		if block.isLast {
			header[0] |= 0x80
		}
		output.Write(header)
		output.Write(block.data)
	}
	output.Write(audio)
	return os.WriteFile(path, output.Bytes(), 0o644)
}

func readFLACBlocks(path string) ([]flacBlock, []byte, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, nil, err
	}
	defer file.Close()
	magic := make([]byte, 4)
	if _, err := io.ReadFull(file, magic); err != nil {
		return nil, nil, err
	}
	if string(magic) != "fLaC" {
		return nil, nil, ErrUnsupportedFormat
	}
	var blocks []flacBlock
	for {
		header := make([]byte, 4)
		if _, err := io.ReadFull(file, header); err != nil {
			return nil, nil, err
		}
		size := int(header[1])<<16 | int(header[2])<<8 | int(header[3])
		data := make([]byte, size)
		if _, err := io.ReadFull(file, data); err != nil {
			return nil, nil, err
		}
		block := flacBlock{
			blockType: header[0] & 0x7f,
			isLast:    header[0]&0x80 != 0,
			data:      data,
		}
		blocks = append(blocks, block)
		if block.isLast {
			break
		}
	}
	audio, err := io.ReadAll(file)
	return blocks, audio, err
}

func parseVorbisComments(data []byte) metadata.AudioMetadata {
	comments := parseVorbisCommentMap(data)
	first := func(key string) *string {
		values := comments[key]
		if len(values) == 0 {
			return nil
		}
		value := strings.TrimSpace(values[0])
		if value == "" {
			return nil
		}
		return &value
	}
	var md metadata.AudioMetadata
	md.Title = first("TITLE")
	md.Artist = first("ARTIST")
	md.Album = first("ALBUM")
	md.AlbumArtist = first("ALBUMARTIST")
	md.Genre = first("GENRE")
	md.Comment = first("COMMENT")
	md.Composer = first("COMPOSER")
	if value := first("DATE"); value != nil {
		if year, ok := parseInt(*value); ok {
			md.Year = &year
		}
	}
	if value := first("TRACKNUMBER"); value != nil {
		if number, ok := parseInt(*value); ok {
			md.TrackNumber = &number
		}
	}
	if value := first("TRACKTOTAL"); value != nil {
		if total, ok := parseInt(*value); ok {
			md.TrackTotal = &total
		}
	}
	if value := first("DISCNUMBER"); value != nil {
		if number, ok := parseInt(*value); ok {
			md.DiscNumber = &number
		}
	}
	if value := first("DISCTOTAL"); value != nil {
		if total, ok := parseInt(*value); ok {
			md.DiscTotal = &total
		}
	}
	return md
}

func parseVorbisCommentMap(data []byte) map[string][]string {
	result := map[string][]string{}
	reader := bytes.NewReader(data)
	vendor, err := readVorbisString(reader)
	if err != nil || vendor == "" {
		return result
	}
	var count uint32
	if err := binary.Read(reader, binary.LittleEndian, &count); err != nil {
		return result
	}
	for i := uint32(0); i < count; i++ {
		comment, err := readVorbisString(reader)
		if err != nil {
			break
		}
		key, value, ok := strings.Cut(comment, "=")
		if !ok {
			continue
		}
		key = strings.ToUpper(strings.TrimSpace(key))
		result[key] = append(result[key], value)
	}
	return result
}

func buildVorbisComments(comments map[string][]string) []byte {
	var output bytes.Buffer
	writeVorbisString(&output, "NASMusic Agent")
	keys := make([]string, 0, len(comments))
	for key := range comments {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	count := uint32(0)
	for _, key := range keys {
		count += uint32(len(comments[key]))
	}
	_ = binary.Write(&output, binary.LittleEndian, count)
	for _, key := range keys {
		for _, value := range comments[key] {
			writeVorbisString(&output, key+"="+value)
		}
	}
	return output.Bytes()
}

func readVorbisString(reader *bytes.Reader) (string, error) {
	var size uint32
	if err := binary.Read(reader, binary.LittleEndian, &size); err != nil {
		return "", err
	}
	if size > uint32(reader.Len()) {
		return "", errors.New("invalid vorbis comment size")
	}
	buffer := make([]byte, size)
	_, err := io.ReadFull(reader, buffer)
	return string(buffer), err
}

func writeVorbisString(output *bytes.Buffer, value string) {
	_ = binary.Write(output, binary.LittleEndian, uint32(len([]byte(value))))
	output.WriteString(value)
}

func applyVorbisPatch(comments map[string][]string, patch metadata.AudioMetadata) {
	setString := func(key string, value *string) {
		if value == nil {
			return
		}
		comments[key] = []string{*value}
	}
	setInt := func(key string, value *int) {
		if value == nil {
			return
		}
		comments[key] = []string{strconv.Itoa(*value)}
	}
	setString("TITLE", patch.Title)
	setString("ARTIST", patch.Artist)
	setString("ALBUM", patch.Album)
	setString("ALBUMARTIST", patch.AlbumArtist)
	setString("GENRE", patch.Genre)
	setString("COMMENT", patch.Comment)
	setString("COMPOSER", patch.Composer)
	setInt("DATE", patch.Year)
	setInt("TRACKNUMBER", patch.TrackNumber)
	setInt("TRACKTOTAL", patch.TrackTotal)
	setInt("DISCNUMBER", patch.DiscNumber)
	setInt("DISCTOTAL", patch.DiscTotal)
}
