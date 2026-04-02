#!/bin/sh
# T2 Suspend Fix - DRM Display Control
# Usage: drm-display.sh <on|off>
# Controls display power state for Intel, AMD, and Touchbar DRM connectors

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
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

# Function to control a single display
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
            t2_log "$LABEL" "OK: $conn $ACTION after $i/10 attempts"
            return 0
        fi
        sleep 0.5
    done
    
    t2_log "$LABEL" "ERROR: failed to turn $ACTION $conn"
    return 1
}

# Scan DRM connectors and control them based on driver type
# Order: AMD (first off, second on), Intel (second off, first on), Touchbar (last)
INTEL_CONN=""
AMD_CONN=""
TOUCHBAR_CONN=""

for card in /sys/class/drm/card[0-9]*; do
    [ -d "$card" ] || continue
    
    driver=$(cat "$card/device/uevent" 2>/dev/null | grep "^DRIVER=" | cut -d= -f2)
    
    case "$driver" in
        "i915")
            # Intel GPU - find eDP connector
            for conn in "$card"/*-eDP-*; do
                [ -f "$conn/status" ] || continue
                INTEL_CONN=$(basename "$conn")
                t2_log "$LABEL" "Found Intel eDP: $INTEL_CONN"
                break
            done
            ;;
        "amdgpu")
            # AMD GPU - find eDP connector
            for conn in "$card"/*-eDP-*; do
                [ -f "$conn/status" ] || continue
                AMD_CONN=$(basename "$conn")
                t2_log "$LABEL" "Found AMD eDP: $AMD_CONN"
                break
            done
            ;;
        "appletbdrm")
            # Touchbar DRM - find USB connector
            for conn in "$card"/*-USB-*; do
                [ -f "$conn/status" ] || continue
                TOUCHBAR_CONN=$(basename "$conn")
                t2_log "$LABEL" "Found Touchbar DRM: $TOUCHBAR_CONN"
                break
            done
            ;;
    esac
done

# Control displays in order:
# - Turn off: AMD first, then Intel, then Touchbar
# - Turn on: Intel first, then AMD, then Touchbar
if [ "$ACTION" = "off" ]; then
    [ -n "$AMD_CONN" ] && control_display "$AMD_CONN"
    [ -n "$INTEL_CONN" ] && control_display "$INTEL_CONN"
    [ -n "$TOUCHBAR_CONN" ] && control_display "$TOUCHBAR_CONN"
else
    [ -n "$INTEL_CONN" ] && control_display "$INTEL_CONN"
    [ -n "$AMD_CONN" ] && control_display "$AMD_CONN"
    [ -n "$TOUCHBAR_CONN" ] && control_display "$TOUCHBAR_CONN"
fi

exit 0
