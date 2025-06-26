# parallax

*parallax* turbocharges Podman on HPC systems by providing an efficient and read-only container image storage for parallel filesystems. With parallax, users can migrate images, leverage SquashFS, and manage distributed storage.
*parallax* is a Go utility that directly uses the container storage libraries to ensure compatibility with Podman.

## Why parallax?
* Faster and lighter containers. It uses SquashFS images that boosts start times and runtimes.
* Shared storage ready. Run Podman with container image store located in parallel filesystems.
* Enhances Podman's overlay driver. No changes to your workflows are needed.
* Pull-once, run-everywhere. Using Podman in a cluster does not require pulling iamges on every node, instead run directly from shared FS.

## How it works?
1. Migrate your container image to a shared, read-only store.
2. Integrates with Podman via our custom mount\_program script that provides overlay + SquashFS support.
3. Easy management. Listing and removing image data from the store.


## Quick start
### 0. Install dependencies
~~~
go >= 1.24
libbtrfs-dev
device-mapper-devel
mksquashfs
fuse-overlayfs
squashfuse
inotifywait
~~~

### 1. Build
~~~
    go mod tidy
    go build -o parallax
~~~

### 2. Pull an image
~~~
    podman \
        --root "/path/to/your/podmanroot" \
        --runroot "/path/to/runroot" \
        pull docker.io/library/hello-world:linux
~~~

### 3. Migrate an Image
~~~
    parallax \
        --podmanRoot "/path/to/your/podmanroot" \
        --roStoragePath "/path/to/your/nfs/parallax/store" \
        --mksquashfsPath "/path/to/your/mksquashfs/binary" \
        --log-level info \
        --migrate \
        --image docker.io/library/hello-world:linux
~~~

### 4. Run from parallax store
~~~
    podman \
        --root "/path/to/your/podmanroot" \
        --runroot "/path/to/runroot" \
        --storage-opt additionalimagestore=/path/nfs/parallax/store \
        --storage-opt mount_program=/parallax_path/scripts/parallax-mount-program.sh \
        run --rm docker.io/library/hello-world:linux
~~~
Note: using `--storage-opt` cli option makes podman ignore the default storage configuration file.

### 5. List images
~~~
    podman \
        --root "/path/to/your/podmanroot" \
        --storage-opt additionalimagestore=/path/nfs/parallax/store \
        ls
~~~

### 6. Remove an image
~~~
    parallax \
        --podmanRoot "/path/to/your/podmanroot" \
        --roStoragePath "/path/to/your/nfs/parallax/store" \
        --mksquashfsPath "/path/to/your/mksquashfs/binary" \
        --log-level info \
        --rmi \
        --image docker.io/library/hello-world:linux
~~~


## Requirements
* Go 1.22+
* Podman 5.5.0+
* System utilities: mksquashfs, fuse-overlayfs, squashfuse, inotifywait
* Linux

## Technical overview

* parallax utility helps you migrate and manage an enhanced, distributed, read-only image store for Podman.
* parallax-mount-program.sh: Is a mount program to be used by Podman that makes usage of the enhanced store transparent.

## Podman Integration: Custom Overlay Mount Program
Parallax is designed to work with Podman’s overlay storage, especially for parallel filesystems like NFS-backeds enhancing them with read-only SquashFS stores.
Use the provided script [`scripts/parallax-mount-program.sh`](scripts/parallax-mount-program.sh) as the Podman overlay `mount_program`. This enables:
- Automatic SquashFS mounting of migrated images
- Robust mount/unmount logic for NFS and similar backends
- Enhanced logging and dependency checks
- To be used as `--storage-opt mount_program=...` in Podman
- Requires: fuse-overlayfs, squashfuse, inotifywait

## Technical Design Goals

* Integrates with existing container libraries avoiding custom code when possible. Relies on well-tested libraries (containers/storage, container/image, opencontainers/go-digest)
* Simple project structure. Modular and with clear separation of concerns to facilitate maintainability and readibility.
* Explicit CLI interface. Uses Go core flag package, for simplicity.
* Robust logging. Structured logging via logrus library, for enhancing debugging and monitoring.
* Strong Error Handling. We try to enforce good use of error handling, explicit logging of issues, and graceful shutdowns.

