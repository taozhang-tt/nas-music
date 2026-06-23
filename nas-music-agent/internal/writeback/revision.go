package writeback

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"syscall"
	"time"
)

func fileRevision(path string) (string, os.FileInfo, error) {
	info, err := os.Stat(path)
	if err != nil {
		return "", nil, err
	}
	inode := uint64(0)
	if stat, ok := info.Sys().(*syscall.Stat_t); ok {
		inode = stat.Ino
	}
	input := fmt.Sprintf("%d:%d:%d", info.Size(), info.ModTime().UTC().UnixNano(), inode)
	sum := sha256.Sum256([]byte(input))
	return hex.EncodeToString(sum[:]), info, nil
}

func sameTechnicalInfo(before, after os.FileInfo) bool {
	const tolerance = 2 * time.Second
	sizeDelta := before.Size() - after.Size()
	if sizeDelta < 0 {
		sizeDelta = -sizeDelta
	}
	return sizeDelta < 1024*1024 && before.ModTime().Sub(after.ModTime()) < tolerance
}
