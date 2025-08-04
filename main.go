package main

import (
	"flag"
	"os"
	"fmt"
	"time"

	"github.com/sirupsen/logrus"
	"github.com/containers/storage/pkg/unshare"
	"github.com/containers/storage/pkg/reexec"

	"parallax/cmd"
	"parallax/common"
)

func main() {
	// Registering reexec for unshare
	if reexec.Init() {
		return
	}
	// Enter new user-namespace needed for rootless storage
	unshare.MaybeReexecUsingUserNamespace(true)

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
			if err := common.validateRoStore(cli.Config.RoStoragePath); err != nil {
				logrus.Fatalf("Storage validation failed before migration: %v", err)
			}
			_, err := cmd.RunMigration(cli.Config)
			if err != nil {
				logrus.Fatalf("Migration failed for image '%s': %v", cli.Config.Image, err)
			}
		case common.OpRmi:
			if err := common.validateRoStore(cli.Config.RoStoragePath); err != nil {
				logrus.Fatalf("Storage validation failed before rmi: %v", err)
			}
			err = cmd.RunRmi(cli.Config)
			if err != nil {
				logrus.Fatalf("RMI operation failed for image '%s': %v", cli.Config.Image, err)
			}
		default:
			panic("Unknown operation. We should never reach here!")
	}
}

