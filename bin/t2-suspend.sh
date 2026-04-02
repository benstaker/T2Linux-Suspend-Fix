#!/bin/sh

# Source common library and hardware config
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
    detect_hardware
fi

# Configuration flags (defaults if hardware.conf not found)
APPLE_BCE_RELOAD=true
APPLE_GMUX_RELOAD="${HAS_GMUX:-true}"
SENSORS_RELOAD=true
TOUCHBAR_RELOAD=true
WIFI_RELOAD=true

LABEL="suspend"

t2_log "$LABEL" "Starting suspend sequence..."

# Stop user services
stop_service tiny-dfr
stop_service t2fanrd

# Stop audio
/usr/local/bin/t2-stop-audio.sh

# Turn off keyboard backlight
t2_log "$LABEL" "Turning off keyboard backlight..."
/usr/bin/brightnessctl -sd :white:kbd_backlight set 0 -q 2>/dev/null || true

# Unload WiFi
if [ "$WIFI_RELOAD" = true ]; then
    unload_mod brcmfmac_wcc
    unload_mod brcmutil
fi

# Unload Touchbar
if [ "$TOUCHBAR_RELOAD" = true ]; then
    unload_mod hid_appletb_bl
    unload_mod hid_appletb_kbd
    unload_mod appletbdrm
fi

# Unload Sensors
if [ "$SENSORS_RELOAD" = true ]; then
    unload_mod hid_sensor_als
    unload_mod hid_sensor_rotation
    unload_mod hid_sensor_iio_common
    unload_mod industrialio_triggered_buffer
    unload_mod industrialio
fi

# Turn off internal display before unloading gmux
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    /usr/local/bin/t2-drm-display.sh off
fi

# Unload Apple GMUX
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    unload_mod apple_gmux
fi

# Unload Apple BCE
if [ "$APPLE_BCE_RELOAD" = true ]; then
    unload_mod apple_bce
fi

t2_log "$LABEL" "Suspend complete, ready to sleep"
