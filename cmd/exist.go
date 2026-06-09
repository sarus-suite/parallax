package cmd

import "parallax/common"

func RunExist(cfg common.Config) (bool, error) {
	log = log.WithField("sub", "exist")
	log.Infof("Checking for image in read-only storage: %s", cfg.Image)

	roStore, cleanupRoStore, err := setupScratchStore(&cfg)
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
