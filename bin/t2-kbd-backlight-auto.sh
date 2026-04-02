#!/bin/sh
# T2 Suspend Fix - Keyboard Backlight Auto-off Service
# Automatically turns off keyboard backlight after idle time
# Uses swayidle to monitor user activity (Wayland only)

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
    exit 1
fi

# Configuration
LABEL="kbd-auto"
BACKLIGHT_DEVICE=":white:kbd_backlight"
IDLE_LIMIT=10000  # 10 seconds in milliseconds

# Check if backlight device exists
if ! brightnessctl -d "$BACKLIGHT_DEVICE" info >/dev/null 2>&1; then
    t2_log "$LABEL" "ERROR: Backlight device $BACKLIGHT_DEVICE not found"
    exit 1
fi

# Check for active Wayland session
get_wayland_session() {
    local uid
    uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
    if [ -z "$uid" ]; then
        return 1
    fi

    # Check for Wayland session specifically
    local session_type
    session_type=$(loginctl show-session "$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | head -n1)" -p Type 2>/dev/null | cut -d= -f2)

    if [ "$session_type" != "wayland" ]; then
        return 1
    fi

    echo "$uid"
    return 0
}

# Validate session before starting
SESSION_UID=$(get_wayland_session)
if [ -z "$SESSION_UID" ]; then
    t2_log "$LABEL" "No Wayland session found, exiting gracefully"
    # Exit gracefully - this is expected behavior when no Wayland session is active
    exit 0
fi

# Check WAYLAND_DISPLAY environment variable
if [ -z "$WAYLAND_DISPLAY" ]; then
    # Try to detect from session
    if [ -S "/run/user/$SESSION_UID/bus" ]; then
        export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$SESSION_UID/bus"
    fi

    # Log but continue - swayidle might still work in some cases
    t2_log "$LABEL" "WARNING: No WAYLAND_DISPLAY variable set"
fi

# Log startup
USERNAME=$(id -nu "$SESSION_UID" 2>/dev/null || echo "unknown")
t2_log "$LABEL" "Starting keyboard backlight auto-off service (idle limit: ${IDLE_LIMIT}ms, user: $USERNAME)"

# Main idle monitoring loop
# swayidle exits if it can't connect to the display, which is the desired behavior
exec swayidle -w \
    timeout "$IDLE_LIMIT" "/usr/bin/brightnessctl -d $BACKLIGHT_DEVICE set 0% -q" \
    resume "/usr/bin/brightnessctl -d $BACKLIGHT_DEVICE set 10% -q"
