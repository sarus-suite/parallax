package cmd

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/containers/storage"
	"github.com/sirupsen/logrus"

	"parallax/common"
)

type RoImage struct {
	ID       string
	TopLayer string
	Link     string // overlay link ID used for squash files
}

var log = logrus.WithField("component", "cmd")

func RunRmi(cfg common.Config) error {
	log = log.WithField("sub", "rmi")
	log.Infof("Starting removal of image: %s", cfg.Image)
	log.Debugf("Podman Root: %s, Read-only Storage Path: %s", cfg.PodmanRoot, cfg.RoStoragePath)

    // we copy mirror the RoStoragePath to hide the fact that might be a networkedFS
    mirror, mirrorCleanup, err := common.Mirror(cfg.RoStoragePath)
    if err != nil {
        log.Debug("Failed to copy mirror: %v", err)
        return err
    }
    log.Infof("Copy mirror of %s at %s", cfg.RoStoragePath, mirror)
    originalPath := cfg.RoStoragePath
    cfg.RoStoragePath = mirror

	storeRun, cleanupRun := common.MustTempDir("rmi-RoStore-*")
	log.Infof("Opened store with: %s, %s", cfg.RoStoragePath, storeRun)
	store, err := storage.GetStore(storage.StoreOptions{
		GraphRoot:       cfg.RoStoragePath,
		RunRoot:         storeRun,
		GraphDriverName: "overlay",
	})
	if err != nil {
		panic(fmt.Errorf("Error init overlay store: %w", err))
	}
	defer func() {
		cfg.RoStoragePath = originalPath
		store.Shutdown(false)
		cleanupRun()
		mirrorCleanup()
		log.Info("Teardown of store completed")
	}()

	name := cfg.Image

	img, err := getImageRMI(store, cfg, name)
	if err != nil {
		log.Errorf("Could not locate image %s: %v", name, err)
		return nil
	}

	log.Infof("Removing squash for %s (link=%s)", name, img.Link)
	if err := RemoveSquashFile(cfg, img.Link); err != nil {
		log.Warnf("Error removing squash side-cars for layer %s: %v", img.Link, err)
	}

	log.Infof("Removing Image from store %s", img.ID)
	_, err = store.DeleteImage(img.ID, true) // true == actually perform deletion
	if err != nil {
		log.Errorf("Failed to delete image %s via storage: %v", img.ID, err)
		return nil
	}

	log.Infof("Removal successfully completed for image: %s", cfg.Image)
	return nil
}

func getImageRMI(store storage.Store, cfg common.Config, name string) (*RoImage, error) {
	img, err := common.FindImage(store, name)
	if err != nil {
		return nil, err
	}

	// read the overlay “link” file under RoStoragePath/overlay/<TopLayer>/link
	linkPath := filepath.Join(cfg.RoStoragePath, "overlay", img.TopLayer, "link")
	data, err := os.ReadFile(linkPath)
	if err != nil {
		return nil, err
	}

	return &RoImage{
		ID:       img.ID,
		TopLayer: img.TopLayer,
		Link:     string(data),
	}, nil
}

func RemoveSquashFile(cfg common.Config, link string) error {
	paths := []string{
		filepath.Join(cfg.RoStoragePath, "overlay", "l", link+".squash"),
		filepath.Join(cfg.RoStoragePath, "squash", link+".squash"),
	}
	for _, p := range paths {
		if err := os.Remove(p); err != nil && !os.IsNotExist(err) {
			return fmt.Errorf("removing %s: %w", p, err)
		}
	}
	return nil
}

