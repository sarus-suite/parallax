package common

import (
    "bufio"
	"fmt"
	"flag"
	"os"
	"regexp"
	"strings"
)

var kvLineRE = regexp.MustCompile(`^([A-Za-z_][A-Za-z0-9_]*)=(.*)$`)

// Configuration file is a KEY=VALUE config file.
// A format for compatibility with parallax mount program
func LoadKeyValueFile(path string) (map[string]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	kv := make(map[string]string)

	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	iline := 0
	for sc.Scan(){
		iline++
		line := strings.TrimSpace(sc.Text())
		// skip empty line
		if line == "" {continue}
		// skip commented lines
		if strings.HasPrefix(line, "#") {continue}

		m := kvLineRE.FindStringSubmatch(line)
		if m == nil {
			return nil, fmt.Errorf("Invalid line, found %q", sc.Text())
		}

		key := m[1]
		valRaw := m[2]

		parsed, err := parseValue(valRaw)
		if err != nil {
			return nil, fmt.Errorf("%v", err)
		}

		kv[key] = parsed
	}

	if err := sc.Err(); err != nil {
		return nil, err
	}

	return kv, nil
}


func parseValue(raw string) (string, error) {
	if raw == "" {
		return "", nil
	}

	// unwrap quoted lines
	if len(raw) >= 2 && raw[0] == '"' && raw[len(raw)-1] == '"' {
		return raw[1 : len(raw)-1], nil
	}

	return raw, nil
}


func CollectSetFlags(fs *flag.FlagSet) map[string]bool {
	set := map[string]bool{}
	fs.Visit(func(f *flag.Flag) {
		set[f.Name] = true
	})
	return set
}


func ApplyConfigs(
	setFlags map[string]bool,
	kv map[string]string,
	podmanRoot *string,
	roStoragePath *string,
	mksquashfsPath *string,
	mksquashfsOpts *string,
	logLevel *string,
) {
	apply := func(flagName, key string, dst *string) {
		if dst == nil {
			return
		}
		if setFlags != nil && setFlags[flagName] {
			return
		}
		if v, ok := kv[key]; ok {
			*dst = v
		}
	}

	apply("podmanRoot", "PARALLAX_PODMAN_ROOT", podmanRoot)
	apply("roStoragePath", "PARALLAX_RO_STORAGE_PATH", roStoragePath)
	apply("mksquashfsPath", "PARALLAX_MKSQUASHFS_PATH", mksquashfsPath)
	apply("mksquashfs-opts", "PARALLAX_MKSQUASHFS_OPTS", mksquashfsOpts)
	apply("log-level", "PARALLAX_LOG_LEVEL", logLevel)
}

