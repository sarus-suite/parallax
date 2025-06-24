package cmd

import (
	"archive/tar"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"slices"

	imgmanifest "github.com/containers/image/v5/manifest"
	"github.com/containers/storage"
	"github.com/containers/storage/pkg/archive"
	"github.com/containers/storage/pkg/ioutils"
	godigest "github.com/opencontainers/go-digest"
	ocispec "github.com/opencontainers/image-spec/specs-go/v1"

	"parallax/common"
)

func RunMigration(cfg common.Config) (*storage.Image, error) {
	log = log.WithField("sub", "migration")
	log.Infof("Starting migration for image: %s", cfg.Image)
	log.Debugf("Podman Root: %s, Read-only Storage Path: %s, mksquashfs Path: %s",
	cfg.PodmanRoot, cfg.RoStoragePath, cfg.MksquashfsPath)

	name := cfg.Image
	_, names, err := resolveImageNames(name)
	if err != nil { return nil, err }

	srcStore, cleanupSrcStore, err := setupSrcStore(cfg)
	if err != nil { return nil, err }
	defer cleanupSrcStore()

	scratchStore, cleanupScratch, err := setupScratchStore(cfg)
	if err != nil { return nil, err }
	defer cleanupScratch()

	migrated, err := checkIfMigrated(name, cfg, scratchStore)
	if err != nil || migrated {
		log.Infof("Image already migrated. Nothing to do.")
		return nil, err
	}

	srcImg, mountPoint, cleanupSrc, err := prepareAndMountSourceImage(name, cfg, srcStore)
	if err != nil { return nil, err }
	defer cleanupSrc()

	layerDigest, size, dummyDir, cleanupDummy, err := createDummyFlatLayer(name, srcImg)
	if err != nil { return nil, err }
	defer cleanupDummy()

	newLayer, err := putFlattenedLayer(scratchStore, dummyDir, layerDigest, size)
	if err != nil { return nil, err }

	overlayLink, err := readOverlayLink(newLayer, cfg)
	if err != nil { return nil, err }

	err = createSquashSidecarFromMount(mountPoint, overlayLink, cfg)
	if err != nil { return nil, err }

	cfgBlob, manifestBlob, manifestDigest, err := generateManifestAndConfig(srcImg, layerDigest, size, cfg, srcStore)
	if err != nil { return nil, err }

	flatImg, err := createFlattenedImageInStore(scratchStore, names, newLayer, srcImg, manifestDigest)
	if err != nil { return nil, err }

	err = attachMetadataToImage(scratchStore, flatImg, cfgBlob, manifestBlob, srcImg, cfg, srcStore)
	if err != nil { return nil, err }

	log.Infof("Migration successfully completed for image: %s", flatImg.ID)
	return flatImg, nil
}


func resolveImageNames(name string) (string, []string, error) {
	sublog := log.WithField("fn", "resolveImageNames")
	sublog.Info("Resolving full name")

	fqName, err := common.CanonicalImageName(name)
	if err != nil {
		return "", nil, fmt.Errorf("resolve canonical name: %w", err)
	}
	names := []string{fqName}
	if fqName != name {
		names = append(names, name)
	}
	return fqName, names, nil
}

func prepareAndMountSourceImage(name string, cfg common.Config, srcStore storage.Store) (*storage.Image, string, func(), error) {
	sublog := log.WithField("fn", "prep&mount")
	sublog.Info("Mounting source image")

	sublog.Debug("Get source image")
	srcImg, err := common.FindImage(srcStore, name)
	if err != nil {
		return nil, "", nil, err
	}

	sublog.Debug("Mounting image")
	mountPoint, err := srcStore.MountImage(srcImg.ID, nil, "")
	if err != nil {
		return nil, "", nil, fmt.Errorf("failed to mount image: %w", err)
	}

	cleanup := func() {
		srcStore.UnmountImage(srcImg.ID, true)
	}

	return &srcImg, mountPoint, cleanup, nil
}

func createDummyFlatLayer(name string, srcImg *storage.Image) (godigest.Digest, int64, string, func(), error) {
	sublog := log.WithField("fn", "createDummyFlatLayer")

	sublog.Info("Creating a dummy layer diff dir")
	dummyDir, cleanup, err := makeDummyDir(name, srcImg.ID)
	if err != nil {
		return "", 0, "", nil, err
	}

	sublog.Debug("Calculating digest as podman likes it")
	layerDigest, size, err := FlattenViaTar(dummyDir, "rootfs")
	if err != nil {
		cleanup()
		return "", 0, "", nil, err
	}

	return layerDigest, size, dummyDir, cleanup, nil
}

// We need this for when images come with canonical names and special chars that dont work on FS
func safeName(name string) string {
	return strings.NewReplacer("/", "-", ":", "-").Replace(name)
}

func makeDummyDir(imageName, imageID string) (string, func(), error) {
	dir, cleanup, err := common.TempDir("migrate-*")
	if err != nil {
		return "", nil, err
	}

	sanitized_name := safeName(imageName)
	marker := filepath.Join(dir, ".migrationv3-" + sanitized_name)
	if err := os.WriteFile(marker, []byte(imageID+"\n"), 0o644); err != nil {
		cleanup()
		return "", nil, err
	}
	return dir, cleanup, nil
}

// This function purpose is just to calculate digest as podman does for any dir
// ... and avoid store corruption messages at least for podman 5.5.0-dev
func FlattenViaTar(mountPoint, layerID string) (godigest.Digest, int64, error) {
	diff, err := archive.TarWithOptions(mountPoint, &archive.TarOptions{
		Compression:      archive.Uncompressed,
		IncludeSourceDir: false,
		NoLchown:         true,
	})
	if err != nil {
		return "", 0, fmt.Errorf("create tar from %s: %w", mountPoint, err)
	}
	defer diff.Close()

	digester := godigest.Canonical.Digester()
	counter  := ioutils.NewWriteCounter(digester.Hash())
	tr       := tar.NewReader(io.TeeReader(diff, counter))

	// Walk the tar
	for {
		if _, err := tr.Next(); err != nil {
			if errors.Is(err, io.EOF) {
				break
			}
			return "", 0, fmt.Errorf("layer %s: read tar: %w", layerID, err)
		}
	}

	// Drain any padding so the count is accurate
	if _, err := io.Copy(io.Discard, tr); err != nil && !errors.Is(err, io.EOF) {
		return "", 0, fmt.Errorf("layer %s: drain trailer: %w", layerID, err)
	}

	return digester.Digest(), counter.Count, nil
}

func setupSrcStore(cfg common.Config) (storage.Store, func(), error) {
	sublog := log.WithField("fn", "setupSrcStore")

	sublog.Info("Setting up SRC Store")
	srcRun, cleanupRun := common.MustTempDir("src-runroot-*")
	srcStore, err := storage.GetStore(storage.StoreOptions{
		GraphRoot:       cfg.PodmanRoot,
		RunRoot:         srcRun,
		GraphDriverName: "overlay",
	})
	if err != nil {
		sublog.Debug("Failed to setup SRC store.")
		return nil, nil, err
	}
	cleanup := func() {
		srcStore.Shutdown(false)
		cleanupRun()
	}
	return srcStore, cleanup, nil
}

func setupScratchStore(cfg common.Config) (storage.Store, func(), error) {
	sublog := log.WithField("fn", "setupScratchStore")

	sublog.Info("Setting up scratch Store")
	scratchRun, cleanupScratch := common.MustTempDir("scratch-runroot-*")
	scratchStore, err := storage.GetStore(storage.StoreOptions{
		GraphRoot:       cfg.RoStoragePath,
		RunRoot:         scratchRun,
		GraphDriverName: "overlay",
	})
	if err != nil {
		sublog.Debug("Failed to setup scratch store.")
		return nil, nil, err
	}
	cleanup := func() {
		scratchStore.Shutdown(false)
		cleanupScratch()
	}
	return scratchStore, cleanup, nil
}

func checkIfMigrated(name string, cfg common.Config, roStore storage.Store) (bool, error) {
	sublog := log.WithField("fn", "checkIfMigrated")
	sublog.Debug("Checking if image is migrated")

	img, err := common.FindImage(roStore, name)
	if err != nil {
		if strings.Contains(err.Error(), "Image not found") {
			sublog.Debugf("Image %s not found", name)
			return false, nil
		}
		return false, err
	}
	sublog.Debugf("Found image %s at %s", name, cfg.RoStoragePath)

	// migrated has only one layer, so check TopLayer
	top := img.TopLayer
	if top == "" {
		return false, fmt.Errorf("image %s has no top layer (!?)", name)
	}

	linkBytes, err := os.ReadFile(filepath.Join(cfg.RoStoragePath, "overlay", top, "link"))
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	link := strings.TrimSpace(string(linkBytes))
	sublog.Debugf("Found top layer link: %s", link)

	sublog.Debug("Checking for migration symlinks")
	lSidecar := filepath.Join(cfg.RoStoragePath, "overlay", "l", link+".squash")
	squash    := filepath.Join(cfg.RoStoragePath, "squash",      link+".squash")
	if _, err := os.Stat(lSidecar); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}
	if _, err := os.Stat(squash); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, nil
		}
		return false, err
	}

	sublog.Debug("Image fully migrated.")
	return true, nil
}

// We do this to ensure the creation of a valid and unique layer which podman will accept
func putFlattenedLayer(store storage.Store, dummyDir string, digest godigest.Digest, size int64) (*storage.Layer, error) {
	sublog := log.WithField("fn", "putFlattenedLayer")

	diff, err := archive.TarWithOptions(dummyDir, &archive.TarOptions{
		Compression:      archive.Uncompressed,
		IncludeSourceDir: false,
		NoLchown:         true,
	})
	if err != nil {
		return nil, err
	}
	defer diff.Close()

	sublog.Info("Put single dummy layer")
	layerOpts := &storage.LayerOptions{UncompressedDigest: digest, OriginalSize: &size}
	newLayer, _, err := store.PutLayer("", "", nil, "", false, layerOpts, diff)
	if err != nil {
		return nil, fmt.Errorf("failed to put flattened layer: %w", err)
	}
	return newLayer, nil
}

func readOverlayLink(layer *storage.Layer, cfg common.Config) (string, error) {
	linkBytes, err := os.ReadFile(filepath.Join(cfg.RoStoragePath, "overlay", layer.ID, "link"))
	if err != nil {
		return "", fmt.Errorf("read overlay link: %w", err)
	}
	return strings.TrimSpace(string(linkBytes)), nil
}

func createSquashSidecarFromMount(srcDir, link string, cfg common.Config) error {
	sublog := log.WithField("fn", "createSquash")
	sublog.Info("Building squash file")

	squashPath := filepath.Join(cfg.RoStoragePath, "squash", link+".squash")
	if _, err := os.Stat(squashPath); errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(squashPath), 0o755); err != nil {
			return err
		}
		// TODO: how to expose options? particularly the compression?
		cmd := exec.Command(cfg.MksquashfsPath,
		srcDir, squashPath,
		"-noappend", "-comp", "xz",
		"-no-xattrs", "-e", "security.capability")
		if out, err := cmd.CombinedOutput(); err != nil {
			return fmt.Errorf("mksquashfs: %v\n%s", err, out)
		}
	}

	sublog.Info("Symlinking squash")
	lDir := filepath.Join(cfg.RoStoragePath, "overlay", "l")
	if err := os.MkdirAll(lDir, 0o755); err != nil { return err }

	return ensureSymlink( filepath.Join("..", "..", "squash", link+".squash"), filepath.Join(lDir, link+".squash"))
}

func ensureSymlink(target, linkname string) error {
	_, err := os.Lstat(linkname)
	if err == nil { return nil }
	if !errors.Is(err, os.ErrNotExist) { return err }
	return os.Symlink(target, linkname)
}

func generateManifestAndConfig(srcImg *storage.Image, layerDigest godigest.Digest, size int64, cfg common.Config, srcStore storage.Store) ([]byte, []byte, godigest.Digest, error) {
	sublog := log.WithField("fn", "generateManifestAndConfig")

	sublog.Debug("Parsing source manifest")
	originalManifestBytes, err := srcStore.ImageBigData(srcImg.ID, storage.ImageDigestManifestBigDataNamePrefix)
	if err != nil {
		return nil, nil, "", fmt.Errorf("get src manifest: %w", err)
	}
	var originalManifest ocispec.Manifest
	if err := json.Unmarshal(originalManifestBytes, &originalManifest); err != nil {
		return nil, nil, "", fmt.Errorf("parsing src manifest: %w", err)
	}

	sublog.Debug("Parsing source config")
	originalConfigBytes, err := srcStore.ImageBigData(srcImg.ID, originalManifest.Config.Digest.String())
	if err != nil {
		return nil, nil, "", fmt.Errorf("get src config: %w", err)
	}
	var originalConfig ocispec.Image
	if err := json.Unmarshal(originalConfigBytes, &originalConfig); err != nil {
		return nil, nil, "", fmt.Errorf("parsing src config: %w", err)
	}

	sublog.Debug("Patch new config to match single layer")
	originalConfig.RootFS = ocispec.RootFS{
		Type:    "layers",
		DiffIDs: []godigest.Digest{layerDigest},
	}
	originalConfig.History = append(originalConfig.History, ocispec.History{
		CreatedBy: "MV3", Comment: "Flattened layers from image " + srcImg.ID,
	})
	cfgBytes, err := json.Marshal(originalConfig)
	if err != nil {
		return nil, nil, "", fmt.Errorf("marshal updated config: %w", err)
	}
	cfgDigest := godigest.Canonical.FromBytes(cfgBytes)

	sublog.Debug("Creating new manifest")
	manifest := ocispec.Manifest{
		MediaType: "application/vnd.oci.image.manifest.v1+json",
		Annotations: originalManifest.Annotations,
		Config: ocispec.Descriptor{
			MediaType: ocispec.MediaTypeImageConfig,
			Size:      int64(len(cfgBytes)),
			Digest:    cfgDigest,
		},
		Layers: []ocispec.Descriptor{{
			MediaType: ocispec.MediaTypeImageLayer,
			Size:      size,
			Digest:    layerDigest,
		}},
	}
	manBytes, err := json.Marshal(manifest)
	if err != nil {
		return nil, nil, "", fmt.Errorf("marshal manifest: %w", err)
	}
	manifestDigest := godigest.Canonical.FromBytes(manBytes)

	return cfgBytes, manBytes, manifestDigest, nil
}

func createFlattenedImageInStore(store storage.Store, names []string, layer *storage.Layer, srcImg *storage.Image, manifestDigest godigest.Digest) (*storage.Image, error) {
	flatImg, err := store.CreateImage(
		"",        // The store automagically assign a new ID to image object
		names,     // We pass the name and full name too!
		layer.ID,  // We pass the new dummy layer id
		"",        // Not using srcImg.Metadata as it can add inconsistent info after migration
		&storage.ImageOptions{
			NamesHistory: srcImg.Names,
			CreationDate: srcImg.Created,
			Digest:       manifestDigest,
		})

	if err != nil {
		return nil, fmt.Errorf("create flattened image: %w", err)
	}
	return flatImg, nil
}

func attachMetadataToImage(store storage.Store, img *storage.Image, cfgBlob, manifestBlob []byte, srcImg *storage.Image, cfg common.Config, srcStore storage.Store) error {
	sublog := log.WithField("fn", "attachMetadataToImage")

	sublog.Debug("Attaching manifest")
	err := store.SetImageBigData(
		img.ID,
		storage.ImageDigestManifestBigDataNamePrefix,
		manifestBlob,
		imgmanifest.Digest)

	if err != nil {
		return err
	}

	sublog.Debug("Attaching config")
	cfgDigest := godigest.Canonical.FromBytes(cfgBlob)
	err = store.SetImageBigData(
		img.ID,
		cfgDigest.String(),
		cfgBlob,
		nil)
	if err != nil {
		return err
	}

	sublog.Debug("Attaching all other BigData from srcImage")
	for _, bdname := range srcImg.BigDataNames {
		if bdname == cfgDigest.String() ||
		strings.HasPrefix(bdname, storage.ImageDigestManifestBigDataNamePrefix){
			continue // skip manifest and config
		}

		sublog.Debugf("Found BigData blob %s", bdname)
		data, err := srcStore.ImageBigData(srcImg.ID, bdname)
		if err != nil {
			return err
		}

		sublog.Debugf("Attaching BigData blob %s as-is.", bdname)
		if err := store.SetImageBigData(img.ID, bdname, data, nil); err != nil {
			return err
		}
	}

	return nil
}

