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

    # Debug: Monitor all module loading for 8s after apple_bce
    # t2_log "$LABEL" "DEBUG: Monitoring module loading after apple_bce..."
    # for i in 1 2 3 4 5 6 7 8; do
    #     mods=$(lsmod | awk 'NR>1 {print $1}' | tr '\n' ' ')
    #     t2_log "$LABEL" "DEBUG: t=${i}s modules: $mods"
    #     sleep 1
    # done

    # Wait for sensors auto-loaded by apple_bce
    /usr/local/bin/t2-wait-lsmod.sh industrialio 10
fi

# Start t2fanrd service
start_service t2fanrd

# Load WiFi
if [ "$HAS_WIFI" = true ]; then
    load_mod brcmutil
    load_mod brcmfmac
    load_mod brcmfmac_wcc
fi

# Turn on keyboard backlight
/usr/local/bin/t2-fix-backlight.sh :white:kbd_backlight 10%

# Load Apple GMUX
if [ "$HAS_GMUX" = true ]; then
    load_mod apple_gmux
fi

# Turn on DRM display
/usr/local/bin/t2-drm-display.sh on

# Correct GMUX backlight
if [ "$HAS_GMUX" = true ]; then
    /usr/local/bin/t2-fix-backlight.sh gmux_backlight 10%
fi

# Restart audio
/usr/local/bin/t2-start-audio.sh
/usr/local/bin/t2-set-default-audio.sh

# Reload Touchbar keyboard
if [ "$HAS_TOUCHBAR" = true ]; then
    unload_mod hid_appletb_kbd
    load_mod hid_appletb_kbd
fi

# Start tiny-dfr service
start_service tiny-dfr

t2_log "$LABEL" "Resume complete"
