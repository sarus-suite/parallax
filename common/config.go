package common

import (
	"os"
	"fmt"
	"path/filepath"
)

type Config struct {
    PodmanRoot        string
    RoStoragePath     string
    MksquashfsPath    string
    Image             string
	MksquashfsOpts    []string
}

func IsDir(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if !info.IsDir() {
		return fmt.Errorf("%s is not a directory", path)
	}
	return nil
}

func IsExecutable(path string) error {
	info, err := os.Stat(path)
	if err != nil {
		return err
	}
	if info.IsDir() {
		return fmt.Errorf("%s is a directory, not an executable", path)
	}
	if info.Mode()&0111 == 0 {
		return fmt.Errorf("%s is not executable", path)
	}
	return nil
}

func ValidateRoStore(path string) error {
	fileInfo, err := os.Stat(path)
	if err != nil || !fileInfo.IsDir() {
		return fmt.Errorf("'%s' is not a valid directory", path)
	}

	files, err := os.ReadDir(path)
	if err != nil {
		return fmt.Errorf("failed reading directory '%s': %w", path, err)
	}
	// Quick accept if directory is empty
	if len(files) == 0 {
		return nil
	}

    // Accept any of the common podman-overlay store subdirs is present
    hasSubdirs := false
	storeSubdirs := []string{"overlay", "overlay-images", "overlay-layers"}
	for _, dir := range storeSubdirs {
		fullPath := filepath.Join(path, dir)
		if _, err := os.Stat(fullPath); err == nil {
			// We found a subdir, we can break loop
            hasSubdirs = true
			break
		}
	}
	if !hasSubdirs {
        return fmt.Errorf("storage validation failed, non-empty and does not look like a podman-overlay store")
	}

    // Good enough check, dir looks like a podman overlay store
	return nil
}

