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
    log.Infof("Mirror: rsync from %s to %s (no squash/)", srcPath, mirrorPath)

    // Define PodmanOverlay file and directory patterns for mirror
    allowedPatterns := []string{
        "overlay/",
        "overlay-containers/",
        "overlay-images/",
        "overlay-layers/",
        "storage.lock",
        "userns.lock",
    }

    includePatterns := []string{}
    for _, pattern := range allowedPatterns {
        includePatterns = append(includePatterns, fmt.Sprintf("--include=%s", pattern))
    }

	rsyncArgs := append([]string{"-a"}, includePatterns...)
    rsyncArgs = append(rsyncArgs, "--exclude=*", "--delete")

    log.Infof("Mirror setup: rsync from %s to %s", srcPath, mirrorPath)
    rsyncCmd := append(rsyncArgs, srcPath, mirrorPath)
    cmd := exec.Command("rsync", rsyncCmd...)

    if out, err2 := cmd.CombinedOutput(); err2 != nil {
        os.RemoveAll(mp)
        return "", nil, fmt.Errorf("Initial rsync failed: %v\n%s", err2, out)
    }

    // In case srcDir is not init, we might not have a squash dir, lets create it
    realSquash := filepath.Join(srcDir, "squash")
    linkName   := filepath.Join(mirrorPath, "squash")
    log.Infof("Mirror: creating squash symlink %s to %s", linkName, realSquash)
    if err := os.MkdirAll(realSquash, 0o755); err != nil {
        return "", nil, fmt.Errorf("Failed to create real squash dir %q: %w", realSquash, err)
    }
    if err2 := os.Symlink(realSquash, linkName); err2 != nil {
        os.RemoveAll(mp)
        return "", nil, fmt.Errorf("Squash symlink failed: %w", err2)
    }

    // On cleanup we remove link then rsync back
    cleanup = func() error {
        log.Infof("Mirror-cleanup: remove mirror’s squash symlink")
        if err := os.Remove(filepath.Join(mirrorPath, "squash")); err != nil {
            return fmt.Errorf("Failed to remove squash symlink: %w", err)
        }

        log.Infof("Mirror-cleanup: rsync back from %s to %s", mirrorPath, srcPath)
        rsyncCmd = append(rsyncArgs, mirrorPath, srcPath)
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

