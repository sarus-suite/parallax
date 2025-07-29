#!/usr/bin/env bash
#
# Usage: --storage-opt mount_program=/path/to/parallax-mount-program.sh
#
# Handles overlay and SquashFS mounting for Parallax-migrated Podman images that use the "overlay" storage driver
#
# Requires: fuse-overlayfs, squashfuse, inotifywait
#
# This is a wrapper to: https://github.com/containers/fuse-overlayfs/blob/main/fuse-overlayfs.1.md

UMOUNT_WAIT_RETRIES=${UMOUNT_WAIT_RETRIES:-"100000"}
UMOUNT_WAIT_DELAY=${UMOUNT_WAIT_DELAY:-"30"}

# Log levels as an associative array!
declare -A LOG_LEVELS
LOG_LEVELS=( ["ERROR"]=0 ["WARNING"]=1 ["INFO"]=2 ["DEBUG"]=3 )

LOG_LEVEL="${PARALLAX_MP_LOGLEVEL:-INFO}"  # Set log level or default to INFO
LOG_FILE="${PARALLAX_MP_LOGFILE:-/tmp/parallax-${UID}/mount_program.log}" # Set log file
mkdir -p "$(dirname "$LOG_FILE")"

###########################
# Configuration file logic
###########################
DEFAULT_CONFIG="/etc/parallax-mount.conf"

CONFIG_FILE="${PARALLAX_MP_CONFIG:-$DEFAULT_CONFIG}"
## lets source the config if it is there, silent skip if file is not there
if [ -r "$CONFIG_FILE" ]; then
	log "INFO" "Reading config file $CONFIG_FILE"
    source "$CONFIG_FILE" \
      || { echo "Error: failed to load config $CONFIG_FILE" >&2; exit 1; }
fi

## Defaults and validation
: "${PARALLAX_MP_INOTIFYWAIT_CMD:=inotifywait}"
: "${PARALLAX_MP_FUSE_OVERLAYFS_CMD:=fuse-overlayfs}"
: "${PARALLAX_MP_SQUASHFUSE_CMD:=squashfuse}"
: "${PARALLAX_MP_SQUASHFUSE_FLAG:=''}"

REQUIRED_CFG_VARS=(
  PARALLAX_MP_INOTIFYWAIT_CMD
  PARALLAX_MP_FUSE_OVERLAYFS_CMD
  PARALLAX_MP_SQUASHFUSE_CMD
)
# for each required config var
for cfg in "${REQUIRED_CFG_VARS[@]}"; do
  # expand the variable from the config list
  cmd="${!cfg}"
  if [ -z "$cmd" ]; then
    echo "Error: $var must be set (env or config)" >&2
    exit 1
  fi
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $var=\"$cmd\" not found or not executable" >&2
    exit 1
  fi
done
INOTIFYWAIT_CMD="${PARALLAX_MP_INOTIFYWAIT_CMD}"
FUSE_OVERLAYFS_CMD="${PARALLAX_MP_FUSE_OVERLAYFS_CMD}"
SQUASHFUSE_CMD="${PARALLAX_MP_SQUASHFUSE_CMD}"

# List of all dependency-tools
DEPENDENCIES=(
  "$INOTIFYWAIT_CMD"
  "$FUSE_OVERLAYFS_CMD"
  "$SQUASHFUSE_CMD"
)

verify_dependencies

## Ensure log file directory exists or create it if possible
mkdir -p "$(dirname "$LOG_FILE")" || { echo "Error: Failed to create log directory" >&2; exit 1; }
## Ensure LOG_LEVEL is valid; default to INFO
if [[ -z "${LOG_LEVELS[$LOG_LEVEL]}" ]]; then
    echo "Invalid log level '$LOG_LEVEL'. Defaulting to INFO." >&2
    LOG_LEVEL="INFO"
fi


check_log_level() {
    local msg_level="$1"

    local level_index="${LOG_LEVELS[$LOG_LEVEL]}"
    local msg_index="${LOG_LEVELS[$msg_level]}"

    [[ $msg_index -le $level_index ]]
}

log() {
    local level="$1"
    local message="$2"

    if check_log_level "$level"; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $level: $message" >> "$LOG_FILE"
    fi
}

# Support functions
handle_error() {
    log "ERROR" "$1"
    echo "Error: $1" >&2
    exit 1
}

verify_dependencies() {
    for dep in "${DEPENDENCIES[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            handle_error "Missing required dependency: $dep"
        fi
    done
    log "INFO" "All dependencies are available"
}

# TODO: consider logic swap, normally a return 1 means error but I did the exist with a 1
verify_file_exists() {
    local file="$1"
    if [ ! -e "$file" ]; then
        return 0
    elif [ ! -r "$file" ]; then
        return 0
    fi
    log "INFO" "Verified file exists and is readable: $file"
    return 1
}

verify_mount_point() {
    local mount_point="$1"
    if [ ! -d "$mount_point" ]; then
        handle_error "Mount point does not exist or is not a directory: $mount_point"
    fi
    if mountpoint -q "$mount_point"; then
        handle_error "Mount point is already in use: $mount_point"
    fi
    log "INFO" "Verified mount point is valid: $mount_point"
}

unmount_with_retries() {
    local mount_path="$1"

    if [ ! -e "$mount_path" ]; then
        log "INFO" "Path $mount_path does not exist; nothing to unmount."
        return
    fi

    for i in $(seq "$UMOUNT_WAIT_RETRIES"); do
        if [ ! -e "$mount_path" ]; then
            log "INFO" "Path $mount_path does not exist; nothing to unmount."
            return
        fi
		# TODO: check if path is a valid mount point before unmount try
        umount -v "$mount_path" >>"$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log "INFO" "Successfully unmounted $mount_path"
            return
        fi
        log "INFO" "Unmount failed, retrying in $UMOUNT_WAIT_DELAY seconds"
        sleep "$UMOUNT_WAIT_DELAY"
    done
    handle_error "Failed to unmount $mount_path after $UMOUNT_WAIT_RETRIES retries"
}

do_squash_mount() {
    local squash_file="$1"
    local target_dir="$2"

	# Here we only check if link is a symlink to the actual squash file, as this is what Parallax migration does
    if [ -h "$squash_file" ]; then
        run_and_log "Mounting squash file." "$SQUASHFUSE_CMD" "$squash_file" "$target_dir" "$PARALLAX_MP_SQUASHFUSE_FLAG"
        if [ $? -ne 0 ]; then
            handle_error "squashfuse failed"
        fi
    else
        log "INFO" "No squash file detected, skipping squash mount"
    fi
}

do_fuse_mount() {
    run_and_log "Exec fuse-overlayfs mount" "$FUSE_OVERLAYFS_CMD" "$@"
 #   if [ $? -ne 0 ]; then
 #       handle_error "Fuse-overlayfs mount failed"
 #   fi
 #   log "INFO" "Fuse-overlayfs mount successful"
}

# Watcher unmount process
run_watcher() {
    local mount_dir="$1"
    local squash_file="$2"

    # Validate inputs
    if [ ! -d "$mount_dir" ]; then
        log "ERROR" "Mount directory $mount_dir does not exist or is not accessible"
        return 1
    fi

    if [ ! -e "$squash_file" ]; then
        log "ERROR" "Squash file $squash_file does not exist"
        return 1
    fi

    log "INFO" "Starting squash watcher for: $squash_file and mount directory: $mount_dir"

    if [ ! -e "$squash_file" ]; then
        log "INFO" "No squash file found, watcher not needed"
        return
    fi

    # Wait until container stops, FS check (inotifywait in quiet mode and event delete)
    log "INFO" "Starting inotifywait -q -e delete $mount_dir/etc"
    output=$("$INOTIFYWAIT_CMD" -q -e delete "$mount_dir/etc" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 1 ]; then
        log "INFO" "inotifywait detected an expected event: $output"
    elif [ $exit_code -eq 2 ]; then
        log "INFO" "inotifywait exited due to timeout: $output"
    else
        log "ERROR" "inotifywait failed with exit code $exit_code: $output"
    fi

    log "INFO" "Attempt unmounting $squash_file"
    unmount_with_retries "$squash_file"

    log "INFO" "Watcher DONE for $squash_file"
}

run_and_log() {
    local description="$1"
    shift                    # Remove description from args
    local cmd=("$@")         # Get command

	log "INFO" "Running ($description): ${cmd[*]}"
    output=$("${cmd[@]}" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log "ERROR" "$description failed: $output"
        return $exit_code
    else
        log "INFO" "$description successful: $output"
        return 0
    fi
}

# Core logic
main() {
#    verify_dependencies

    # Extract lower directory and squash file
    LOWER_DIR=$(echo "$@" | sed 's/,upperdir.*//' | sed 's/.*lowerdir=//' | sed 's/.*://')
    MOUNT_DIR=$(echo "$@" | sed 's/.* //')

    # Squash check
    verify_file_exists "${LOWER_DIR}.squash"
    SQUASH=$?

    if [ "$SQUASH" -eq 1 ]; then
      log "INFO" "Squashed container mount"

      verify_mount_point "$MOUNT_DIR"

      # Do the mounts
      do_squash_mount "${LOWER_DIR}.squash" "$LOWER_DIR"
      do_fuse_mount "$@"

      # Permission reset
      run_and_log "Updating permissions for $MOUNT_DIR" chmod a+rx $MOUNT_DIR
      run_and_log "Listing directory for $MOUNT_DIR" ls -ld $MOUNT_DIR >> $LOG_FILE

      # Watcher as background process to unmount
      # "0<&-" drop stdin
      # "&>/dev/null" discard output
      run_watcher "$MOUNT_DIR" "${LOWER_DIR}" 0<&- &>/dev/null &
      watcher_pid=$!
      log "INFO" "Watcher process started with PID: $watcher_pid"
    else
          log "INFO" "Normal container mount"
          do_fuse_mount "$@"
    fi
}

# Entry point
main "$@"

exit 0
