package common

import (
	"errors"
	"fmt"
	"strings"

	"github.com/containers/image/v5/docker/reference"
	"github.com/containers/image/v5/pkg/shortnames"
	"github.com/containers/storage"
	"github.com/opencontainers/go-digest"
)


func splitNameTag(ref string) (string, string) {
    lastColon := strings.LastIndex(ref, ":")
	lastSlash := strings.LastIndex(ref, "/")

	// Only pick tag as last content after ":" and non empty
	if lastColon > lastSlash && lastColon != -1 {
		return ref[:lastColon], ref[lastColon+1:]
	}

	// we did not find a tag
	return ref, "latest"
}


func hasRegistry(name string) bool {
    first := name

	// find first slash and keep what is before it
	i := strings.IndexRune(name, '/')
	if i != -1 {
        first = name[:i]
	}

    isLocalhost := (first == "localhost")
	hasDomain := strings.Contains(first, ".")
	hasPort := strings.Contains(first, ":")

	return isLocalhost || hasDomain || hasPort
}



// We get fully qualified name with more robust Resolve()
func CanonicalImageName(ref string) (string, error) {
    name, tag := splitNameTag(ref)

	if hasRegistry(name) {
        return fmt.Sprintf("%s:%s", name, tag), nil
	}

	if shortnames.IsShortName(ref) {
		resolved, err := shortnames.Resolve(nil, ref)
		if err != nil {
			return "", fmt.Errorf("failed to resolve short name %q: %w", ref, err)
		}

		if len(resolved.PullCandidates) == 0 {
			return "", fmt.Errorf("no resolution candidates found for short name %q", ref)
		}

		// take first candidate
		candidate := resolved.PullCandidates[0]
		// Candidate already includes tag
		return candidate.Value.String(), nil
	}

	return fmt.Sprintf("%s:%s", name, tag), nil
}

func FindImage(store storage.Store, name string) (storage.Image, error) {
	// Storage resolves exact names, full IDs, and unique ID prefixes.
	if img, err := store.Image(name); err == nil {
		return *img, nil
	} else if !errors.Is(err, storage.ErrImageUnknown) {
		return storage.Image{}, fmt.Errorf("Find image %q: %w", name, err)
	}

	// Manifest digests use a separate index. For named digests, also
	// require a matching repository so a different name cannot select it.
	d, digestErr := digest.Parse(name)
	repository := ""
	if named, err := reference.ParseNormalizedNamed(name); err == nil {
		if digested, ok := named.(reference.Digested); ok {
			d, digestErr = digested.Digest(), nil
			repository = named.Name()
		}
	}
	if digestErr == nil {
		matches, err := store.ImagesByDigest(d)
		if err != nil {
			return storage.Image{}, fmt.Errorf("Find image by digest %q: %w", name, err)
		}
		var match *storage.Image
		for _, img := range matches {
			if repository != "" {
				matchesRepository := false
				for _, n := range img.Names {
					if named, err := reference.ParseNormalizedNamed(n); err == nil && named.Name() == repository {
						matchesRepository = true
						break
					}
				}
				if !matchesRepository {
					continue
				}
			}
			if match != nil && match.ID != img.ID {
				return storage.Image{}, fmt.Errorf("Ambiguous image digest: %q", name)
			}
			match = img
		}
		if match != nil {
			return *match, nil
		}
		return storage.Image{}, fmt.Errorf("Image not found: %q", name)
	}

	imgs, err := store.Images()
	if err != nil {
		return storage.Image{}, fmt.Errorf("List images: %w", err)
	}

	base, tag := splitNameTag(name)

	// Build candidate name options
	normalized := fmt.Sprintf("%s:%s", base, tag)

	localhostName := ""
	if !hasRegistry(base) {
		localhostName = fmt.Sprintf("localhost/%s:%s", base, tag)
	}

	canonical := ""
	if fq, err := CanonicalImageName(name); err == nil {
		canonical = fq
	}

	// loop over all images and its name for a match
	for _, img := range imgs {
		for _, n := range img.Names {
			isNormalized := (n == normalized)
			isLocalhost := (n == localhostName)
			isCanonical := (n == canonical)

			if isNormalized || isLocalhost || isCanonical {
				return img, nil
			}
		}
	}

	return storage.Image{}, fmt.Errorf("Image not found: %q", name)
}

