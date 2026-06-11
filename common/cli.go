package common

import (
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/sirupsen/logrus"
	"github.com/mattn/go-shellwords"
)

func usage_banner() {
	out := flag.CommandLine.Output()

	// Header
	fmt.Fprintf(out, `
Parallax
OCI image migration tool for Podman on HPC systems

Usage:
  parallax --migrate --image <image[:tag]> [options]
  parallax --exists  --image <image[:tag]> [options]
  parallax --rmi     --image <image[:tag]> [options]

Options:
`)

	// New flag section
	order := []string{
		"migrate",
		"exists",
		"rmi",
		"image",
		"podmanRoot",
		"roStoragePath",
		"mksquashfsPath",
		"mksquashfs-opts",
		"log-level",
		"version",
	}
	for _, name := range order {
		if f := flag.CommandLine.Lookup(name); f != nil {
			printFlag(out, f)
		}
	}

	// Footer
	fmt.Fprintf(out, `
Examples:
  parallax --migrate --image ubuntu:latest
  parallax --exists  --image ubuntu:latest
  parallax --rmi     --image alpine:3.18

`)
}

func printFlag(out io.Writer, f *flag.Flag) {
	// double-dashed name!
	line := fmt.Sprintf("  --%s", f.Name)

	// alignment
	if len(f.Name) < 8 {
		line += "\t"
	} else {
		line += "\t"
	}

	// usage text
	line += f.Usage

	// show default
	if def := f.DefValue; def != "" && def != "false" {
		line += fmt.Sprintf(" (default %q)", def)
	}
	// and print
	fmt.Fprintln(out, line)
}

// Track we are being asked
type Operation int

const (
	OpUnknown Operation = iota
	OpMigrate
	OpExist
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
	mksOptsF   := fs.String("mksquashfs-opts", "", "Parameters for mksquashfs")
	image      := fs.String("image", "", "The image reference to operate on")
	logLevelF  := fs.String("log-level", "info", "Logging level (debug, info, warn, error, fatal, panic)")
	migrateF   := fs.Bool("migrate", false, "Migrates an image")
	existsF    := fs.Bool("exists", false, "Checks whether an image exists in the read-only storage")
	existF     := fs.Bool("exist", false, "Alias for --exists")
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
		VersionPrint()
		os.Exit(0)
	}

	selectedOps := 0
	if *migrateF {
		selectedOps++
	}
	existRequested := *existsF || *existF
	if existRequested {
		selectedOps++
	}
	if *rmiF {
		selectedOps++
	}
	if selectedOps != 1 {
		return nil, fmt.Errorf("Must specify exactly one of -migrate, -exists, or -rmi")
	}
	// Validate that image is present
	if *image == "" {
		return nil, fmt.Errorf("Must specify -image image (e.g. -image ubuntu:latest)")
	}

	op := OpUnknown
	switch {
	case *migrateF:
		op = OpMigrate
	case existRequested:
		op = OpExist
	case *rmiF:
		op = OpRmi
	}

	// Argument validation
	if err := IsDir(*roStorage); err != nil {
		return nil, fmt.Errorf("roStoragePath. Read-only storage path: %w", err)
	}
	if op == OpMigrate {
		if err := IsDir(*podmanRoot); err != nil {
			return nil, fmt.Errorf("podmanRoot. Podman root directory: %w", err)
		}
		if err := IsExecutable(*mksquashfs); err != nil {
			return nil, fmt.Errorf("mksquashfsPath. mksquashfs binary: %w", err)
		}
	}
	// Setting up logging
	level, err := logrus.ParseLevel(*logLevelF)
	if err != nil {
		return nil, fmt.Errorf("Invalid log level %q", *logLevelF)
	}

	// Lets parse the mksquashfs options into a string[]
	var opts []string
	if *mksOptsF != "" {
		parser := shellwords.NewParser()
		parser.ParseBacktick = true
		parsed, err := parser.Parse(*mksOptsF)
		if err != nil {
			return nil, fmt.Errorf("invalid mksquashfs-opts: %w", err)
		}
		opts = parsed
	}

	// We made it through checks we can init the CLI struct
	return &CLI{
		Config: Config{
			PodmanRoot:     *podmanRoot,
			RoStoragePath:  *roStorage,
			MksquashfsPath: *mksquashfs,
			Image:          *image,
			MksquashfsOpts: opts,
		},
		Op: op,
		LogLevel: level,
	}, nil
}
