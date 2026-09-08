//go:build linux

package rootless

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"syscall"
)

const (
	usernsConfiguredEnv = "_CONTAINERS_USERNS_CONFIGURED"
	rootlessUIDEnv      = "_CONTAINERS_ROOTLESS_UID"
	rootlessGIDEnv      = "_CONTAINERS_ROOTLESS_GID"
)

type ReexecResult struct {
	Reexecuted bool
	ExitCode   int
}

// MaybeReexec starts a child parallax process as uid 0 inside a fresh user and
// mount namespace. It intentionally avoids libc user lookups and fd-based
// reexec so static musl builds work on NSS-backed hosts.
func MaybeReexec() (ReexecResult, error) {
	if os.Getenv(usernsConfiguredEnv) != "" {
		if os.Geteuid() != 0 {
			return ReexecResult{}, fmt.Errorf("%s is set but effective UID is %d, expected 0", usernsConfiguredEnv, os.Geteuid())
		}
		inUserNS, err := inNonInitialUserNamespace()
		if err != nil {
			return ReexecResult{}, err
		}
		if !inUserNS {
			return ReexecResult{}, fmt.Errorf("%s is set but process is still in the initial user namespace", usernsConfiguredEnv)
		}
		return ReexecResult{}, nil
	}

	uid := os.Geteuid()
	gid := os.Getegid()
	if uid == 0 {
		return ReexecResult{}, fmt.Errorf("parallax must be started rootless, not as root")
	}

	cmd := exec.Command("/proc/self/exe", os.Args[1:]...)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	cmd.Env = reexecEnv(uid, gid)
	cmd.SysProcAttr = &syscall.SysProcAttr{
		Cloneflags: syscall.CLONE_NEWUSER | syscall.CLONE_NEWNS,
		UidMappings: []syscall.SysProcIDMap{
			{
				ContainerID: 0,
				HostID:      uid,
				Size:        1,
			},
		},
		GidMappings: []syscall.SysProcIDMap{
			{
				ContainerID: 0,
				HostID:      gid,
				Size:        1,
			},
		},
		GidMappingsEnableSetgroups: false,
		Pdeathsig:                  syscall.SIGKILL,
	}

	err := cmd.Run()

	if err == nil {
		return ReexecResult{Reexecuted: true, ExitCode: 0}, nil
	}

	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		if status, ok := exitErr.Sys().(syscall.WaitStatus); ok {
			if status.Signaled() {
				return ReexecResult{Reexecuted: true, ExitCode: 128 + int(status.Signal())}, nil
			}
			return ReexecResult{Reexecuted: true, ExitCode: status.ExitStatus()}, nil
		}
	}

	return ReexecResult{}, fmt.Errorf("re-exec /proc/self/exe in user namespace: %w", err)
}

func inNonInitialUserNamespace() (bool, error) {
	content, err := os.ReadFile("/proc/self/uid_map")
	if err != nil {
		return false, fmt.Errorf("read /proc/self/uid_map: %w", err)
	}
	mapping, err := parseFirstIDMapLine(string(content))
	if err != nil {
		return false, fmt.Errorf("parse /proc/self/uid_map: %w", err)
	}
	return !mapping.isInitialNamespace(), nil
}

type idMapLine struct {
	containerID uint64
	hostID      uint64
	size        uint64
}

func (m idMapLine) isInitialNamespace() bool {
	return m.containerID == 0 && m.hostID == 0 && m.size == 4294967295
}

func parseFirstIDMapLine(content string) (idMapLine, error) {
	line, _, _ := strings.Cut(strings.TrimSpace(content), "\n")
	fields := strings.Fields(line)
	if len(fields) != 3 {
		return idMapLine{}, fmt.Errorf("expected three fields in first mapping line, got %d", len(fields))
	}

	containerID, err := strconv.ParseUint(fields[0], 10, 64)
	if err != nil {
		return idMapLine{}, fmt.Errorf("parse container id %q: %w", fields[0], err)
	}
	hostID, err := strconv.ParseUint(fields[1], 10, 64)
	if err != nil {
		return idMapLine{}, fmt.Errorf("parse host id %q: %w", fields[1], err)
	}
	size, err := strconv.ParseUint(fields[2], 10, 64)
	if err != nil {
		return idMapLine{}, fmt.Errorf("parse size %q: %w", fields[2], err)
	}

	return idMapLine{
		containerID: containerID,
		hostID:      hostID,
		size:        size,
	}, nil
}

func reexecEnv(uid, gid int) []string {
	env := os.Environ()
	env = setEnv(env, usernsConfiguredEnv, "done")
	env = setEnv(env, rootlessUIDEnv, strconv.Itoa(uid))
	env = setEnv(env, rootlessGIDEnv, strconv.Itoa(gid))
	return env
}

func setEnv(env []string, key, value string) []string {
	prefix := key + "="
	entry := prefix + value
	for i, current := range env {
		if strings.HasPrefix(current, prefix) {
			env[i] = entry
			return env
		}
	}
	return append(env, entry)
}
