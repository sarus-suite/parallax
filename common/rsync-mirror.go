package common

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	log "github.com/sirupsen/logrus"
)

// Mirror creates a writable mirror of srcDir in a temp directory.
// It returns the mirror path, a cleanup func (which pushes changes back to srcDir),
// and any error from setup.
//
// Note: this requires the "rsync" binary to be installed and in PATH.
func Mirror(srcDir string) (mirrorDir string, cleanup func() error, err error) {
	log.Infof("Mirror: creating temp dir for %q", srcDir)

	mp, err := os.MkdirTemp("", "rsync-mirror-")
	if err != nil {
		return "", nil, fmt.Errorf("Failed to create temp dir: %w", err)
	}

	srcPath := filepath.Clean(srcDir) + string(os.PathSeparator)
	mirrorPath := filepath.Clean(mp) + string(os.PathSeparator)
	log.Infof("Mirror: rsync from %s to %s", srcPath, mirrorPath)

	// Define PodmanOverlay file and directory patterns for mirror.
	allowedPatterns := []string{
		"overlay/***",
		"overlay-containers/***",
		"overlay-images/***",
		"overlay-layers/***",
		"squash/***",
		"storage.lock",
		"userns.lock",
	}

	includePatterns := []string{}
	for _, pattern := range allowedPatterns {
		includePatterns = append(includePatterns, fmt.Sprintf("--include=%s", pattern))
	}

	setupArgs := append([]string{
		"-rltD",
		"--no-owner",
		"--no-group",
		"--chmod=Du+rwx,Dgo+rx,Fu+rw,Fgo+r",
	}, includePatterns...)
	setupArgs = append(setupArgs, "--exclude=*", "--delete")

	log.Infof("Mirror setup: rsync from %s to %s", srcPath, mirrorPath)
	rsyncCmd := append(setupArgs, srcPath, mirrorPath)
	log.Infof("  rsync args %v", rsyncCmd)
	cmd := exec.Command("rsync", rsyncCmd...)

	if out, err2 := cmd.CombinedOutput(); err2 != nil {
		os.RemoveAll(mp)
		return "", nil, fmt.Errorf("Initial rsync failed: %v\n%s", err2, out)
	}

	if err := os.MkdirAll(filepath.Join(mirrorPath, "squash"), 0o755); err != nil {
		os.RemoveAll(mp)
		return "", nil, fmt.Errorf("Failed to create mirror squash dir: %w", err)
	}

	writeBackArgs := append([]string{
		"-rltD",
		"--no-owner",
		"--no-group",
		"--no-perms",
		"--omit-dir-times",
	}, includePatterns...)
	writeBackArgs = append(writeBackArgs, "--exclude=*", "--delete")

	// On cleanup we push the normalized working copy back without changing
	// destination ownership or access policy.
	cleanup = func() error {
		log.Infof("Mirror-cleanup: rsync back from %s to %s", mirrorPath, srcPath)
		rsyncCmd = append(writeBackArgs, mirrorPath, srcPath)
		cmdBack := exec.Command("rsync", rsyncCmd...)

		if out, err2 := cmdBack.CombinedOutput(); err2 != nil {
			return fmt.Errorf("rsync back failed: %v\n%s", err2, out)
		}

		if err2 := os.RemoveAll(mp); err2 != nil {
			return fmt.Errorf("failed to remove temp dir %q: %w", mp, err2)
		}
		return nil
	}

	return mp, cleanup, nil
}
