package common

import (
	"fmt"
	"strings"

	"github.com/containers/image/v5/pkg/shortnames"
	"github.com/containers/image/v5/pkg/sysregistriesv2"
	"github.com/containers/storage"
)

// We get fully qualified name
func CanonicalImageName(ref string) (string, error) {
	parts := strings.Split(ref, ":")
	name := parts[0]

	// if there is no tag, we default it to latest
	tag := "latest"
	if len(parts) == 2 && parts[1] != "" {
		tag = parts[1]
	}

	if shortnames.IsShortName(ref) {
		alias, _, err := sysregistriesv2.ResolveShortNameAlias(nil, name)
		if err != nil {
			return "", err
		}
		name = alias.Name()
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

