#!/bin/sh
# T2 Suspend Fix - Hardware Detection
# Detects hardware capabilities and generates configuration

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
else
    echo "Error: common.sh not found" >&2
    exit 1
fi

T2_HARDWARE_CONF="${T2_HARDWARE_CONF:-/etc/t2-suspend-fix/hardware.conf}"

# Detect GMUX presence (indicates dual-GPU system with hardware switch)
detect_gmux() {
    # Check for gmux_backlight device - this indicates actual GMUX hardware
    if [ -d "/sys/class/backlight" ]; then
        for bl in /sys/class/backlight/*/; do
            if [ -f "$bl/type" ]; then
                if grep -q "gmux" "$bl/type" 2>/dev/null; then
                    echo "true"
                    return
                fi
            fi
            # Also check the device name
            if echo "$bl" | grep -q "gmux"; then
                echo "true"
                return
            fi
        done
    fi
    
    # Check if gmux_backlight device exists by name
    if [ -e "/sys/class/backlight/gmux_backlight" ]; then
        echo "true"
        return
    fi
    
    # Fallback: Check for both Intel AND AMD GPUs present (dual-GPU indicator)
    local has_intel=false
    local has_amd=false
    
    if [ -d "/sys/class/drm" ]; then
        for card in /sys/class/drm/card[0-9]*/; do
            [ -d "$card" ] || continue
            if [ -f "$card/device/uevent" ]; then
                if grep -q "DRIVER=i915" "$card/device/uevent" 2>/dev/null; then
                    has_intel=true
                elif grep -q "DRIVER=amdgpu" "$card/device/uevent" 2>/dev/null; then
                    has_amd=true
                fi
            fi
        done
    fi
    
    # Only report GMUX if we have BOTH GPUs
    if [ "$has_intel" = "true" ] && [ "$has_amd" = "true" ]; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Detect AMD GPU presence
detect_amd_gpu() {
    # Check lspci for AMD graphics (specific to Radeon/AMD GPUs)
    if command -v lspci >/dev/null 2>&1; then
        # Look for AMD/ATI GPU specifically, not just any AMD device
        if lspci 2>/dev/null | grep -qiE "(radeon|amd.*(rx|hd|r[0-9])|ati.*technologies)"; then
            echo "true"
            return
        fi
    fi
    
    # Check for loaded amdgpu module (only if actually loaded, not just available)
    if lsmod 2>/dev/null | grep -q "^amdgpu"; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Detect surround audio capability
detect_surround_audio() {
    # Check for T2 DSP with surround configuration
    # This is a heuristic based on speaker count
    
    # Check if we can detect from PipeWire
    if command -v wpctl >/dev/null 2>&1; then
        # Check for multiple speaker channels
        local speaker_count
        speaker_count=$(wpctl status 2>/dev/null | grep -c "input.filter-chain-speaker" 2>/dev/null | head -n1 || echo "0")
        
        if [ "$speaker_count" -gt 2 ] 2>/dev/null; then
            echo "true"
            return
        fi
    fi
    
    # Check audio hardware profile
    if [ -f "/proc/asound/cards" ]; then
        # MacBook Pro 16" typically has different audio hardware than 13"
        if grep -q "MacBookPro16" /proc/asound/cards 2>/dev/null || \
           grep -q "MacBookPro15" /proc/asound/cards 2>/dev/null; then
            echo "true"
            return
        fi
    fi
    
    # Default to stereo for unknown configurations
    echo "false"
}

# Detect tiny-dfr presence
detect_tiny_dfr() {
    # Check if tiny-dfr service is installed
    if systemctl list-unit-files "tiny-dfr.service" 2>/dev/null | grep -q "tiny-dfr.service"; then
        echo "true"
        return
    fi
    
    # Check if tiny-dfr binary exists
    if command -v tiny-dfr >/dev/null 2>&1 || [ -f "/usr/bin/tiny-dfr" ]; then
        echo "true"
        return
    fi
    
    echo "false"
}

# Detect if Apple BCE module is available
detect_apple_bce() {
    if lsmod 2>/dev/null | grep -q "^apple_bce" || [ -d "/sys/module/apple_bce" ]; then
        echo "true"
        return
    fi
    # Check if module is available
    if modinfo apple_bce >/dev/null 2>&1; then
        echo "true"
        return
    fi
    echo "false"
}

# Detect if touchbar modules are available
detect_touchbar() {
    if lsmod 2>/dev/null | grep -q "^appletb" || [ -d "/sys/module/appletbdrm" ]; then
        echo "true"
        return
    fi
    # Check if modules are available
    if modinfo appletbdrm >/dev/null 2>&1; then
        echo "true"
        return
    fi
    echo "false"
}

# Detect if sensor modules are available
detect_sensors() {
    if lsmod 2>/dev/null | grep -q "^hid_sensor" || [ -d "/sys/module/industrialio" ]; then
        echo "true"
        return
    fi
    # Check if modules are available
    if modinfo industrialio >/dev/null 2>&1; then
        echo "true"
        return
    fi
    echo "false"
}

# Detect if WiFi modules are available
detect_wifi() {
    if lsmod 2>/dev/null | grep -q "^brcm" || [ -d "/sys/module/brcmfmac" ]; then
        echo "true"
        return
    fi
    # Check if modules are available
    if modinfo brcmfmac >/dev/null 2>&1; then
        echo "true"
        return
    fi
    echo "false"
}

t2_log "hw-detect" "Starting hardware detection..."

# Create config directory
mkdir -p "$(dirname "$T2_HARDWARE_CONF")"

# Write configuration file
cat > "$T2_HARDWARE_CONF" << EOF
# T2 Suspend Fix - Hardware Configuration
# Generated: $(date -Iseconds)
HAS_GMUX=$(detect_gmux)
HAS_AMD_GPU=$(detect_amd_gpu)
HAS_SURROUND_AUDIO=$(detect_surround_audio)
HAS_TINYDFR=$(detect_tiny_dfr)
HAS_APPLE_BCE=$(detect_apple_bce)
HAS_TOUCHBAR=$(detect_touchbar)
HAS_SENSORS=$(detect_sensors)
HAS_WIFI=$(detect_wifi)
EOF

t2_log "hw-detect" "Hardware configuration written to $T2_HARDWARE_CONF"
echo "Configuration saved to: $T2_HARDWARE_CONF":
echo ""
cat "$T2_HARDWARE_CONF"
