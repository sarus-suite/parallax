package common

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"time"

	log "github.com/sirupsen/logrus"
	"golang.org/x/sys/unix"
)

const storeLockName = ".parallax.lock"

// ErrStoreLockTimeout means another writer held the store past the wait deadline.
var ErrStoreLockTimeout = errors.New("image store lock timeout")

// LockRoStore exclusively locks the original, shared store until release is called.
// The lock file must never be removed or replaced, including during mirror write-back.
// A zero timeout attempts acquisition once. Negative timeouts are invalid.
func LockRoStore(path string, timeout time.Duration) (release func() error, err error) {
	if timeout < 0 {
		return nil, fmt.Errorf("lock-timeout must not be negative")
	}
	file, err := os.OpenFile(filepath.Join(path, storeLockName), os.O_CREATE|os.O_RDWR|unix.O_CLOEXEC, 0o666)
	if err != nil {
		return nil, fmt.Errorf("open image store lock for %q: %w", path, err)
	}
	defer func() {
		if err != nil {
			err = errors.Join(err, file.Close())
		}
	}()

	deadline := time.Now().Add(timeout)
	waiting := false
	for {
		err = unix.Flock(int(file.Fd()), unix.LOCK_EX|unix.LOCK_NB)
		if err == nil {
			log.Infof("Acquired image store lock for %q", path)
			return func() error {
				unlockErr := unix.Flock(int(file.Fd()), unix.LOCK_UN)
				closeErr := file.Close()
				if err := errors.Join(unlockErr, closeErr); err != nil {
					return fmt.Errorf("release image store lock for %q: %w", path, err)
				}
				return nil
			}, nil
		}
		if !errors.Is(err, unix.EWOULDBLOCK) && !errors.Is(err, unix.EAGAIN) && !errors.Is(err, unix.EINTR) {
			return nil, fmt.Errorf("acquire image store lock for %q: %w", path, err)
		}
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return nil, fmt.Errorf("%w for %q after %s", ErrStoreLockTimeout, path, timeout)
		}
		if !waiting {
			log.Infof("Waiting for image store lock for %q (timeout %s)", path, timeout)
			waiting = true
		}
		time.Sleep(min(100*time.Millisecond, remaining))
		if !time.Now().Before(deadline) {
			return nil, fmt.Errorf("%w for %q after %s", ErrStoreLockTimeout, path, timeout)
		}
	}
}
