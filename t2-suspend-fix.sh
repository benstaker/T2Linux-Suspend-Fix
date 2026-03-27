#!/bin/bash

# T2 MacBook Suspend Fix Installer - Use at your own risk!

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
LOG_FILE="/var/log/t2-suspend-fix.log"

t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" | tee -a "$LOG_FILE" 2>/dev/null || true
}

echo -e "${GREEN}=== T2 MacBook Suspend Fix Installer v${VERSION} ===${NC}\n"

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Error: Do not run this script as root. It will use sudo when needed.${NC}"
    exit 1
fi

# Prompt for mode
MODE="install"
echo -e "${YELLOW}Select action:${NC}"
echo "1) Install suspend fix"
echo "2) Uninstall suspend fix"
echo "3) Install apple-bce driver (no-state-suspend branch)"
echo "4) Uninstall apple-bce driver"
read -p "Choose [1-4]: " -n 1 -r
echo
if [[ $REPLY =~ ^[2]$ ]]; then
    MODE="uninstall"
elif [[ $REPLY =~ ^[1]$ ]]; then
    MODE="install"
elif [[ $REPLY =~ ^[3]$ ]]; then
    MODE="install-apple-bce"
elif [[ $REPLY =~ ^[4]$ ]]; then
    MODE="uninstall-apple-bce"
else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

if [ "$MODE" = "uninstall" ]; then
    # Confirm with user
    read -p "Continue with uninstall? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  - uninstall cancelled."
        exit 0
    fi
    echo -e "${YELLOW}⚙${NC} Uninstalling..."

    # Disable and remove (previous) fixes
    echo "  - Disabling services..."
    sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
    sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
    sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
    sudo systemctl disable t2-suspend.service 2>/dev/null || true
    sudo systemctl disable t2-resume.service 2>/dev/null || true
    sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
    sudo systemctl disable fix-gmux-backlight.service 2>/dev/null || true
    sudo systemctl disable fix-gmux-display.service 2>/dev/null || true
    sudo systemctl disable enable-wakeup-devices.service 2>/dev/null || true
    sudo systemctl disable suspend-amdgpu-unbind.service 2>/dev/null || true
    sudo systemctl disable resume-amdgpu-bind.service 2>/dev/null || true
    echo "  - Services disabled."

    echo "  - Removing unit files and scripts..."
    sudo rm -f /etc/systemd/system/suspend-fix-t2.service
    sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
    sudo rm -f /etc/systemd/system/resume-wifi-reload.service
    sudo rm -f /etc/systemd/system/t2-suspend.service
    sudo rm -f /etc/systemd/system/t2-resume.service
    sudo rm -f /etc/systemd/system/fix-kbd-backlight.service
    sudo rm -f /etc/systemd/system/fix-gmux-backlight.service
    sudo rm -f /etc/systemd/system/fix-gmux-display.service
    sudo rm -f /etc/systemd/system/enable-wakeup-devices.service
    sudo rm -f /etc/systemd/system/suspend-amdgpu-unbind.service
    sudo rm -f /etc/systemd/system/resume-amdgpu-bind.service
    sudo rm -f /usr/local/bin/t2-wait-apple-bce.sh
    sudo rm -f /usr/local/bin/t2-wait-brcmfmac.sh
    sudo rm -f /usr/local/bin/t2-suspend.sh
    sudo rm -f /usr/local/bin/t2-resume.sh
    sudo rm -f /usr/local/bin/fix-kbd-backlight.sh
    sudo rm -f /usr/local/bin/fix-gmux-backlight.sh
    sudo rm -f /usr/local/bin/drm-display-off.sh
    sudo rm -f /usr/local/bin/drm-display-on.sh
    sudo rm -f /usr/local/bin/enable-wakeup-devices.sh
    sudo rm -f /usr/local/bin/t2-stop-audio.sh
    sudo rm -f /usr/local/bin/t2-start-audio.sh
    sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
    sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
    echo "  - Unit files and scripts removed."

    echo "  - Reloading systemd..."
    sudo systemctl daemon-reload

    echo -e "${GREEN}Uninstall complete.${NC}"

    exit 0
fi

# Install apple-bce driver
if [ "$MODE" = "install-apple-bce" ]; then
    # Ensure commands available
    command -v git >/dev/null 2>&1 || { t2_log "ERROR: git not found"; exit 1; }
    command -v make >/dev/null 2>&1 || { t2_log "ERROR: make not found"; exit 1; }
    command -v nproc >/dev/null 2>&1 || { t2_log "ERROR: nproc not found"; exit 1; }
    
    # Confirm with user
    read -p "Continue with install-apple-bce? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  - install-apple-bce cancelled."
        exit 0
    fi
    echo -e "${YELLOW}⚙${NC} Installing apple-bce driver (no-state-suspend branch)..."
    
    BUILD_DIR="/tmp/apple-bce-build"
    
    # Clean up any previous build
    sudo rm -rf "$BUILD_DIR"
    
    # Clone repository
    echo "  - Cloning apple-bce repository..."
    if ! git clone https://github.com/deqrocks/apple-bce.git "$BUILD_DIR"; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        exit 1
    fi
    
    cd "$BUILD_DIR"
    
    # Checkout no-state-suspend branch
    echo "  - Checking out no-state-suspend branch..."
    if ! git checkout no-state-suspend; then
        echo -e "${RED}Error: Failed to checkout no-state-suspend branch${NC}"
        exit 1
    fi
    
    # Detect kernel compiler
    echo "  - Detecting kernel compiler..."
    KERNEL_COMPILER=""
    LD_COMPILER=""
    if grep -q "clang" /proc/version; then
        KERNEL_COMPILER="clang"
        LD_COMPILER="ld.lld"
        echo "    Kernel built with clang"
    elif grep -q "gcc" /proc/version; then
        KERNEL_COMPILER="gcc"
        LD_COMPILER="ld"
        echo "    Kernel built with gcc"
    else
        echo "    Could not detect kernel compiler, assuming gcc"
        KERNEL_COMPILER="gcc"
        LD_COMPILER="ld"
    fi
    
    # Build module with detected compiler
    echo "  - Building module..."
    if ! make CC="$KERNEL_COMPILER" LD="$LD_COMPILER" -j$(nproc); then
        echo -e "${RED}Error: Failed to build module${NC}"
        exit 1
    fi
    
    # Install module
    echo "  - Installing module..."
    if ! sudo make install; then
        echo -e "${RED}Error: Failed to install module${NC}"
        exit 1
    fi
    
    # Update module dependencies
    echo "  - Updating module dependencies..."
    sudo depmod -a
    
    # Rebuild initramfs (for both mkinitcpio and update-initramfs)
    echo "  - Rebuilding initramfs..."
    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo mkinitcpio -P
    elif command -v update-initramfs >/dev/null 2>&1; then
        sudo update-initramfs -u
    else
        echo -e "${YELLOW}Warning: Could not rebuild initramfs (neither mkinitcpio nor update-initramfs found)${NC}"
    fi
    
    # Clean up
    cd -
    sudo rm -rf "$BUILD_DIR"
    
    echo -e "${GREEN}apple-bce driver installed successfully.${NC}"
    echo -e "${YELLOW}NOTE: Reboot required to load the new driver.${NC}"
    
    exit 0
fi

# Uninstall apple-bce driver
if [ "$MODE" = "uninstall-apple-bce" ]; then
    # Confirm with user
    read -p "Continue with uninstall-apple-bce? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "  - uninstall-apple-bce cancelled."
        exit 0
    fi
    echo -e "${YELLOW}⚙${NC} Uninstalling apple-bce driver..."
    
    BUILD_DIR="/tmp/apple-bce-build"
    
    # Try to use make uninstall if build directory exists
    if [ -d "$BUILD_DIR" ] && [ -f "$BUILD_DIR/Makefile" ]; then
        echo "  - Attempting make uninstall..."
        cd "$BUILD_DIR"
        sudo make uninstall 2>/dev/null || true
        cd - >/dev/null
    fi
    
    # Find and remove only from updates directory (where make install puts out-of-tree modules)
    # Do NOT remove from kernel/drivers/staging (those are kernel's built-in drivers)
    echo "  - Searching for out-of-tree module files in updates directories..."
    MODULE_FILES=$(find /lib/modules -path "*/updates/*" -type f \( -name "apple-bce.ko*" -o -name "apple_bce.ko*" \) 2>/dev/null)
    
    if [ -z "$MODULE_FILES" ]; then
        echo -e "${YELLOW}No out-of-tree apple-bce module files found in updates directories${NC}"
        exit 0
    fi
    
    # Remove all found module files
    echo "  - Removing out-of-tree module files..."
    echo "$MODULE_FILES" | while read -r file; do
        echo "    Removing: $file"
        sudo rm -f "$file"
    done
    
    # Update module dependencies
    echo "  - Updating module dependencies..."
    sudo depmod -a
    
    # Rebuild initramfs
    echo "  - Rebuilding initramfs..."
    if command -v mkinitcpio >/dev/null 2>&1; then
        sudo mkinitcpio -P
    elif command -v update-initramfs >/dev/null 2>&1; then
        sudo update-initramfs -u
    fi
    
    # Clean up build directory
    if [ -d "$BUILD_DIR" ]; then
        echo "  - Cleaning up build directory..."
        sudo rm -rf "$BUILD_DIR"
    fi
    
    echo -e "${GREEN}apple-bce driver uninstalled.${NC}"
    echo -e "${YELLOW}NOTE: Reboot required to unload the driver completely.${NC}"
    
    exit 0
fi

# Ensure commands available
command -v brightnessctl >/dev/null 2>&1 || { t2_log "ERROR: brightnessctl not found"; exit 1; }
command -v swayidle >/dev/null 2>&1 || { t2_log "ERROR: swayidle not found"; exit 1; }
command -v wpctl >/dev/null 2>&1 || { t2_log "ERROR: wpctl not found"; exit 1; }

# Confirm with user
read -p "Continue with install? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "  - install cancelled."
    exit 0
fi

# Create 'fix-kbd-backlight' service
echo -e "\n${YELLOW}⚙${NC} Creating 'fix-kbd-backlight' service..."
sudo tee /etc/systemd/system/fix-kbd-backlight.service > /dev/null << 'EOF'
[Unit]
Description=Fix Apple BCE Keyboard Backlight
After=multi-user.target

[Service]
User=root
Type=oneshot
ExecStart=/usr/bin/bash /usr/local/bin/fix-kbd-backlight.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
echo -e "${GREEN}Done${NC}"

# Create 'fix-kbd-backlight.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 'fix-kbd-backlight.sh' script..."
sudo tee /usr/local/bin/fix-kbd-backlight.sh > /dev/null << 'EOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][kbd-bl] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting keyboard backlight fix..."

for i in $(seq 1 10); do
    SET_OUTPUT=$(brightnessctl -d :white:kbd_backlight set 10% 2>&1)
    CURRENT=$(brightnessctl -d :white:kbd_backlight get 2>/dev/null)
    case "$SET_OUTPUT" in
        *"$CURRENT"*)
            t2_log "OK: kbd backlight set to $CURRENT after $i/10 attempts"
            exit 0
            ;;
    esac
    sleep 0.5
done

t2_log "ERROR: could not set kbd backlight after 10 attempts"
exit 0
EOF
sudo chmod +x /usr/local/bin/fix-kbd-backlight.sh
echo -e "${GREEN}Done${NC}"

# Create 'fix-gmux-display' service
echo -e "\n${YELLOW}⚙${NC} Creating 'fix-gmux-display' service..."
sudo tee /etc/systemd/system/fix-gmux-display.service > /dev/null << 'EOF'
[Unit]
Description=Fix Apple GMUX Display After Resume
After=graphical.target

[Service]
User=root
Type=oneshot
ExecStart=/usr/local/bin/drm-display-off.sh
ExecStart=/usr/local/bin/drm-display-on.sh
ExecStart=/usr/local/bin/fix-gmux-backlight.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF
echo -e "${GREEN}Done${NC}"

# Create 'fix-gmux-backlight.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 'fix-gmux-backlight.sh' script..."
sudo tee /usr/local/bin/fix-gmux-backlight.sh > /dev/null << 'EOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][gmux-bl] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting gmux backlight fix..."

for i in $(seq 1 10); do
    SET_OUTPUT=$(brightnessctl -d gmux_backlight set 10% 2>&1)
    CURRENT=$(brightnessctl -d gmux_backlight get 2>/dev/null)
    case "$SET_OUTPUT" in
        *"$CURRENT"*)
            t2_log "OK: gmux backlight set to $CURRENT after $i/10 attempts"
            sleep 0.5
            exit 0
            ;;
    esac
    sleep 0.5
done

t2_log "ERROR: could not set gmux backlight after 10 attempts"
exit 0
EOF
sudo chmod +x /usr/local/bin/fix-gmux-backlight.sh
echo -e "${GREEN}Done${NC}"

# Create 'drm-display-off.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 'drm-display-off.sh' script..."
sudo tee /usr/local/bin/drm-display-off.sh > /dev/null << 'EOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][drm-off] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting DRM display off..."

turn_off_display() {
    local conn="$1"
    local path="/sys/class/drm/${conn}"
    [ -f "$path/status" ] || return 0
    if grep -q "connected" "$path/status" 2>/dev/null; then
        t2_log "Turning off $path"
        for i in $(seq 1 10); do
            echo off > "$path/status" 2>/dev/null
            STATUS=$(cat "$path/status" 2>/dev/null)
            if [ "$STATUS" = "disconnected" ]; then
                t2_log "OK: $path off after $i/10 attempts"
                return 0
            fi
            sleep 0.5
        done
        t2_log "ERROR: failed to turn off $path"
    fi
    return 0
}

INTEL_CONN="" AMD_CONN=""
for card in /sys/class/drm/card[0-9]*; do
    driver=$(cat "$card/device/uevent" 2>/dev/null | grep "^DRIVER=" | cut -d= -f2)
    for conn in "$card"/*-eDP-*; do
        if [ -f "$conn/status" ] && grep -q "connected" "$conn/status" 2>/dev/null; then
            connname=$(basename "$conn")
            if [ "$driver" = "i915" ]; then
                INTEL_CONN="$connname"
                t2_log "Found Intel eDP: $connname"
            elif [ "$driver" = "amdgpu" ]; then
                AMD_CONN="$connname"
                t2_log "Found AMD eDP: $connname"
            fi
        fi
    done
done

[ -n "$AMD_CONN" ] && turn_off_display "$AMD_CONN"
[ -n "$INTEL_CONN" ] && turn_off_display "$INTEL_CONN"

exit 0
EOF
sudo chmod +x /usr/local/bin/drm-display-off.sh
echo -e "${GREEN}Done${NC}"

# Create 'drm-display-on.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 'drm-display-on.sh' script..."
sudo tee /usr/local/bin/drm-display-on.sh > /dev/null << 'EOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][drm-on] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting DRM display on..."

turn_on_display() {
    local conn="$1"
    local path="/sys/class/drm/${conn}"
    [ -f "$path/status" ] || return 0
    if grep -q "disconnected" "$path/status" 2>/dev/null; then
        t2_log "Turning on $path"
        for i in $(seq 1 10); do
            echo on > "$path/status" 2>/dev/null
            STATUS=$(cat "$path/status" 2>/dev/null)
            if [ "$STATUS" = "connected" ]; then
                t2_log "OK: $path on after $i/10 attempts"
                return 0
            fi
            sleep 0.5
        done
        t2_log "ERROR: failed to turn on $path"
    fi
    return 0
}

INTEL_CONN="" AMD_CONN=""
for card in /sys/class/drm/card[0-9]*; do
    driver=$(cat "$card/device/uevent" 2>/dev/null | grep "^DRIVER=" | cut -d= -f2)
    for conn in "$card"/*-eDP-*; do
        if [ -f "$conn/status" ] && grep -q "disconnected" "$conn/status" 2>/dev/null; then
            connname=$(basename "$conn")
            if [ "$driver" = "i915" ]; then
                INTEL_CONN="$connname"
                t2_log "Found Intel eDP: $connname"
            elif [ "$driver" = "amdgpu" ]; then
                AMD_CONN="$connname"
                t2_log "Found AMD eDP: $connname"
            fi
        fi
    done
done

# Turn on Intel (primary) first
[ -n "$INTEL_CONN" ] && turn_on_display "$INTEL_CONN"
[ -n "$AMD_CONN" ] && turn_on_display "$AMD_CONN"

exit 0
EOF
sudo chmod +x /usr/local/bin/drm-display-on.sh
echo -e "${GREEN}Done${NC}"

# Create 't2-wait-apple-bce.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 't2-wait-apple-bce.sh' script..."
sudo tee /usr/local/bin/t2-wait-apple-bce.sh > /dev/null << 'EOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][wait-bce] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting wait for appletbdrm in lsmod..."
for i in $(seq 1 30); do
    if lsmod | grep -q "^appletbdrm"; then
        t2_log "OK: appletbdrm found in lsmod (attempt $i/15)"
        exit 0
    fi
    sleep 0.5
done
t2_log "ERROR: appletbdrm not found in lsmod after 15 attempts"
exit 1
EOF
sudo chmod +x /usr/local/bin/t2-wait-apple-bce.sh
echo -e "${GREEN}Done${NC}"

# Create 't2-stop-audio.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 't2-stop-audio.sh' script..."
sudo tee /usr/local/bin/t2-stop-audio.sh > /dev/null << 'AUDIOEOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][stop-audio] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Stopping PipeWire audio session..."

# Check if PipeWire is installed
if ! systemctl --user list-unit-files pipewire.socket 2>/dev/null | grep -q pipewire; then
    t2_log "SKIP: PipeWire not found (not installed)"
    exit 0
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "SKIP: no user session found"
    exit 0
fi
if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi
username=$(id -nu "$uid" 2>/dev/null) || exit 0
XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user stop pipewire.socket pipewire-pulse.socket \
        pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null
t2_log "OK: PipeWire stopped for user $username"
exit 0
AUDIOEOF
sudo chmod +x /usr/local/bin/t2-stop-audio.sh

# Create 't2-start-audio.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 't2-start-audio.sh' script..."
sudo tee /usr/local/bin/t2-start-audio.sh > /dev/null << 'AUDIOEOF'
#!/bin/sh
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][start-audio] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
t2_log "Starting PipeWire audio session..."

# Check if PipeWire is installed
if ! systemctl --user list-unit-files pipewire.socket 2>/dev/null | grep -q pipewire; then
    t2_log "SKIP: PipeWire not found (not installed)"
    exit 0
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "SKIP: no user session found"
    exit 0
fi
if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi
username=$(id -nu "$uid" 2>/dev/null) || exit 0
t2_log "Starting PipeWire for user $username (uid=$uid)..."
XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user start pipewire.socket pipewire-pulse.socket 2>/dev/null
t2_log "OK: PipeWire sockets started"

# Restore T2 DSP default devices if wpctl is available
if command -v wpctl >/dev/null 2>&1; then
    t2_log "Checking for T2 DSP devices (polling for 5s)..."
    # Poll for up to 5s for DSP devices to appear
    for i in $(seq 1 10); do
        T2_SPEAKERS=$(XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            wpctl status 2>/dev/null | grep -F '[Audio/Sink]' | grep -F 'input.filter-chain-speakers' | sed -n 's/.* \([0-9]\+\)\..*/\1/p')
        T2_MIC=$(XDG_RUNTIME_DIR="/run/user/$uid" \
            DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
            wpctl status 2>/dev/null | grep -F '[Audio/Source]' | grep -F 'output.filter-chain-mic' | sed -n 's/.* \([0-9]\+\)\..*/\1/p')
        if [ -n "$T2_SPEAKERS" ] || [ -n "$T2_MIC" ]; then
            break
        fi
        sleep 0.5
    done
    if [ -n "$T2_SPEAKERS" ]; then
        XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" wpctl set-default "$T2_SPEAKERS" 2>/dev/null
        t2_log "OK: T2 speakers set to $T2_SPEAKERS"
    else
        t2_log "NOTE: T2 speakers not found after 5s"
    fi
    if [ -n "$T2_MIC" ]; then
        XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" wpctl set-default "$T2_MIC" -s 2>/dev/null
        t2_log "OK: T2 mic set to $T2_MIC"
    else
        t2_log "NOTE: T2 mic not found after 5s"
    fi
fi
t2_log "OK: audio services started"
exit 0
AUDIOEOF
sudo chmod +x /usr/local/bin/t2-start-audio.sh
echo -e "${GREEN}Done${NC}"

# Create log file
echo -e "\n${YELLOW}⚙${NC} Creating log file '/var/log/t2-suspend-fix.log'..."
sudo touch /var/log/t2-suspend-fix.log
sudo chmod 666 /var/log/t2-suspend-fix.log
echo -e "${GREEN}Done${NC}"

# Create 't2-suspend.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 't2-suspend.sh' script..."
sudo tee /usr/local/bin/t2-suspend.sh > /dev/null << 'SUSPEND_EOF'
#!/bin/sh

APPLE_BCE_RELOAD=true # Unloads and reloads apple_bce module
APPLE_GMUX_RELOAD=true # Unloads and reloads apple_gmux module
SENSORS_RELOAD=true # Unloads and reloads sensor driver modules
TOUCHBAR_RELOAD=true # Unloads and reloads touchbar driver modules
WIFI_RELOAD=true # Unloads and reloads WiFi driver modules

LOG_FILE="/var/log/t2-suspend-fix.log"

t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][suspend] $*" >> "$LOG_FILE" 2>/dev/null || true
}
lsmod_log() {
    lsmod | grep -E 'apple|bcm|brcm|industrialio|kfifo|sensor|sparse' >> "$LOG_FILE" 2>/dev/null || true
}

unload_mod() {
    local mod="$1"
    if lsmod | grep -q "^${mod}"; then
        t2_log "Unloading $mod..."
        /usr/bin/modprobe -r "$mod" 2>/dev/null || true
        lsmod | grep "^${mod}" >/dev/null && t2_log "ERROR: $mod still loaded" || t2_log "OK: $mod unloaded"
    else
        t2_log "No unload needed for $mod"
    fi
}

stop_service() {
    local svc="$1"
    t2_log "Stopping $svc..."
    
    # Check if service exists
    if ! systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"; then
        t2_log "SKIP: $svc not installed"
        return 0
    fi
    
    systemctl stop "$svc" --no-block 2>/dev/null || true
    for i in $(seq 1 20); do
        if ! systemctl is-active "$svc" >/dev/null 2>&1; then
            t2_log "OK: $svc stopped after $i/20 attempts"
            return 0
        fi
        sleep 0.5
    done
    t2_log "ERROR: $svc stop timed out after 10s"
    return 1
}

t2_log "Starting suspend sequence..."
lsmod_log

# Stop user services
stop_service tiny-dfr
stop_service t2fanrd

# Stop audio
/usr/local/bin/t2-stop-audio.sh

# Turn off keyboard backlight
t2_log "Turning off keyboard backlight..."
/usr/bin/brightnessctl -sd :white:kbd_backlight set 0 -q 2>/dev/null || true
t2_log "OK: keyboard backlight off"

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
    /usr/local/bin/drm-display-off.sh
fi

# Unload Apple GMUX
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    unload_mod apple_gmux
fi

# Unload Apple BCE
if [ "$APPLE_BCE_RELOAD" = true ]; then
    unload_mod apple_bce
fi

t2_log "Suspend complete, ready to sleep"
lsmod_log
SUSPEND_EOF
sudo chmod +x /usr/local/bin/t2-suspend.sh
echo -e "${GREEN}Done${NC}"

# Create 't2-resume.sh' script
echo -e "\n${YELLOW}⚙${NC} Creating 't2-resume.sh' script..."
sudo tee /usr/local/bin/t2-resume.sh > /dev/null << 'RESUME_EOF'
#!/bin/sh

APPLE_BCE_RELOAD=true # Unloads and reloads apple_bce module
APPLE_GMUX_RELOAD=true # Unloads and reloads apple_gmux module
SENSORS_RELOAD=true # Unloads and reloads sensor driver modules
TOUCHBAR_RELOAD=true # Unloads and reloads touchbar driver modules
WIFI_RELOAD=true # Unloads and reloads WiFi driver modules

LOG_FILE="/var/log/t2-suspend-fix.log"

t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][resume] $*" >> /var/log/t2-suspend-fix.log 2>/dev/null || true
}
lsmod_log() {
    lsmod | grep -E 'apple|bcm|brcm|industrialio|kfifo|sensor|sparse' >> "$LOG_FILE" 2>/dev/null || true
}

load_mod() {
    local mod="$1"
    if lsmod | grep -q "^${mod}"; then
        t2_log "No load needed for $mod"
    else
        t2_log "Loading $mod..."
        /usr/bin/modprobe "$mod" 2>/dev/null || true
        lsmod | grep "^${mod}" >/dev/null && t2_log "OK: $mod loaded" || t2_log "ERROR: $mod not loaded"
    fi
}

start_service() {
    local svc="$1"
    t2_log "Starting $svc..."
    
    # Check if service exists
    if ! systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"; then
        t2_log "SKIP: $svc not installed"
        return 0
    fi
    
    systemctl start "$svc" --no-block 2>/dev/null || true
    for i in $(seq 1 20); do
        if systemctl is-active "$svc" >/dev/null 2>&1; then
            t2_log "OK: $svc started after $i/20 attempts"
            return 0
        fi
        sleep 0.5
    done
    t2_log "ERROR: $svc start timed out after 10s"
    return 1
}

t2_log "Starting resume..."
lsmod_log

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
/usr/local/bin/t2-wait-apple-bce.sh

# Turn on keyboard backlight
/usr/local/bin/fix-kbd-backlight.sh

# Restart audio
/usr/local/bin/t2-start-audio.sh

# Start user services
start_service t2fanrd
start_service tiny-dfr

# Fix DRM display
if [ "$APPLE_GMUX_RELOAD" = true ]; then
    /usr/local/bin/drm-display-off.sh
    /usr/local/bin/drm-display-on.sh
    /usr/local/bin/fix-gmux-backlight.sh
fi 

t2_log "Resume complete"
lsmod_log
RESUME_EOF
sudo chmod +x /usr/local/bin/t2-resume.sh
echo -e "${GREEN}Done${NC}"

# Create 't2-suspend' service
echo -e "\n${YELLOW}⚙${NC} Creating 't2-suspend' service..."
sudo tee /etc/systemd/system/t2-suspend.service > /dev/null << 'EOF'
[Unit]
Description=Suspend script for T2 MacBook
Before=sleep.target
StopWhenUnneeded=yes

[Service]
User=root
Type=oneshot
ExecStart=/usr/local/bin/t2-suspend.sh

[Install]
WantedBy=sleep.target
EOF
echo -e "${GREEN}Done${NC}"

# Create 't2-resume' service
echo -e "\n${YELLOW}⚙${NC} Creating 't2-resume' service..."
sudo tee /etc/systemd/system/t2-resume.service > /dev/null << 'EOF'
[Unit]
Description=Resume script for T2 MacBook
After=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target

[Service]
User=root
Type=oneshot
ExecStart=/usr/local/bin/t2-resume.sh

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target suspend-then-hibernate.target
EOF
echo -e "${GREEN}Done${NC}"

# Activate services
echo -e "\n${YELLOW}⚙${NC} Activating services..."
sudo systemctl daemon-reload
sudo systemctl enable t2-suspend.service
sudo systemctl enable t2-resume.service
sudo systemctl enable fix-kbd-backlight.service 
sudo systemctl enable fix-gmux-display.service
echo -e "${GREEN}Done${NC}"

# Kernel parameters info
echo -e "\n${YELLOW}NOTE${NC}: See README.md for more information on modifying kernel parameters."

# Complete
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
