package writeback

import "errors"

var ErrUnsupportedFormat = errors.New("unsupported format")
var ErrFileChanged = errors.New("file changed")
var ErrFileLocked = errors.New("file locked")
var ErrValidationFailed = errors.New("validation failed")
var ErrRollbackFailed = errors.New("rollback failed")
var ErrOperationNotFound = errors.New("operation not found")
