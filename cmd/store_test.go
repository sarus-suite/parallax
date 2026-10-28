package cmd

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"parallax/common"
)

func TestWritersLockBeforeStoreSetup(t *testing.T) {
	for _, operation := range []string{"migrate", "rmi"} {
		t.Run(operation, func(t *testing.T) {
			path := t.TempDir()
			release, err := common.LockRoStore(path, 0)
			if err != nil {
				t.Fatal(err)
			}
			defer release()
			cfg := common.Config{RoStoragePath: path, Image: "alpine", PodmanRoot: "/missing", LockTimeout: 10 * time.Millisecond}
			if operation == "migrate" {
				_, err = RunMigration(cfg)
			} else {
				err = RunRmi(cfg)
			}
			if !errors.Is(err, common.ErrStoreLockTimeout) {
				t.Fatalf("writer should wait before accessing stores: %v", err)
			}
			entries, err := os.ReadDir(path)
			if err != nil || len(entries) != 1 || entries[0].Name() != ".parallax.lock" {
				t.Fatalf("store setup ran before lock acquisition: entries=%v err=%v", entries, err)
			}
		})
	}
}

func TestWritersReleaseLockOnValidationFailure(t *testing.T) {
	for _, operation := range []string{"migrate", "rmi"} {
		t.Run(operation, func(t *testing.T) {
			path := t.TempDir()
			if err := os.WriteFile(filepath.Join(path, "unrelated"), nil, 0o600); err != nil {
				t.Fatal(err)
			}
			cfg := common.Config{RoStoragePath: path, Image: "alpine"}
			var err error
			if operation == "migrate" {
				_, err = RunMigration(cfg)
			} else {
				err = RunRmi(cfg)
			}
			if err == nil || !strings.Contains(err.Error(), "Storage validation failed") {
				t.Fatalf("expected validation failure, got %v", err)
			}
			release, err := common.LockRoStore(path, 0)
			if err != nil {
				t.Fatalf("lock was not released after validation failed: %v", err)
			}
			if err := release(); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestWritersReleaseLockOnSetupFailure(t *testing.T) {
	for _, operation := range []string{"migrate", "rmi"} {
		t.Run(operation, func(t *testing.T) {
			path := t.TempDir()
			// Fail the initial mirror without invoking storage setup for rmi.
			bin := t.TempDir()
			if err := os.WriteFile(filepath.Join(bin, "rsync"), []byte("#!/bin/sh\necho injected-setup-failure >&2\nexit 42\n"), 0o755); err != nil {
				t.Fatal(err)
			}
			t.Setenv("PATH", bin)
			// A regular file cannot be used as the source graphroot for migrate.
			source := filepath.Join(t.TempDir(), "not-a-directory")
			if err := os.WriteFile(source, nil, 0o600); err != nil {
				t.Fatal(err)
			}
			cfg := common.Config{RoStoragePath: path, Image: "alpine", PodmanRoot: source}
			var err error
			if operation == "migrate" {
				_, err = RunMigration(cfg)
			} else {
				err = RunRmi(cfg)
			}
			if err == nil {
				t.Fatal("expected setup to fail")
			}
			if operation == "rmi" && !strings.Contains(err.Error(), "injected-setup-failure") {
				t.Fatalf("mirror setup error was lost: %v", err)
			}
			release, err := common.LockRoStore(path, 0)
			if err != nil {
				t.Fatalf("lock was not released after setup failed: %v", err)
			}
			if err := release(); err != nil {
				t.Fatal(err)
			}
		})
	}
}
