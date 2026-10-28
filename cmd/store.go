package cmd

import (
	"errors"
	"fmt"
	"path/filepath"

	"parallax/common"
)

// lockAndValidateStore runs before any store setup. Use an absolute destination
// throughout so the mirror's squash symlink also works with relative CLI paths.
func lockAndValidateStore(cfg *common.Config) (func() error, error) {
	path, err := filepath.Abs(cfg.RoStoragePath)
	if err != nil {
		return nil, err
	}
	cfg.RoStoragePath = path
	release, err := common.LockRoStore(path, cfg.LockTimeout)
	if err != nil {
		return nil, err
	}
	if err := common.ValidateRoStore(path); err != nil {
		return nil, errors.Join(fmt.Errorf("Storage validation failed: %w", err), release())
	}
	return release, nil
}
