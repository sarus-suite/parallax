package common

import (
    "fmt"
	"runtime"
)

var (
    // These to get overriden at build time via flags
	Version = "unversioned"
	Commit = "unknown"
	BuildDate = "unknown"
)

func Print() {
    fmt.Printf("Parallax version: %s\n", Version)
	if Commit != "" && Commit != "unknown" {
        fmt.Printf("Commit: %s\n", Commit)
	}
	if BuildDate != "" && BuildDate != "unknown" {
        fmt.Printf("Build date: %s\n", BuildDate)
	}
}
