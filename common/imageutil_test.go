package common

import (
	"path/filepath"
	"strings"
	"testing"

	"github.com/containers/storage"
	"github.com/opencontainers/go-digest"
)

func TestFindImageReferences(t *testing.T) {
	// Use an isolated VFS store to exercise storage's real lookup indexes
	// without requiring overlay mounts or pulling images.
	dir := t.TempDir()
	store, err := storage.GetStore(storage.StoreOptions{
		GraphRoot:       filepath.Join(dir, "root"),
		RunRoot:         filepath.Join(dir, "run"),
		GraphDriverName: "vfs",
	})
	if err != nil {
		t.Fatal(err)
	}
	// Release the store before t.TempDir removes its files.
	t.Cleanup(func() {
		if _, err := store.Shutdown(false); err != nil {
			t.Error(err)
		}
	})

	// Image records are enough for lookup; no layers or manifest blobs are needed.
	// Distinct fixed IDs make abbreviated-ID selection deterministic.
	id := strings.Repeat("a", 64)
	d := digest.FromString("manifest")
	_, err = store.CreateImage(id, []string{"example.com/test:latest", "localhost/test:latest"}, "", "", &storage.ImageOptions{Digest: d})
	if err != nil {
		t.Fatal(err)
	}
	// Reuse the repository path and tag under another registry, with different
	// content, so the assertions can distinguish the two images.
	otherID := strings.Repeat("b", 64)
	otherDigest := digest.FromString("other registry manifest")
	if _, err := store.CreateImage(otherID, []string{"other.example.com/test:latest"}, "", "", &storage.ImageOptions{Digest: otherDigest}); err != nil {
		t.Fatal(err)
	}

	// IDs and bare digests identify images independently of registry names.
	// Named digests must match the repository, and existing name lookup still works.
	for _, tc := range []struct {
		ref    string
		wantID string
	}{
		{id, id},
		{id[:12], id},
		{d.String(), id},
		{"example.com/test@" + d.String(), id},
		{"example.com/test:latest", id},
		{"example.com/test", id},
		{otherID, otherID},
		{otherID[:12], otherID},
		{otherDigest.String(), otherID},
		{"other.example.com/test@" + otherDigest.String(), otherID},
	} {
		t.Run(tc.ref, func(t *testing.T) {
			img, err := FindImage(store, tc.ref)
			if err != nil {
				t.Fatal(err)
			}
			if img.ID != tc.wantID {
				t.Fatalf("image ID = %q, want %q", img.ID, tc.wantID)
			}
		})
	}

	// Reject both unknown digests and known digests paired with the wrong registry.
	// Preserve the missing-image error text used by migration's existence check.
	for _, ref := range []string{
		digest.FromString("missing").String(),
		"other.example.com/test@" + d.String(),
		"example.com/test@" + otherDigest.String(),
	} {
		t.Run(ref, func(t *testing.T) {
			if _, err := FindImage(store, ref); err == nil || !strings.Contains(err.Error(), "Image not found") {
				t.Fatalf("lookup error = %v, want image not found", err)
			}
		})
	}
}
