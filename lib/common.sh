#!/bin/sh
# T2 Suspend Fix - Common Library
# Shared functions for all T2 suspend fix scripts

# Log file location
T2_LOG_FILE="${T2_LOG_FILE:-/var/log/t2-suspend-fix.log}"

# Hardware configuration file
T2_HARDWARE_CONF="${T2_HARDWARE_CONF:-/etc/t2-suspend-fix/hardware.conf}"

# Logging function
# Usage: t2_log <label> <message>
t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" >> "$T2_LOG_FILE" 2>/dev/null || true
}

# Get active user session info
# Returns: "uid:dbus_path" or empty string if no session
get_user_session() {
    local uid
    uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
    if [ -z "$uid" ]; then
        return 1
    fi
    local dbus_path="/run/user/$uid/bus"
    if [ ! -S "$dbus_path" ]; then
        return 1
    fi
    echo "$uid:$dbus_path"
}

# Retry a command with multiple attempts
# Usage: retry_command <label> <max_attempts> <command> [args...]
# Returns: 0 on success, 1 on failure
retry_command() {
    local label="$1"
    local max_attempts="$2"
    shift 2
    local cmd="$@"
    
    for i in $(seq 1 "$max_attempts"); do
        if eval "$cmd" 2>/dev/null; then
            t2_log "$label" "OK: command succeeded after $i/$max_attempts attempts"
            return 0
        fi
        sleep 0.5
    done
    
    t2_log "$label" "ERROR: command failed after $max_attempts attempts"
    return 1
}

# Check if a systemd service exists
# Usage: check_service_exists <service_name>
# Returns: 0 if exists, 1 if not
check_service_exists() {
    local svc="$1"
    systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"
}

# Load kernel module if not already loaded
# Usage: load_mod <module_name>
load_mod() {
    local mod="$1"
    if lsmod | grep -q "^${mod}"; then
        t2_log "resume" "No load needed for $mod"
        return 0
    fi
    
    /usr/bin/modprobe "$mod" 2>/dev/null || true
    if lsmod | grep -q "^${mod}"; then
        t2_log "resume" "OK: $mod loaded"
        return 0
    else
        t2_log "resume" "ERROR: $mod not loaded"
        return 1
    fi
}

# Unload kernel module if loaded
# Usage: unload_mod <module_name>
unload_mod() {
    local mod="$1"
    if ! lsmod | grep -q "^${mod}"; then
        t2_log "suspend" "No unload needed for $mod"
        return 0
    fi
    
    /usr/bin/modprobe -r "$mod" 2>/dev/null || true
    if ! lsmod | grep -q "^${mod}"; then
        t2_log "suspend" "OK: $mod unloaded"
        return 0
    else
        t2_log "suspend" "ERROR: $mod still loaded"
        return 1
    fi
}

# Start a systemd service with retry
# Usage: start_service <service_name> [label]
start_service() {
    local svc="$1"
    local label="${2:-resume}"
    
    if ! check_service_exists "$svc"; then
        t2_log "$label" "SKIP: $svc not installed"
        return 0
    fi
    
    systemctl start "$svc" --no-block 2>/dev/null || true
    
    for i in $(seq 1 20); do
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            t2_log "$label" "OK: $svc started after $i/20 attempts"
            return 0
        fi
        sleep 0.5
    done
    
    t2_log "$label" "ERROR: $svc start timed out after 10s"
    return 1
}

# Stop a systemd service with retry
# Usage: stop_service <service_name> [label]
stop_service() {
    local svc="$1"
    local label="${2:-suspend}"
    
    if ! check_service_exists "$svc"; then
        t2_log "$label" "SKIP: $svc not installed"
        return 0
    fi
    
    systemctl stop "$svc" --no-block 2>/dev/null || true
    
    for i in $(seq 1 20); do
        if ! systemctl is-active "$svc" >/dev/null 2>&1; then
            t2_log "$label" "OK: $svc stopped after $i/20 attempts"
            return 0
        fi
        sleep 0.5
    done
    
    t2_log "$label" "ERROR: $svc stop timed out after 10s"
    return 1
}

# Detect and source hardware configuration
# Sets: HAS_GMUX, HAS_AMD_GPU, HAS_SURROUND_AUDIO, HAS_TINYDFR, etc.
detect_hardware() {
    if [ -f "$T2_HARDWARE_CONF" ]; then
        # shellcheck source=/dev/null
        . "$T2_HARDWARE_CONF"
        return 0
    fi
    
    # Set defaults if config doesn't exist
    HAS_GMUX=""
    HAS_AMD_GPU=""
    HAS_SURROUND_AUDIO=""
    HAS_TINYDFR=""
    return 1
}

# Get DRM connector names for Intel and AMD GPUs
# Usage: get_drm_connectors
# Sets: INTEL_CONN, AMD_CONN (global variables)
get_drm_connectors() {
    INTEL_CONN=""
    AMD_CONN=""
    
    for card in /sys/class/drm/card[0-9]*; do
        [ -d "$card" ] || continue
        
        local driver
        driver=$(cat "$card/device/uevent" 2>/dev/null | grep "^DRIVER=" | cut -d= -f2)
        
        for conn in "$card"/*-eDP-*; do
            [ -f "$conn/status" ] || continue
            
            local connname
            connname=$(basename "$conn")
            
            if [ "$driver" = "i915" ]; then
                INTEL_CONN="$connname"
            elif [ "$driver" = "amdgpu" ]; then
                AMD_CONN="$connname"
            fi
        done
    done
}

# Set backlight brightness with retry
# Usage: set_backlight <device> <value>
# Device examples: ":white:kbd_backlight", "gmux_backlight"
set_backlight() {
    local device="$1"
    local value="$2"
    local label="backlight"
    
    for i in $(seq 1 10); do
        local set_output
        set_output=$(brightnessctl -d "$device" set "$value" 2>&1)
        local current
        current=$(brightnessctl -d "$device" get 2>/dev/null)
        
        case "$set_output" in
            *"$current"*)
                t2_log "$label" "OK: $device set to $value after $i/10 attempts"
                return 0
                ;;
        esac
        sleep 0.5
    done
    
    t2_log "$label" "ERROR: could not set $device after 10 attempts"
    return 1
}
