package common

import (
	"fmt"
	"strings"

	"github.com/containers/image/v5/pkg/shortnames"
	"github.com/containers/image/v5/pkg/sysregistriesv2"
	"github.com/containers/storage"
)

// We get fully qualified name with more robust Resolve()
func CanonicalImageName(ref string) (string, error) {
	parts := strings.Split(ref, ":")
	name := parts[0]

	// default to "latest"
	tag := "latest"
	if len(parts) == 2 && parts[1] != "" {
		tag = parts[1]
	}

	if shortnames.IsShortName(ref) {
		candidates, err := shortnames.Resolve(nil, ref)
		if err != nil {
			return "", fmt.Errorf("failed to resolve short name %q: %w", ref, err)
		}
		if len(candidates) == 0 {
			return "", fmt.Errorf("no resolution candidates found for short name %q", ref)
		}
		name = candidates[0].String() // take first candidate
		return name, nil // Already includes tag
	}

	return fmt.Sprintf("%s:%s", name, tag), nil
}

func FindImage(store storage.Store, name string) (storage.Image, error){
	canonical, err := CanonicalImageName(name)
	if err != nil {
		return storage.Image{}, fmt.Errorf("Resolving canonical name %q: %w", name, err)
	}
	imgs, err := store.Images()
	if err != nil {
		return storage.Image{}, fmt.Errorf("Liust iamges: %w", err)
	}
	for _, img := range imgs {
		for _, tag := range img.Names {
			if tag == name || tag == canonical {
				return img, nil
			}
		}
	}
	return storage.Image{}, fmt.Errorf("Image not found: %q", name)
}

