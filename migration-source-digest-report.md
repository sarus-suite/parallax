# Parallax Migration with Tags and Digests

A reference such as `registry.example/team/app:stable@sha256:<source>` gives Parallax two pieces of information. The digest pins the source image to squash, and `registry.example/team/app:stable` names the result in the shared store. The migrated image needs a usable tag, a digest for its own manifest, and a way to look it up by its original digest. A later migration of the same tag with a different source digest should move the tag while preserving the previous image by ID and under any other tags it owns.

## Why lookup breaks

The original migration path passed the full input through name resolution and into `containers/storage` as a name. A tag-only lookup then had no matching name in the destination. Docker-style normalization also drops the tag from a combined reference, so lookup through that path uses `registry.example/team/app@sha256:<source>`. That form needs a matching repository and an entry in the digest index. The migration recorded only the new digest in the index because flattening rewrites the layer list and image config. The original digest was still embedded in the stored name. [Docker reference normalization](https://github.com/containers/image/blob/v5.36.2/docker/reference/normalize.go#L64) · [Parallax image lookup](common/imageutil.go#L74)

## How this branch handles migration

### Choose the source and destination

Parallax reads the tag and digest from the input. Each has a different job.

- `repo@digest` selects the source image in the local store.
- The normalized `repo:tag` names the migrated image in the shared store.

Parallax checks that the source manifest matches the requested digest. If the default manifest has a different digest, Parallax checks for a match among the stored alternate manifests. [Reference parsing and source verification](cmd/migration.go#L157)

### Save both digests

The flattened manifest remains the default, and its digest remains the image’s primary digest. Parallax saves the verified source manifest bytes under `manifest-parallax-source-<digest>`. [Source manifest storage](cmd/migration.go#L141)

`containers/storage` builds its digest index from the primary digest and the digests of data entries whose keys start with `manifest`. Podman uses that index and the repository name to build `RepoDigests`. This makes the original digest available for local lookup. A reader that verifies the bytes of the flattened manifest uses the flattened digest. [Storage digest index](https://github.com/containers/storage/blob/v1.59.1/images.go#L452) · [Podman `RepoDigests`](https://github.com/containers/common/blob/main/libimage/image.go#L698)

### Move the tag when the replacement is ready

If the tag already points to a complete migration with the requested source digest, Parallax skips the work. [Repeat check](cmd/migration.go#L203)

For a different source digest, Parallax creates an unnamed replacement and writes its squash files and metadata. Once those are ready, it moves the tag with `Store.AddNames`. The previous image remains available by ID and through any other tags it owns. [Tag publication](cmd/migration.go#L118)

If preparation fails, Parallax discards the scratch copy and removes any squash file created by that attempt. It reports writeback errors to the caller. [Scratch cleanup](cmd/migration.go#L350)

The fix applies to new tagged digest migrations and assumes one writer per shared store.

## Verification

`go test ./...` and local storage checks passed for alternate manifest selection, digest persistence across reload, and tag transfer. The new Bats test covers no-pull execution by tag, both digest entries, repeat migration, tag replacement, and retry after a partial squash failure. Running that test end to end requires a rootless Podman environment with FUSE and Skopeo. [Bats coverage](tests/image_references.bats#L190)
