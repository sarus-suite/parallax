package common

import (
	"os"
	"fmt"

	"github.com/sirupsen/logrus"
)

func MustTempDir(prefix string) (string, func()) {
    dir, cleanup, err := TempDir(prefix)
    if err != nil {
		panic(fmt.Errorf("MustTempDir: %w", err))
    }
    return dir, cleanup
}

// env var PARALLAX_KEEP_TMP can be used to inspect dirs if debug is needed
func TempDir(prefix string) (string, func(), error) {
	dir, err := os.MkdirTemp("", prefix)
	if err != nil {
		return "", nil, err
	}
	logrus.WithField("component", "common")
	logrus.Debugf("Created temp dir %s", dir)

	cleanup := func() {
		if os.Getenv("PARALLAX_KEEP_TMP") != "" {
			logrus.Infof("PARALLAX KEEP_TMP set - keeping %s", dir)
			return
		}
		_ = os.RemoveAll(dir)
	}

	return dir, cleanup, nil
}
