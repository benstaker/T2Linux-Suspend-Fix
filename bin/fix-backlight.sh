#!/bin/sh
# T2 Suspend Fix - Backlight Control
# Usage: fix-backlight.sh <device> [value]
# Device examples: :white:kbd_backlight, gmux_backlight
# Value: brightness value (default: 10%)

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

# Fixed label for logging
LABEL="fix-backlight"

# Validate arguments
DEVICE="$1"
VALUE="${2:-10%}"

if [ -z "$DEVICE" ]; then
    t2_log "$LABEL" "ERROR: No device specified"
    exit 1
fi

t2_log "$LABEL" "Setting $DEVICE to $VALUE..."

# Use shared set_backlight function
if set_backlight "$DEVICE" "$VALUE"; then
    exit 0
else
    t2_log "$LABEL" "ERROR: Failed to set $DEVICE"
    exit 1
fi
