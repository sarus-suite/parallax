package common

import (
	"bufio"
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// TestStoreLockProcess is a separate lock owner, with stdin controlling release.
func TestStoreLockProcess(t *testing.T) {
	path := os.Getenv("PARALLAX_TEST_LOCK_STORE")
	if path == "" {
		return
	}
	release, err := LockRoStore(path, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprintln(os.Stdout, "locked")
	_, _ = io.Copy(io.Discard, os.Stdin)
	if err := release(); err != nil {
		t.Fatal(err)
	}
}

type lockProcess struct {
	cmd    *exec.Cmd
	input  io.WriteCloser
	stderr bytes.Buffer
	done   bool
}

func startLockProcess(t *testing.T, path string) *lockProcess {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	t.Cleanup(cancel)
	p := &lockProcess{cmd: exec.CommandContext(ctx, os.Args[0], "-test.run=^TestStoreLockProcess$")}
	p.cmd.Env = append(os.Environ(), "PARALLAX_TEST_LOCK_STORE="+path)
	p.cmd.Stderr = &p.stderr
	var err error
	p.input, err = p.cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	output, err := p.cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := p.cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if !p.done {
			_ = p.input.Close()
			_ = p.cmd.Wait()
		}
	})
	line, err := bufio.NewReader(output).ReadString('\n')
	if err != nil || line != "locked\n" {
		_ = p.input.Close()
		_ = p.cmd.Wait()
		p.done = true
		t.Fatalf("lock subprocess did not become ready: line=%q err=%v stderr=%s", line, err, &p.stderr)
	}
	return p
}

func TestStoreLockContention(t *testing.T) {
	path := t.TempDir()
	p := startLockProcess(t, path)
	for _, timeout := range []time.Duration{0, 120 * time.Millisecond} {
		start := time.Now()
		_, err := LockRoStore(path, timeout)
		if !errors.Is(err, ErrStoreLockTimeout) || !strings.Contains(err.Error(), path) || !strings.Contains(err.Error(), timeout.String()) {
			t.Fatalf("timeout %s: got %v", timeout, err)
		}
		if elapsed := time.Since(start); elapsed < timeout || elapsed > time.Second {
			t.Fatalf("waited %s for timeout %s", elapsed, timeout)
		}
	}
	if err := p.input.Close(); err != nil {
		t.Fatal(err)
	}
	if err := p.cmd.Wait(); err != nil {
		t.Fatalf("holder failed: %v: %s", err, &p.stderr)
	}
	p.done = true
	release, err := LockRoStore(path, 0)
	if err != nil {
		t.Fatal(err)
	}
	if err := release(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(path, storeLockName)); err != nil {
		t.Fatalf("lock file should persist: %v", err)
	}
}

func TestStoreLockWaitsForRelease(t *testing.T) {
	path := t.TempDir()
	p := startLockProcess(t, path)
	// The subprocess continues holding the lock until this timer closes stdin.
	timer := time.AfterFunc(150*time.Millisecond, func() { _ = p.input.Close() })
	defer timer.Stop()
	start := time.Now()
	release, err := LockRoStore(path, 2*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer release()
	if time.Since(start) < 150*time.Millisecond {
		t.Fatal("acquired before the other process released its lock")
	}
}

func TestStoreLockReleasedOnTermination(t *testing.T) {
	path := t.TempDir()
	p := startLockProcess(t, path)
	if err := p.cmd.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = p.cmd.Wait()
	_ = p.input.Close()
	p.done = true
	release, err := LockRoStore(path, time.Second)
	if err != nil {
		t.Fatal(err)
	}
	if err := release(); err != nil {
		t.Fatal(err)
	}
}

func TestStoreLockIndependentStoresAndAliases(t *testing.T) {
	path := t.TempDir()
	startLockProcess(t, path)
	release, err := LockRoStore(t.TempDir(), 0)
	if err != nil {
		t.Fatalf("unrelated store was blocked: %v", err)
	}
	if err := release(); err != nil {
		t.Fatal(err)
	}
	alias := filepath.Join(t.TempDir(), "alias")
	if err := os.Symlink(path, alias); err != nil {
		t.Fatal(err)
	}
	cwd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	relative, err := filepath.Rel(cwd, path)
	if err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{alias, relative} {
		if _, err := LockRoStore(name, 0); !errors.Is(err, ErrStoreLockTimeout) {
			t.Fatalf("alias %q bypassed lock: %v", name, err)
		}
	}
}

func TestStoreLockErrors(t *testing.T) {
	path := t.TempDir()
	if _, err := LockRoStore(path, -time.Second); err == nil {
		t.Fatal("negative timeout accepted")
	}
	if err := os.Mkdir(filepath.Join(path, storeLockName), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := LockRoStore(path, time.Minute); err == nil || errors.Is(err, ErrStoreLockTimeout) {
		t.Fatalf("expected immediate open error, got %v", err)
	}
}

func TestValidateRoStoreWithLock(t *testing.T) {
	for _, contents := range []string{"empty", "lock", "unrelated", "lock-and-unrelated", "directory", "store"} {
		t.Run(contents, func(t *testing.T) {
			path := t.TempDir()
			if strings.Contains(contents, "lock") {
				if err := os.WriteFile(filepath.Join(path, storeLockName), nil, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			if strings.Contains(contents, "unrelated") {
				if err := os.WriteFile(filepath.Join(path, "unrelated"), nil, 0o600); err != nil {
					t.Fatal(err)
				}
			}
			if contents == "directory" || contents == "store" {
				name := storeLockName
				if contents == "store" {
					name = "overlay-images"
				}
				if err := os.Mkdir(filepath.Join(path, name), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			wantError := strings.Contains(contents, "unrelated") || contents == "directory"
			if err := ValidateRoStore(path); (err != nil) != wantError {
				t.Fatalf("validation error = %v, want error %v", err, wantError)
			}
		})
	}
}
