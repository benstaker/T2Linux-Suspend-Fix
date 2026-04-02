#!/bin/sh

# Source common library and hardware config
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
    detect_hardware
fi

LABEL="resume"

t2_log "$LABEL" "Starting resume..."

# Load Apple BCE
if [ "$HAS_APPLE_BCE" = true ]; then
    load_mod apple_bce
fi

# Load Apple GMUX
if [ "$HAS_GMUX" = true ]; then
    load_mod apple_gmux
fi

# Load Sensors
if [ "$HAS_SENSORS" = true ]; then
    load_mod industrialio
    load_mod hid_sensor_rotation
fi

# Load WiFi
if [ "$HAS_WIFI" = true ]; then
    load_mod brcmutil
    load_mod brcmfmac
    load_mod brcmfmac_wcc
fi

# Wait for touchbar modules
if [ "$HAS_TOUCHBAR" = true ]; then
    /usr/local/bin/t2-wait-lsmod.sh appletbdrm 10
fi

# Turn on keyboard backlight
/usr/local/bin/t2-fix-backlight.sh :white:kbd_backlight 10%

# Restart audio
/usr/local/bin/t2-start-audio.sh
/usr/local/bin/t2-set-default-audio.sh

# Start user services
start_service t2fanrd
start_service tiny-dfr

# Fix DRM display
if [ "$HAS_GMUX" = true ]; then
    /usr/local/bin/t2-drm-display.sh off
    /usr/local/bin/t2-drm-display.sh on
    /usr/local/bin/t2-fix-backlight.sh gmux_backlight 10%
fi 

t2_log "$LABEL" "Resume complete"
