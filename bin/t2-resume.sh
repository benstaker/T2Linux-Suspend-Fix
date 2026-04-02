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

LABEL="resume"

t2_log "$LABEL" "Starting resume..."

# Load Apple BCE
if [ "$HAS_APPLE_BCE" = true ]; then
    load_mod apple_bce
    # Wait for module auto-loaded by apple_bce
    /usr/local/bin/t2-wait-lsmod.sh industrialio 20
fi

# Load Apple GMUX
if [ "$HAS_GMUX" = true ]; then
    load_mod apple_gmux
fi

# Load WiFi
if [ "$HAS_WIFI" = true ]; then
    load_mod brcmutil
    load_mod brcmfmac
    load_mod brcmfmac_wcc
fi

# Turn on DRM display
/usr/local/bin/t2-drm-display.sh on

# Correct GMUX backlight
if [ "$HAS_GMUX" = true ]; then
    /usr/local/bin/t2-fix-backlight.sh gmux_backlight 10%
fi

# Turn on keyboard backlight
/usr/local/bin/t2-fix-backlight.sh :white:kbd_backlight 10%

# Restart audio
/usr/local/bin/t2-start-audio.sh
/usr/local/bin/t2-set-default-audio.sh

# Start user services
start_service t2fanrd
start_service tiny-dfr

t2_log "$LABEL" "Resume complete"
