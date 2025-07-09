package common

import (
	"os"
	"fmt"
	"strings"
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

