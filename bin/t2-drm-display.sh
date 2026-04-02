#!/bin/sh
# T2 Suspend Fix - DRM Display Control
# Usage: drm-display.sh <on|off>
# Controls display power state for Intel and AMD eDP connectors

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# Fixed label for logging
LABEL="drm-display"

# Validate argument
ACTION="$1"
if [ -z "$ACTION" ]; then
    t2_log "$LABEL" "ERROR: No action specified (use 'on' or 'off')"
    exit 1
fi

if [ "$ACTION" != "on" ] && [ "$ACTION" != "off" ]; then
    t2_log "$LABEL" "ERROR: Invalid action '$ACTION' (use 'on' or 'off')"
    exit 1
fi

# Set target and check status based on action
if [ "$ACTION" = "on" ]; then
    TARGET_STATUS="connected"
    CHECK_STATUS="disconnected"
else
    TARGET_STATUS="disconnected"
    CHECK_STATUS="connected"
fi

t2_log "$LABEL" "Starting DRM display $ACTION..."

# Function to control display
control_display() {
    local conn="$1"
    local path="/sys/class/drm/${conn}"
    
    [ -f "$path/status" ] || return 0
    
    local current_status
    current_status=$(cat "$path/status" 2>/dev/null)
    if [ "$current_status" != "$CHECK_STATUS" ]; then
        # Already in target state or doesn't exist
        t2_log "$LABEL" "SKIP: $conn already $ACTION"
        return 0
    fi
    
    t2_log "$LABEL" "Turning $ACTION $conn..."
    
    for i in $(seq 1 10); do
        echo "$ACTION" > "$path/status" 2>/dev/null
        local status
        status=$(cat "$path/status" 2>/dev/null)
        if [ "$status" = "$TARGET_STATUS" ]; then
            t2_log "$LABEL" "OK: $path $ACTION after $i/10 attempts"
            return 0
        fi
        sleep 0.5
    done
    
    t2_log "$LABEL" "ERROR: failed to turn $ACTION $path"
    return 1
}

# Find connectors
INTEL_CONN=""
AMD_CONN=""

get_drm_connectors

# Log found connectors
if [ -n "$INTEL_CONN" ]; then
    t2_log "$LABEL" "Found Intel eDP: $INTEL_CONN"
fi

if [ -n "$AMD_CONN" ]; then
    t2_log "$LABEL" "Found AMD eDP: $AMD_CONN"
fi

# Control displays in order:
# - Turn off: AMD first, then Intel
# - Turn on: Intel first, then AMD
if [ "$ACTION" = "off" ]; then
    [ -n "$AMD_CONN" ] && control_display "$AMD_CONN"
    [ -n "$INTEL_CONN" ] && control_display "$INTEL_CONN"
else
    [ -n "$INTEL_CONN" ] && control_display "$INTEL_CONN"
    [ -n "$AMD_CONN" ] && control_display "$AMD_CONN"
fi

exit 0
