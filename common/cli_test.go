package common

import (
	"flag"
	"io"
	"testing"
	"time"
)

func TestLockTimeoutFlag(t *testing.T) {
	for _, tc := range []struct {
		name, operation, value string
		want                   time.Duration
		wantError              bool
	}{
		{"default", "migrate", "", 5 * time.Minute, false},
		{"custom", "rmi", "30s", 30 * time.Second, false},
		{"immediate", "migrate", "0", 0, false},
		{"negative-migrate", "migrate", "-1s", 0, true},
		{"negative-rmi", "rmi", "-1s", 0, true},
		{"invalid", "rmi", "invalid", 0, true},
		{"exists-ignores", "exists", "-1s", -time.Second, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			fs := flag.NewFlagSet(tc.name, flag.ContinueOnError)
			fs.SetOutput(io.Discard)
			args := []string{"--" + tc.operation, "--image", "alpine", "--roStoragePath", t.TempDir(), "--podmanRoot", t.TempDir(), "--mksquashfsPath", "/bin/true"}
			if tc.value != "" {
				args = append(args, "--lock-timeout", tc.value)
			}
			cli, err := ParseAndValidateFlags(fs, args)
			if (err != nil) != tc.wantError {
				t.Fatalf("error = %v, want error %v", err, tc.wantError)
			}
			if err == nil && cli.Config.LockTimeout != tc.want {
				t.Fatalf("timeout = %s, want %s", cli.Config.LockTimeout, tc.want)
			}
		})
	}
}
