package common

import (
    "fmt"
    "os"
    "os/exec"
    "path/filepath"
)

// Mirror creates a writable mirror of srcDir in a temp directory.
// It returns the mirror path, a cleanup func (which pushes changes back to srcDir),
// and any error from setup.
//
// Note: this requires the "rsync" binary to be installed and in PATH.
func Mirror(srcDir string) (mirrorDir string, cleanup func() error, err error) {
    mp, err := os.MkdirTemp("", "rsync-mirror-")
    if err != nil {
        return "", nil, fmt.Errorf("failed to create temp dir: %w", err)
    }

    // Ensure the srcDir path ends with a trailing slash for rsync behavior
    srcPath := filepath.Clean(srcDir) + string(os.PathSeparator)
    mirrorPath := filepath.Clean(mp) + string(os.PathSeparator)

    // Setup mirror but skip squash/ dir
    cmd := exec.Command("rsync",
        "-a",
        "--exclude=squash/",
        srcPath, mirrorPath,
    )
    if out, err2 := cmd.CombinedOutput(); err2 != nil {
        os.RemoveAll(mp)
        return "", nil, fmt.Errorf("initial rsync failed: %v\n%s", err2, out)
    }

    // Now we symlink real squash into mirror
    realSquash := filepath.Join(srcDir, "squash")
    linkName   := filepath.Join(mirrorPath, "squash")
    if err2 := os.Symlink(realSquash, linkName); err2 != nil {
        os.RemoveAll(mp)
        return "", nil, fmt.Errorf("squash symlink failed: %w", err2)
    }

    // On cleanup we remove link then rsync back
    cleanup = func() error {
        if err := os.Remove(filepath.Join(mirrorPath, "squash")); err != nil {
            return fmt.Errorf("Failed to remove squash symlink: %w", err)
        }

        cmdBack := exec.Command("rsync",
            "-a",
            "--exclude squash/"
            "--delete",
            mirrorPath, srcPath,
        )
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

