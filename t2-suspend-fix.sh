#!/bin/bash

# T2 MacBook Suspend Fix Installer
# Use at your own risk!
# André Eikmeyer, Reken, Germany - 2026-02-05

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
VERSION="1.5.0"

BACKUP_DIR="/etc/t2-suspend-fix"
THERMALD_STATE_FILE="${BACKUP_DIR}/thermald_enabled"
OVERRIDE_BACKUP="${BACKUP_DIR}/override.conf.bak"
WAKEUP_BACKUP="${BACKUP_DIR}/wakeup_devices.bak"
LOG_FILE="/var/log/t2-suspend-fix.log"

t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" | tee -a "$LOG_FILE" 2>/dev/null || true
}

ensure_libnotify() {
    if command -v notify-send >/dev/null 2>&1; then
        echo -e "${GREEN}libnotify already installed (notify-send found)${NC}"
        return 0
    fi
    echo -e "${YELLOW}Installing libnotify (notify-send not found)...${NC}"
    if command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y libnotify
    elif command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update
        sudo apt-get install -y libnotify-bin
    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm libnotify
    else
        echo -e "${YELLOW}Warning: No supported package manager found. Please install libnotify manually.${NC}"
        return 1
    fi
}

capture_acpi_wakeup_state() {
    sudo mkdir -p "$BACKUP_DIR"
    sudo sh -c "cat /proc/acpi/wakeup > '$WAKEUP_BACKUP'"
}

enable_all_wakeup_devices() {
    while read -r dev _ status _; do
        [ "$dev" = "Device" ] && continue
        if [ "$status" = "*disabled" ]; then
            sudo sh -c "echo $dev > /proc/acpi/wakeup"
        fi
    done < /proc/acpi/wakeup
}

restore_acpi_wakeup_state() {
    [ -f "$WAKEUP_BACKUP" ] || return 0
    while read -r dev _ desired_status _; do
        [ "$dev" = "Device" ] && continue
        current_status=$(awk -v d="$dev" '$1==d {print $3}' /proc/acpi/wakeup)
        [ -z "$current_status" ] && continue
        if [ "$current_status" != "$desired_status" ]; then
            sudo sh -c "echo $dev > /proc/acpi/wakeup"
        fi
    done < "$WAKEUP_BACKUP"
}

echo -e "${GREEN}=== T2 MacBook Suspend Fix Installer v${VERSION} ===${NC}\n"

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
    echo -e "${RED}Error: Do not run this script as root. It will use sudo when needed.${NC}"
    exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="$ID"
    DISTRO_ID_LIKE="$ID_LIKE"
else
    echo -e "${RED}Error: Cannot detect distribution.${NC}"
    exit 1
fi

MODE="install"
echo -e "${YELLOW}Select action:${NC}"
echo "1) Install"
echo "2) Uninstall"
read -p "Choose [1-2]: " -n 1 -r
echo
if [[ $REPLY =~ ^[2]$ ]]; then
    MODE="uninstall"
elif [[ $REPLY =~ ^[1]$ ]]; then
    MODE="install"
else
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

if [ "$MODE" = "uninstall" ]; then
    echo -e "${YELLOW}⚙${NC} Uninstalling and restoring backups..."

    # Disable and remove (previous) fixes
    echo "  - Disabling services..."
    sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
    sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
    sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
    sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
    sudo systemctl disable enable-wakeup-devices.service 2>/dev/null || true
    sudo systemctl disable suspend-amdgpu-unbind.service 2>/dev/null || true
    sudo systemctl disable resume-amdgpu-bind.service 2>/dev/null || true
    echo "  - Services disabled."

    echo "  - Removing unit files and scripts..."
    sudo rm -f /etc/systemd/system/suspend-fix-t2.service
    sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
    sudo rm -f /etc/systemd/system/resume-wifi-reload.service
    sudo rm -f /etc/systemd/system/fix-kbd-backlight.service
    sudo rm -f /etc/systemd/system/enable-wakeup-devices.service
    sudo rm -f /etc/systemd/system/suspend-amdgpu-unbind.service
    sudo rm -f /etc/systemd/system/resume-amdgpu-bind.service
    sudo rm -f /usr/local/bin/t2-wait-apple-bce.sh
    sudo rm -f /usr/local/bin/t2-wait-brcmfmac.sh
    sudo rm -f /usr/local/bin/fix-kbd-backlight.sh
    sudo rm -f /usr/local/bin/enable-wakeup-devices.sh
    sudo rm -f /usr/local/bin/t2-stop-audio.sh
    sudo rm -f /usr/local/bin/t2-start-audio.sh
    sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
    sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
    echo "  - Unit files and scripts removed."

    # Restore override.conf if backed up
    if [ -f "$OVERRIDE_BACKUP" ]; then
        echo "  - Restoring override.conf..."
        sudo mkdir -p /etc/systemd/system/systemd-suspend.service.d
        sudo cp "$OVERRIDE_BACKUP" /etc/systemd/system/systemd-suspend.service.d/override.conf
        echo "  - override.conf restored."
    else
        echo "  - No override.conf backup found. Skipping restore."
    fi

    # Restore thermald if it was enabled
    if [ -f "$THERMALD_STATE_FILE" ]; then
        if grep -q "^enabled=1" "$THERMALD_STATE_FILE"; then
            echo "  - Re-enabling thermald..."
            sudo systemctl enable --now thermald || true
            echo "  - thermald re-enabled."
        else
            echo "  - thermald was not enabled before. Skipping."
        fi
    else
        echo "  - No thermald state file found. Skipping."
    fi

    # Restore ACPI wake sources
    if [ -f "$WAKEUP_BACKUP" ]; then
        echo "  - Restoring ACPI wake sources..."
        restore_acpi_wakeup_state
        echo "  - ACPI wake sources restored."
    else
        echo "  - No ACPI wake backup found. Skipping."
    fi

    # Update GRUB if possible after restore
    if [ "$GRUB_RESTORED" = true ]; then
        echo "  - Updating GRUB..."
        if command -v update-grub &> /dev/null; then
            sudo update-grub
        elif command -v grub-mkconfig &> /dev/null; then
            if [ -f /boot/grub/grub.cfg ]; then
                sudo grub-mkconfig -o /boot/grub/grub.cfg
            fi
        fi
        echo "  - GRUB update complete."
    fi

    echo "  - Reloading systemd..."
    sudo systemctl daemon-reload

    echo -e "${GREEN}Uninstall complete.${NC}"

    exit 0
fi

# Confirm with user
read -p "Continue with installation? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Ensure libnotify is available for desktop notifications
ensure_libnotify || true

# Remove prior systemd fixes
echo -e "\n${YELLOW}⚙${NC} Removing prior systemd fixes (if any)..."
echo "  - Disabling old services..."
sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
sudo systemctl disable enable-wakeup-devices.service 2>/dev/null || true
echo "  - Old services disabled."

echo "  - Removing old unit files..."
sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
sudo rm -f /etc/systemd/system/resume-wifi-reload.service
sudo rm -f /etc/systemd/system/fix-kbd-backlight.service
sudo rm -f /etc/systemd/system/enable-wakeup-devices.service
sudo rm -f /etc/systemd/system/suspend-fix-t2.service
sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
echo "  - Old unit files removed."

# Enable all wakeup devices (backup current state first)
echo -e "\n${YELLOW}⚙${NC} Enabling all wakeup devices..."
capture_acpi_wakeup_state
enable_all_wakeup_devices
sudo systemctl daemon-reload
echo -e "${GREEN}Done${NC}"

# Create service to enable wakeup devices at boot
echo -e "\n${YELLOW}⚙${NC} Creating wakeup devices service..."
sudo tee /etc/systemd/system/enable-wakeup-devices.service > /dev/null << 'EOF'
[Unit]
Description=Enable all wakeup devices for suspend
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/enable-wakeup-devices.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /usr/local/bin/enable-wakeup-devices.sh > /dev/null << 'EOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][wakeup] $*" >> "$LOG_FILE" 2>/dev/null || true
}
t2_log "Starting enable wakeup devices..."
enabled=0
while read -r dev _ status _; do
    [ "$dev" = "Device" ] && continue
    if [ "$status" = "*disabled" ]; then
        echo "$dev" > /proc/acpi/wakeup
        t2_log "OK: enabled $dev wakeup"
        enabled=$((enabled + 1))
    fi
done < /proc/acpi/wakeup
t2_log "Done: enabled $enabled wakeup devices"
EOF
sudo chmod +x /usr/local/bin/enable-wakeup-devices.sh
sudo systemctl enable enable-wakeup-devices.service
echo -e "${GREEN}Done${NC}"

# Create systemd service that calls a script to reload the KBD backlight on boot
echo -e "\n${YELLOW}⚙${NC} Creating KBD reload service..."
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

# Create script that reloads the keyboard backlight when systemd calls it
echo -e "\n${YELLOW}⚙${NC} Creating keyboard backlight script..."
sudo tee /usr/local/bin/fix-kbd-backlight.sh > /dev/null << 'EOF'
#!/bin/sh
# Keyboard backlight fix for apple_bce after boot/resume
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}
t2_log "kbd-bl" "Starting keyboard backlight fix..."

find_kbd_path() {
    ls -1 /sys/class/leds/*kbd_backlight*/brightness 2>/dev/null | head -n1
}

set_kbd_brightness() {
    # Use brightnessctl with 1%
    if command -v brightnessctl >/dev/null 2>&1; then
        brightnessctl -d :white:kbd_backlight set 1% -q 2>&1
        CURRENT=$(brightnessctl -d :white:kbd_backlight get 2>/dev/null)
        if [ -n "$CURRENT" ] && [ "$CURRENT" -gt 0 ]; then
            t2_log "kbd-bl" "OK: brightness set to $CURRENT"
            return 0
        fi
        t2_log "kbd-bl" "ERROR: brightness still 0"
    fi
    return 1
}

# Try immediately first
if set_kbd_brightness; then
    t2_log "kbd-bl" "OK: keyboard backlight set immediately via sysfs"
    exit 0
fi

# Poll
for i in $(seq 1 15); do
    if set_kbd_brightness; then
        t2_log "kbd-bl" "OK: keyboard backlight set after $i/15 attempts"
        exit 0
    fi
    sleep 1
done

t2_log "kbd-bl" "ERROR: could not set keyboard backlight after 15 attempts"
t2_log "kbd-bl" "DEBUG: checking leds directory..."
ls -la /sys/class/leds/ 2>/dev/null | grep -i kbd
t2_log "kbd-bl" "DEBUG: brightnessctl available: $(command -v brightnessctl || echo 'no')"
t2_log "kbd-bl" "DEBUG: current brightness: $(cat /sys/class/leds/:white:kbd_backlight/brightness 2>/dev/null || echo 'read failed')"
exit 0
EOF
sudo chmod +x /usr/local/bin/fix-kbd-backlight.sh
echo -e "${GREEN}Done${NC}"

# Create helper wait scripts
echo -e "\n${YELLOW}⚙${NC} Creating helper wait scripts..."
sudo tee /usr/local/bin/t2-wait-apple-bce.sh > /dev/null << 'EOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}
t2_log "wait-bce" "Starting wait for apple_bce PCI binding..."
for i in $(seq 1 15); do
    if ls /sys/bus/pci/drivers/apple-bce/*:* >/dev/null 2>&1; then
        t2_log "wait-bce" "OK: apple_bce PCI binding found (attempt $i/15)"
        exit 0
    fi
    sleep 1
done
t2_log "wait-bce" "ERROR: apple_bce PCI binding not found after 15 attempts"
exit 1
EOF
sudo chmod +x /usr/local/bin/t2-wait-apple-bce.sh
echo -e "${GREEN}Done${NC}"

# Create audio stop/start helper scripts
echo -e "\n${YELLOW}⚙${NC} Creating audio stop/start helper scripts..."
sudo tee /usr/local/bin/t2-stop-audio.sh > /dev/null << 'AUDIOEOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}
t2_log "audio" "Stopping PipeWire audio session..."
uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "audio" "SKIP: no user session found"
    exit 0
fi
if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "audio" "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi
username=$(id -nu "$uid" 2>/dev/null) || exit 0
XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user stop pipewire.socket pipewire-pulse.socket \
        pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null
t2_log "audio" "OK: PipeWire stopped for user $username"
exit 0
AUDIOEOF
sudo chmod +x /usr/local/bin/t2-stop-audio.sh

sudo tee /usr/local/bin/t2-start-audio.sh > /dev/null << 'AUDIOEOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    local label="$1"
    shift
    local msg="$*"
    local timestamp
    timestamp=$(date "+%Y_%m_%d-%H:%M:%S")
    echo "[${timestamp}][${label}] ${msg}" >> "$LOG_FILE" 2>/dev/null || true
}
t2_log "audio" "Starting PipeWire audio session..."
uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "audio" "SKIP: no user session found"
    exit 0
fi
if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "audio" "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi
username=$(id -nu "$uid" 2>/dev/null) || exit 0
t2_log "audio" "Starting PipeWire for user $username (uid=$uid)..."
XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user start pipewire.socket pipewire-pulse.socket 2>/dev/null
t2_log "audio" "OK: PipeWire sockets started"

# Restore T2 DSP default devices if wpctl is available
if command -v wpctl >/dev/null 2>&1; then
    t2_log "audio" "Checking for T2 DSP devices (polling for 5s)..."
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
        t2_log "audio" "OK: T2 speakers set to $T2_SPEAKERS"
    else
        t2_log "audio" "NOTE: T2 speakers not found after 5s"
    fi
    if [ -n "$T2_MIC" ]; then
        XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" wpctl set-default "$T2_MIC" -s 2>/dev/null
        t2_log "audio" "OK: T2 mic set to $T2_MIC"
    else
        t2_log "audio" "NOTE: T2 mic not found after 5s"
    fi
fi
t2_log "audio" "OK: audio services started"
exit 0
AUDIOEOF
sudo chmod +x /usr/local/bin/t2-start-audio.sh
echo -e "${GREEN}Done${NC}"

# Create log file with proper permissions
echo -e "\n${YELLOW}⚙${NC} Creating log file..."
sudo touch /var/log/t2-suspend-fix.log
sudo chmod 666 /var/log/t2-suspend-fix.log
echo -e "${GREEN}Done${NC}"

# Create suspend script
echo -e "\n${YELLOW}⚙${NC} Creating suspend script..."
sudo tee /usr/local/bin/t2-suspend.sh > /dev/null << 'SUSPEND_EOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][suspend] $*" >> "$LOG_FILE" 2>/dev/null || true
}

t2_log "Starting suspend sequence..."

# Stop user services
t2_log "Stopping user services (tiny-dfr, t2fanrd)..."
/usr/bin/systemctl stop tiny-dfr 2>/dev/null || true
/usr/bin/systemctl stop t2fanrd 2>/dev/null || true

# Set pm_async for better suspend stability
t2_log "Setting pm_async=0..."
echo 0 > /sys/power/pm_async
t2_log "OK: pm_async=0"

# Backlight off
t2_log "Turning off keyboard backlight..."
/usr/bin/brightnessctl -sd :white:kbd_backlight set 0 -q 2>/dev/null || true
t2_log "OK: keyboard backlight off"

# Stop audio
t2_log "Stopping audio services..."
/usr/local/bin/t2-stop-audio.sh

# Block WiFi and Bluetooth
t2_log "Blocking WiFi and Bluetooth..."
/usr/bin/rfkill block wifi
/usr/bin/rfkill block bluetooth
t2_log "OK: WiFi/BT blocked"

# Deactivate WiFi
t2_log "Disabling WiFi radio..."
/usr/bin/nmcli radio wifi off
t2_log "OK: WiFi radio disabled"

# Unload WiFi driver
t2_log "Unloading brcmfmac driver..."
/usr/sbin/modprobe -r brcmfmac_wcc 2>/dev/null || true
/usr/sbin/modprobe -r brcmfmac 2>/dev/null || true
lsmod | grep "^brcmfmac" >/dev/null && t2_log "ERROR: brcmfmac still loaded" || t2_log "OK: brcmfmac unloaded"

# Unload Bluetooth driver
t2_log "Unloading hci_bcm4377 driver..."
/usr/sbin/modprobe -r hci_bcm4377 2>/dev/null || true
lsmod | grep "^hci_bcm4377" >/dev/null && t2_log "ERROR: hci_bcm4377 still loaded" || t2_log "OK: hci_bcm4377 unloaded"

# Unload Touch Bar drivers (sparse_keymap depends on hid_appletb_kbd)
t2_log "Unloading sparse_keymap..."
/usr/sbin/modprobe -r sparse_keymap 2>/dev/null || true
lsmod | grep "^sparse_keymap" >/dev/null && t2_log "ERROR: sparse_keymap still loaded" || t2_log "OK: sparse_keymap unloaded"

t2_log "Unloading hid_appletb_kbd..."
/usr/sbin/modprobe -r hid_appletb_kbd 2>/dev/null || true
lsmod | grep "^hid_appletb_kbd" >/dev/null && t2_log "ERROR: hid_appletb_kbd still loaded" || t2_log "OK: hid_appletb_kbd unloaded"

t2_log "Unloading hid_appletb_bl..."
/usr/sbin/modprobe -r hid_appletb_bl 2>/dev/null || true
lsmod | grep "^hid_appletb_bl" >/dev/null && t2_log "ERROR: hid_appletb_bl still loaded" || t2_log "OK: hid_appletb_bl unloaded"

# Apple BCE removal
t2_log "Removing apple_bce module..."
/usr/sbin/rmmod -f apple_bce 2>/dev/null || true
lsmod | grep "^apple_bce" >/dev/null && t2_log "ERROR: apple_bce still loaded" || t2_log "OK: apple_bce removed"

t2_log "Suspend complete, ready to sleep"
SUSPEND_EOF
sudo chmod +x /usr/local/bin/t2-suspend.sh
echo -e "${GREEN}Done${NC}"

# Create resume script
echo -e "\n${YELLOW}⚙${NC} Creating resume script..."
sudo tee /usr/local/bin/t2-resume.sh > /dev/null << 'RESUME_EOF'
#!/bin/sh
LOG_FILE="/var/log/t2-suspend-fix.log"
t2_log() {
    echo "[$(date +%Y_%m_%d-%H:%M:%S)][resume] $*" >> "$LOG_FILE" 2>/dev/null || true
}

t2_log "Starting resume..."

# Load apple_bce first (foundation for everything)
t2_log "Loading apple_bce module..."
/usr/sbin/modprobe apple_bce
lsmod | grep "^apple_bce" >/dev/null && t2_log "OK: apple_bce module loaded" || t2_log "ERROR: failed to load apple_bce"

# Wait for BCE PCI binding
t2_log "Waiting for apple_bce PCI binding..."
/usr/local/bin/t2-wait-apple-bce.sh

# Rescan PCI bus (needs to happen before upower restart so it sees devices)
t2_log "Running PCI bus rescan..."
echo 1 > /sys/bus/pci/rescan
t2_log "OK: PCI rescan complete"

# Restore keyboard backlight (at end)
t2_log "Restoring keyboard backlight..."
/usr/local/bin/fix-kbd-backlight.sh

# Restart UPower (now sees all re-appeared devices)
t2_log "Restarting UPower service..."
/usr/bin/systemctl restart upower
t2_log "OK: UPower restarted"

# Load WiFi driver
t2_log "Loading brcmfmac driver..."
/usr/sbin/modprobe brcmfmac 2>/dev/null || true
/usr/sbin/modprobe brcmfmac_wcc 2>/dev/null || true
lsmod | grep "^brcmfmac" >/dev/null && t2_log "OK: brcmfmac loaded" || t2_log "ERROR: brcmfmac not loaded"

# Load Bluetooth driver
t2_log "Loading hci_bcm4377 driver..."
/usr/sbin/modprobe hci_bcm4377 2>/dev/null || true
lsmod | grep "^hci_bcm4377" >/dev/null && t2_log "OK: hci_bcm4377 loaded" || t2_log "ERROR: hci_bcm4377 not loaded"

# Unblock WiFi and Bluetooth (after drivers loaded)
t2_log "Unblocking WiFi and Bluetooth..."
/usr/bin/rfkill unblock wifi
/usr/bin/rfkill unblock bluetooth
t2_log "OK: WiFi/BT unblocked"

# Enable WiFi radio immediately after unblock (needs to be before audio)
t2_log "Enabling WiFi radio..."
/usr/bin/nmcli radio wifi on
t2_log "OK: WiFi radio enabled"

# Restart audio (needs apple_bce)
t2_log "Starting audio services..."
/usr/local/bin/t2-start-audio.sh

# Smart WiFi check - wait up to 5s for driver to bind
t2_log "Checking WiFi driver binding..."
for i in $(seq 1 10); do
    if ls /sys/bus/pci/drivers/brcmfmac/*:* >/dev/null 2>&1; then
        t2_log "OK: WiFi driver bound (attempt $i/10)"
        break
    fi
    sleep 0.5
done

# Start user services
/usr/bin/systemctl start t2fanrd 2>/dev/null || true
/usr/bin/systemctl start tiny-dfr 2>/dev/null || true

t2_log "Resume complete"
RESUME_EOF
sudo chmod +x /usr/local/bin/t2-resume.sh
echo -e "${GREEN}Done${NC}"

# Create WiFi unload service
echo -e "\n${YELLOW}⚙${NC} Creating WiFi unload service..."
sudo tee /etc/systemd/system/suspend-wifi-unload.service > /dev/null << 'EOF'
[Unit]
Description=WiFi Unload Before Suspend
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

# Create service that reloads WiFi after resume
echo -e "\n${YELLOW}⚙${NC} Creating WiFi reload service..."
sudo tee /etc/systemd/system/resume-wifi-reload.service > /dev/null << 'EOF'
[Unit]
Description=WiFi and BCE Reload After Resume
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
sudo systemctl enable suspend-wifi-unload.service
sudo systemctl enable resume-wifi-reload.service
sudo systemctl enable fix-kbd-backlight.service 
echo -e "${GREEN}Done${NC}"

# Disable thermald if present
echo -e "\n${YELLOW}⚙${NC} Checking for thermald..."
if systemctl is-enabled thermald &>/dev/null; then
    echo "  - Disabling thermald..."
    sudo mkdir -p "$BACKUP_DIR"
    echo "enabled=1" | sudo tee "$THERMALD_STATE_FILE" > /dev/null
    sudo systemctl disable --now thermald
    echo -e "${GREEN}Done${NC}"
else
    sudo mkdir -p "$BACKUP_DIR"
    echo "enabled=0" | sudo tee "$THERMALD_STATE_FILE" > /dev/null
    echo -e "${GREEN}thermald not found or not enabled${NC}"
fi

# Configure deep suspend mode
echo -e "\n${YELLOW}NOTE${NC}: For deep suspend to work properly, add the following kernel parameters to your bootloader:"
echo ""
echo "  For rEFInd (/boot/refind_linux.conf or /boot/efi/EFI/refind/refind.conf):"
echo "    add: mem_sleep_default=deep pcie_aspm=off"
echo ""
echo "  The above kernel parameters are required for suspend/resume to work properly on T2 Macs."

# Remove override.conf
echo -e "\n${YELLOW}⚙${NC} Checking for override.conf..."
if [ -f /etc/systemd/system/systemd-suspend.service.d/override.conf ]; then
    echo "  - Removing systemd-suspend override.conf..."
    # Backup override.conf once
    if [ ! -f "$OVERRIDE_BACKUP" ]; then
        sudo mkdir -p "$BACKUP_DIR"
        sudo cp /etc/systemd/system/systemd-suspend.service.d/override.conf "$OVERRIDE_BACKUP"
        echo "  - Backed up override.conf to $OVERRIDE_BACKUP"
    fi
    sudo rm /etc/systemd/system/systemd-suspend.service.d/override.conf
    sudo systemctl daemon-reload
    echo -e "${GREEN}Done${NC}"
else
    echo -e "${GREEN}No override.conf found${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
echo ""
echo -e "${YELLOW}IMPORTANT NOTES:${NC}"
echo "Reminder: Suspend/Resume takes longer than on MacOS. This is normal behavior and not a malfunction"
echo ""
read -p "Reboot now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    sudo reboot
fi
