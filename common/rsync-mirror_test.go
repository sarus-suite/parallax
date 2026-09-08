package common

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func TestMirrorSymlinksSquashAndWritesBackOverlay(t *testing.T) {
	if _, err := exec.LookPath("rsync"); err != nil {
		t.Skip("rsync is required by Mirror")
	}

	srcDir := t.TempDir()
	overlayFile := filepath.Join(srcDir, "overlay", "layer", "data")
	if err := os.MkdirAll(filepath.Dir(overlayFile), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(overlayFile, []byte("before"), 0o644); err != nil {
		t.Fatal(err)
	}

	mirrorDir, cleanup, err := Mirror(srcDir)
	if err != nil {
		t.Fatal(err)
	}

	linkName := filepath.Join(mirrorDir, "squash")
	info, err := os.Lstat(linkName)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode()&os.ModeSymlink == 0 {
		t.Fatalf("mirror squash is not a symlink: mode=%v", info.Mode())
	}
	target, err := os.Readlink(linkName)
	if err != nil {
		t.Fatal(err)
	}
	if target != filepath.Join(srcDir, "squash") {
		t.Fatalf("squash symlink target = %q, want %q", target, filepath.Join(srcDir, "squash"))
	}

	squashFile := filepath.Join(linkName, "layer.squash")
	if err := os.WriteFile(squashFile, []byte("squash"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(srcDir, "squash", "layer.squash")); err != nil {
		t.Fatalf("squash write did not reach source directly: %v", err)
	}

	mirroredOverlayFile := filepath.Join(mirrorDir, "overlay", "layer", "data")
	if err := os.WriteFile(mirroredOverlayFile, []byte("after"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := cleanup(); err != nil {
		t.Fatal(err)
	}

	contents, err := os.ReadFile(overlayFile)
	if err != nil {
		t.Fatal(err)
	}
	if string(contents) != "after" {
		t.Fatalf("source overlay contents = %q, want %q", contents, "after")
	}
	if _, err := os.Lstat(mirrorDir); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("mirror directory remains after cleanup: %v", err)
	}
}
