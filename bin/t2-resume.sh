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

LABEL="resume"

t2_log "$LABEL" "Starting resume..."

# Load Apple BCE
if [ "$APPLE_BCE_RELOAD" = true ]; then
    load_mod apple_bce
fi

# Load Apple GMUX
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    load_mod apple_gmux
fi

# Load Sensors
if [ "$SENSORS_RELOAD" = true ]; then
    load_mod industrialio
    load_mod hid_sensor_rotation
fi

# Load WiFi
if [ "$WIFI_RELOAD" = true ]; then
    load_mod brcmutil
    load_mod brcmfmac
    load_mod brcmfmac_wcc
fi

# Wait for touchbar modules
/usr/local/bin/t2-wait-lsmod.sh appletbdrm 10

# Turn on keyboard backlight
/usr/local/bin/t2-fix-backlight.sh :white:kbd_backlight 10%

# Restart audio
/usr/local/bin/t2-start-audio.sh
/usr/local/bin/t2-set-default-audio.sh

# Start user services
start_service t2fanrd
start_service tiny-dfr

# Fix DRM display
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    /usr/local/bin/t2-drm-display.sh off
    /usr/local/bin/t2-drm-display.sh on
    /usr/local/bin/t2-fix-backlight.sh gmux_backlight 10%
fi 

t2_log "$LABEL" "Resume complete"
