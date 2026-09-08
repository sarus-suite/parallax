package cmd

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"

	"github.com/containers/storage"

	"parallax/common"
)

func RunExist(cfg common.Config) (bool, error) {
	log = log.WithField("sub", "exist")
	log.Infof("Checking for image in read-only storage: %s", cfg.Image)

	imagesPath := filepath.Join(cfg.RoStoragePath, "overlay-images", "images.json")
	if _, err := os.Stat(imagesPath); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			log.Infof("Image does not exist in read-only storage: %s", cfg.Image)
			return false, nil
		}
		return false, err
	}

	roStore, cleanupRoStore, err := setupReadOnlyStore(cfg)
	if err != nil {
		return false, err
	}
	defer cleanupRoStore()

	exists, err := checkIfMigrated(cfg.Image, cfg, roStore)
	if err != nil {
		return false, err
	}

	if exists {
		log.Infof("Image exists in read-only storage: %s", cfg.Image)
	} else {
		log.Infof("Image does not exist in read-only storage: %s", cfg.Image)
	}

	return exists, nil
}

func setupReadOnlyStore(cfg common.Config) (storage.Store, func(), error) {
	imagesLock := filepath.Join(cfg.RoStoragePath, "overlay-images", "images.lock")
	if _, err := os.Stat(imagesLock); err != nil {
		return nil, nil, fmt.Errorf("read-only image store lock: %w", err)
	}

	graphRoot, cleanupGraph, err := common.TempDir("exists-graphroot-*")
	if err != nil {
		return nil, nil, err
	}
	runRoot, cleanupRun, err := common.TempDir("exists-runroot-*")
	if err != nil {
		cleanupGraph()
		return nil, nil, err
	}

	store, err := storage.GetStore(storage.StoreOptions{
		GraphRoot:       graphRoot,
		RunRoot:         runRoot,
		GraphDriverName: "overlay",
		GraphDriverOptions: []string{
			"overlay.additionalimagestore=" + cfg.RoStoragePath,
		},
	})
	if err != nil {
		cleanupRun()
		cleanupGraph()
		return nil, nil, err
	}

	cleanup := func() {
		store.Shutdown(false)
		cleanupRun()
		cleanupGraph()
	}

	return store, cleanup, nil
}
