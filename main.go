package main

import (
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/containers/storage/pkg/reexec"
	"github.com/sirupsen/logrus"

	"parallax/cmd"
	"parallax/common"
	"parallax/internal/rootless"
)

func main() {
	// Register storage reexec handlers before entering normal CLI flow.
	if reexec.Init() {
		return
	}
	// Enter the user namespace needed for rootless storage.
	reexecResult, err := rootless.MaybeReexec()
	if err != nil {
		logrus.Fatalf("Failed to enter rootless user namespace: %v", err)
	}
	if reexecResult.Reexecuted {
		os.Exit(reexecResult.ExitCode)
	}

	cli, err := common.ParseAndValidateFlags(flag.CommandLine, os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		flag.CommandLine.Usage()
		os.Exit(2)
	}

	logrus.SetLevel(cli.LogLevel)
	logrus.SetOutput(os.Stdout)
	logrus.SetFormatter(&logrus.TextFormatter{
		FullTimestamp:   true,
		TimestampFormat: time.RFC3339,
	})

	switch cli.Op {
	case common.OpMigrate:
		if err := common.ValidateRoStore(cli.Config.RoStoragePath); err != nil {
			logrus.Fatalf("Storage validation failed before migration: %v", err)
		}
		_, err := cmd.RunMigration(cli.Config)
		if err != nil {
			logrus.Fatalf("Migration failed for image '%s': %v", cli.Config.Image, err)
		}
	case common.OpRmi:
		if err := common.ValidateRoStore(cli.Config.RoStoragePath); err != nil {
			logrus.Fatalf("Storage validation failed before rmi: %v", err)
		}
		err = cmd.RunRmi(cli.Config)
		if err != nil {
			logrus.Fatalf("RMI operation failed for image '%s': %v", cli.Config.Image, err)
		}
	case common.OpExist:
		if err := common.ValidateRoStore(cli.Config.RoStoragePath); err != nil {
			logrus.Fatalf("Storage validation failed before exists check: %v", err)
		}
		exists, err := cmd.RunExist(cli.Config)
		if err != nil {
			logrus.Fatalf("Exists check failed for image '%s': %v", cli.Config.Image, err)
		}
		if !exists {
			os.Exit(1)
		}
	default:
		panic("Unknown operation. We should never reach here!")
	}
}
