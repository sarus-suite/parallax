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

func validateRoStorePath(path string) error {
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

	// Validate that at least Podman-overlay Store subdirectories are present
	requiredSubdirs := []string{"overlay", "overlay-images", "overlay-layers"}
	for _, dir := range requiredSubdirs {
		fullPath := filepath.Join(path, dir)
		if err := IsDir(fullPath); err != nil {
			return fmt.Errorf("storage validation failed: %w", err)
		}
	}

	return nil
}

