package common

import (
	"flag"
	"fmt"
	"os"

	"github.com/sirupsen/logrus"
)

// TODO: auto gen version field
const Version = "1.0.0"

func usage_banner() {
	fmt.Fprintf(flag.CommandLine.Output(), `
Parallax
OCI image migration tool for Podman on HPC systems

Usage:
  parallax -migrate -image <image[:tag]> [options]
  parallax -rmi -image <image[:tag]> [options]

Options:
`)
	flag.PrintDefaults()
	fmt.Fprintf(flag.CommandLine.Output(), `
Examples:
  parallax -migrate -image ubuntu:latest
  parallax -rmi -image alpine:3.18

`)
}

// Track we are being asked
type Operation int
const (
	OpUnknown Operation = iota
	OpMigrate
	OpRmi
)

type CLI struct {
	Config Config
	Op Operation
	LogLevel logrus.Level
	ShowUsage bool //use for -h
}

func ParseAndValidateFlags(fs *flag.FlagSet, args []string) (*CLI, error) {
	// flag declaration
	podmanRoot := fs.String("podmanRoot", "/var/lib/containers/storage", "Path to Podman root storage directory")
	roStorage  := fs.String("roStoragePath", "/mnt/nfs/podman", "Path to read-only storage location")
	mksquashfs := fs.String("mksquashfsPath", "/usr/bin/mksquashfs", "Path to mksquashfs binary")
	image      := fs.String("image", "", "the name (:tag) of the image to remove")
	logLevelF  := fs.String("log-level", "info", "Logging level (debug, info, warn, error, fatal, panic)")
	migrateF   := fs.Bool("migrate", false, "Migrates an image")
	rmiF       := fs.Bool("rmi", false, "Removes an image")
	versionF   := fs.Bool("version", false, "Print version")

	// Pass the new help banner
	fs.Usage = usage_banner

	err := fs.Parse(args)
	if err != nil {
		return nil, err
	}

	// Fast version exit
	if *versionF {
		fmt.Fprintf(os.Stdout, "Parallax version %s\n", Version)
		os.Exit(0)
	}

	// Validate that options flags migrate and rmi are exclusive
	if *migrateF == *rmiF {
		return nil, fmt.Errorf("Must specify either -migrate or -rmi")
	}
	// Validate that image is present
	if *image == "" {
		return nil, fmt.Errorf("Must specify -image image (e.g. -image ubuntu:latest)")
	}

	// Argument validation
	if err := IsDir(*podmanRoot); err != nil {
		return nil, fmt.Errorf("podmanRoot. Podman root directory: %w", err)
	}
	if err := IsDir(*roStorage); err != nil {
		return nil, fmt.Errorf("roStoragePath. Read-only storage path: %w", err)
	}
	if err := IsExecutable(*mksquashfs); err != nil {
		return nil, fmt.Errorf("mksquashfsPath. mksquashfs binary: %w", err)
	}
	// Setting up logging
	level, err := logrus.ParseLevel(*logLevelF)
	if err != nil {
		return nil, fmt.Errorf("Invalid log level %q", *logLevelF)
	}

	// We made it through checks we can init the CLI struct
	return &CLI {
		Config: Config {
			PodmanRoot: *podmanRoot,
			RoStoragePath: *roStorage,
			MksquashfsPath: *mksquashfs,
			Image: *image,
		},
		Op: map[bool]Operation{true: OpMigrate, false: OpRmi}[*migrateF], // inlined if/else
		LogLevel: level,
	}, nil
}
