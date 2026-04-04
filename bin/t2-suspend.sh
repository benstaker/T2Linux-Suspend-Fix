#!/bin/sh

# Source common library and hardware config
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
    exit 1
fi

# Load hardware configuration
load_hardware_config

LABEL="suspend"

t2_log "$LABEL" "Starting suspend sequence..."

stop_service tiny-dfr

/usr/local/bin/t2-stop-audio.sh

# Turn off keyboard backlight
t2_log "$LABEL" "Turning off keyboard backlight..."
/usr/bin/brightnessctl -sd :white:kbd_backlight set 0 -q 2>/dev/null || true

# Unload Touchbar
if [ "$HAS_TOUCHBAR" = true ]; then
    unload_mod hid_appletb_bl
    unload_mod hid_appletb_kbd
    unload_mod appletbdrm
fi

# Unload Sensors
if [ "$HAS_SENSORS" = true ]; then
    unload_mod hid_sensor_als
    unload_mod hid_sensor_rotation
    unload_mod hid_sensor_iio_common
    unload_mod industrialio_triggered_buffer
    unload_mod industrialio
fi

if [ "$HAS_GMUX" = true ]; then
    # Turn off DRM displays
    /usr/local/bin/t2-drm-display.sh off
    # Unload Apple GMUX
    unload_mod apple_gmux
fi

# Unload Apple BCE
if [ "$HAS_APPLE_BCE" = true ]; then
    unload_mod apple_bce
fi

stop_service t2fanrd
stop_service upower
stop_service NetworkManager

t2_log "$LABEL" "Suspend complete, ready to sleep"
