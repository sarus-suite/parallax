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



###########################
# General support functions
###########################

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

ensure_directory_exists() {
    local dir_path="$1"

    mkdir -p "$dir_path" || handle_error "Failed to create directory: $dir_path"
}

ensure_open_tmp_permissions() {
    local dir_path="$1"

    mkdir -p "$dir_path" || handle_error "Failed to create directory: $dir_path"
    chmod 1777 "$dir_path" || handle_error "Failed to set permissions on directory: $dir_path"
}




###########################
# Configuration file logic
###########################
DEFAULT_CONFIG="/etc/parallax-mount.conf"

CONFIG_FILE="${PARALLAX_MP_CONFIG:-$DEFAULT_CONFIG}"
## lets source the config if it is there, silent skip if file is not there
if [ -r "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE" \
      || { echo "Error: failed to load config $CONFIG_FILE" >&2; exit 1; }
fi

## Defaults and validation
LOG_LEVEL="${PARALLAX_MP_LOGLEVEL:-INFO}"  # Set log level or default to INFO
TEMP_MOUNT_UID="${PARALLAX_MP_UID:-$UID}"
TEMP_PARENT="/tmp/parallax-${TEMP_MOUNT_UID}"
TEMP_MOUNT_ROOT="${PARALLAX_MP_TMPDIR:-$TEMP_PARENT/mount_program}"
LOG_FILE="${PARALLAX_MP_LOGFILE:-$TEMP_PARENT/mount_program.log}" # Set log file

: "${PARALLAX_MP_INOTIFYWAIT_CMD:=inotifywait}"
: "${PARALLAX_MP_FUSE_OVERLAYFS_CMD:=fuse-overlayfs}"
: "${PARALLAX_MP_SQUASHFUSE_CMD:=squashfuse_ll}"
# ignore squashfuse flag if not set
#: "${PARALLAX_MP_SQUASHFUSE_FLAG:=''}"


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
    echo "Error: $cfg must be set (env or config)" >&2
    exit 1
  fi
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: $cmd not found or not executable" >&2
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

## Ensure log file directory exists or create it if possible
mkdir -p "$(dirname "$LOG_FILE")" || { echo "Error: Failed to create log directory" >&2; exit 1; }
ensure_open_tmp_permissions "$TEMP_PARENT"
ensure_open_tmp_permissions "$TEMP_MOUNT_ROOT"
## Ensure LOG_LEVEL is valid; default to INFO
if [[ -z "${LOG_LEVELS[$LOG_LEVEL]}" ]]; then
    echo "Invalid log level '$LOG_LEVEL'. Defaulting to INFO." >&2
    LOG_LEVEL="INFO"
fi


###########################
# Logic support functions
###########################

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


wait_for_mount_ready() {
    local mount_point="$1"
    local relpath="${2:-}"   # relative path to check within container path. Optional for debugging

    # Hardcoded try loop defaults. 50 sec wait max.
    local tries=500
    local delay=0.1

    for i in $(seq 1 "$tries"); do
        if mountpoint -q "$mount_point"; then
            # Force traversal (also dereferences symlinks)
            if ls -1 "$mount_point"/ >/dev/null 2>&1; then

                # If a relpath is requested, validate the "superset" readiness:
                # exists as a regular file AND can actually be opened/read
                if [[ -n "$relpath" ]]; then
                    local p="$mount_point/$relpath"
                    if [[ -f "$p" ]] && head -c 1 "$p" >/dev/null 2>&1; then
                        log "INFO" "Mount ready (opened $relpath): $mount_point"
                    else
                        log "INFO" "Mount not ready ($relpath): $mount_point"
                        sleep "$delay"
                        continue
                    fi
                else
                    log "INFO" "Mount ready: $mount_point"
                fi

                if check_log_level "DEBUG"; then
                    ls -la "$mount_point"/ >>"$LOG_FILE" 2>&1
                    if [[ -n "$relpath" ]]; then
                        ls -la "$mount_point/$(dirname "$relpath")" >>"$LOG_FILE" 2>&1 || true
                        ls -la "$mount_point/$relpath" >>"$LOG_FILE" 2>&1 || true
                        head -n 5 "$mount_point/$relpath" >>"$LOG_FILE" 2>&1 || true
                    fi
                fi

                return 0
            fi
        fi

        log "INFO" "Mount not ready (${relpath:-<none>}): $mount_point"
        sleep "$delay"
    done

    log "ERROR" "Timed out waiting for mount: $mount_point (relpath=${relpath:-<none>})"
    return 1
}




do_squash_mount() {
    local squash_file="$1"
    local target_dir="$2"

    if [[ -n "$PARALLAX_MP_SQUASHFUSE_FLAG" ]]; then
        IFS=' ' read -r -a PARALLAX_MP_SQUASHFUSE_FLAG_ARR <<< "$PARALLAX_MP_SQUASHFUSE_FLAG"
    else
        PARALLAX_MP_SQUASHFUSE_FLAG_ARR=()
    fi

	# Optional uid/gid passthrough (both needs to be set)
    local PARALLAX_MP_UID_GID_OPTS=()
    if [[ -n "${PARALLAX_MP_UID:-}" && -n "${PARALLAX_MP_GID:-}" ]]; then
        PARALLAX_MP_UID_GID_OPTS=(-o "uid=${PARALLAX_MP_UID},gid=${PARALLAX_MP_GID}")
        log "INFO" "Applying squashfuse uid/gid mapping: uid=${PARALLAX_MP_UID} gid=${PARALLAX_MP_GID}"
    fi

    local SQUASHFUSE_OPTS=(
        "${PARALLAX_MP_SQUASHFUSE_FLAG_ARR[@]}"
        "${PARALLAX_MP_UID_GID_OPTS[@]}"
    )

    # Here we only check if link is a symlink to the actual squash file, as this is what Parallax migration does
    if [ -h "$squash_file" ]; then
        log "INFO" "Running (Mounting squash file.): $SQUASHFUSE_CMD ${SQUASHFUSE_OPTS[*]}"
        output=$("$SQUASHFUSE_CMD" "${SQUASHFUSE_OPTS[@]}" "$squash_file" "$target_dir" 2>&1)
        exit_code=$?

        if [ $exit_code -eq 0 ]; then
            log "INFO" "Mounting squash file successful"
        else
            log "WARNING" "Mounting squash file failed: $output"

            if echo "$output" | grep -q "mountpoint is not empty"; then
                log "WARNING" "Retry squashfuse with -o nonempty"
                run_and_log "Mounting squash file." "$SQUASHFUSE_CMD" "$squash_file" "$target_dir" "${SQUASHFUSE_OPTS[@]}" -o nonempty

                if [ $? -ne 0 ]; then
                    handle_error "squashfuse failed after retry"
                fi
			else
				handle_error "squashfuse failed WITHOUT retry"
			fi
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

create_temp_lowerdir_mountpoint() {
    ensure_directory_exists "$TEMP_MOUNT_ROOT"

    mktemp -d "$TEMP_MOUNT_ROOT/lowerdir.XXXXXX" \
        || handle_error "Failed to create temporary lowerdir mountpoint in $TEMP_MOUNT_ROOT"
}

replace_lowerdir_target() {
    local replacement_dir="$1"
    shift

    local rewritten_args=()
    local arg
    local lowerdir_value=""
    local rewritten_lowerdir=""

    for arg in "$@"; do
        if [[ "$arg" == *"lowerdir="* ]]; then
            lowerdir_value="${arg#*lowerdir=}"
            lowerdir_value="${lowerdir_value%%,upperdir*}"
            log "INFO" "Found lowerdir argument: $lowerdir_value"

            rewritten_lowerdir="$replacement_dir"
            if [[ "$lowerdir_value" == *:* ]]; then
                rewritten_lowerdir="${lowerdir_value%:*}:$replacement_dir"
            fi
            log "INFO" "Replacing lowerdir with: $rewritten_lowerdir"

            arg="${arg/lowerdir=$lowerdir_value/lowerdir=$rewritten_lowerdir}"
        fi

        rewritten_args+=("$arg")
    done

    if [ -z "$lowerdir_value" ]; then
        handle_error "No lowerdir argument found while rewriting fuse-overlayfs arguments"
    fi

    printf '%s\n' "${rewritten_args[@]}"
}

cleanup_temp_lowerdir_mountpoint() {
    local temp_lowerdir="$1"

    if [ -z "$temp_lowerdir" ]; then
        return 0
    fi

    if mountpoint -q "$temp_lowerdir"; then
        log "INFO" "Attempt unmounting temporary lowerdir $temp_lowerdir"
        unmount_with_retries "$temp_lowerdir"
    fi

    if [ -d "$temp_lowerdir" ]; then
        rmdir "$temp_lowerdir" 2>/dev/null \
            && log "INFO" "Removed temporary lowerdir $temp_lowerdir" \
            || log "WARNING" "Could not remove temporary lowerdir $temp_lowerdir"
    fi
}

#########################
# Watcher unmount process
#########################
run_watcher() {
    local mount_dir="$1"
    local temp_lowerdir="$2"

    # Validate inputs
    if [ ! -d "$mount_dir" ]; then
        log "ERROR" "Mount directory $mount_dir does not exist or is not accessible"
        return 1
    fi

    if [ ! -d "$temp_lowerdir" ]; then
        log "ERROR" "Temporary lowerdir $temp_lowerdir does not exist"
        return 1
    fi

    log "INFO" "Starting squash watcher for temp lowerdir: $temp_lowerdir and mount directory: $mount_dir"

    if [ ! -d "$temp_lowerdir" ]; then
        log "INFO" "No temporary lowerdir found, watcher not needed"
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

    log "INFO" "Attempt unmounting $mount_dir"
    unmount_with_retries "$mount_dir"

    cleanup_temp_lowerdir_mountpoint "$temp_lowerdir"

    log "INFO" "Watcher DONE for $mount_dir"
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

##########################
# Core mount program logic
##########################
main() {
    verify_dependencies

    # Extract lower directory and squash file
    LOWER_DIR=$(echo "$@" | sed 's/,upperdir.*//' | sed 's/.*lowerdir=//' | sed 's/.*://')
    MOUNT_DIR=$(echo "$@" | sed 's/.* //')
    local TEMP_LOWER_DIR=""
    local FUSE_MOUNT_ARGS=()

    # Squash check
    verify_file_exists "${LOWER_DIR}.squash"
    SQUASH=$?

    if [ "$SQUASH" -eq 1 ]; then
      log "INFO" "Squashed container mount"

      verify_mount_point "$MOUNT_DIR"
      TEMP_LOWER_DIR=$(create_temp_lowerdir_mountpoint)

      # Do the mounts
      do_squash_mount "${LOWER_DIR}.squash" "$TEMP_LOWER_DIR"

      #wait_for_mount_ready "${TEMP_LOWER_DIR}" "opt/nvidia/nvidia_entrypoint.sh" || handle_error "squashfuse mount not ready: $TEMP_LOWER_DIR"
      wait_for_mount_ready "${TEMP_LOWER_DIR}" || {
          cleanup_temp_lowerdir_mountpoint "$TEMP_LOWER_DIR"
          handle_error "squashfuse mount not ready: $TEMP_LOWER_DIR"
      }

      mapfile -t FUSE_MOUNT_ARGS < <(replace_lowerdir_target "$TEMP_LOWER_DIR" "$@")

	  do_fuse_mount "${FUSE_MOUNT_ARGS[@]}"
      if [ $? -ne 0 ]; then
          cleanup_temp_lowerdir_mountpoint "$TEMP_LOWER_DIR"
          handle_error "Fuse-overlayfs mount failed"
      fi

      #wait_for_mount_ready "$MOUNT_DIR" "opt/nvidia/nvidia_entrypoint.sh" || handle_error "overlay mount not ready: $MOUNT_DIR"
      wait_for_mount_ready "$MOUNT_DIR" || {
          cleanup_temp_lowerdir_mountpoint "$TEMP_LOWER_DIR"
          handle_error "overlay mount not ready: $MOUNT_DIR"
      }

      # Permission reset
      run_and_log "Updating permissions for $MOUNT_DIR" chmod a+rx "$MOUNT_DIR"
      run_and_log "Listing directory for $MOUNT_DIR" ls -ld "$MOUNT_DIR"

      # Watcher as background process to unmount
      # "0<&-" drop stdin
      # "&>/dev/null" discard output
      run_watcher "$MOUNT_DIR" "$TEMP_LOWER_DIR" 0<&- &>/dev/null &
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
