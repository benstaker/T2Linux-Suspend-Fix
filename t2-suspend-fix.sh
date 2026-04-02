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

echo -e "${GREEN}=== T2 MacBook Suspend Fix Installer ===${NC}\n"

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

    # Remove system services
    echo "  - Removing system services..."
    for svc in "$(dirname "$0")/services/system/"*.service; do
        [ -f "$svc" ] || continue
        svc_name=$(basename "$svc")
        sudo systemctl stop "$svc_name" 2>/dev/null || true
        sudo systemctl disable "$svc_name" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/$svc_name"
    done
    echo "  - System services removed."

    # Remove user services
    echo "  - Removing user services..."
    for svc in "$(dirname "$0")/services/user/"*.service; do
        [ -f "$svc" ] || continue
        svc_name=$(basename "$svc")
        for user in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do
            uid=$(id -u "$user" 2>/dev/null) || continue
            if [ -S "/run/user/$uid/bus" ]; then
                sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                    systemctl --user stop "$svc_name" 2>/dev/null || true
            fi
        done
        sudo systemctl disable --global "$svc_name" 2>/dev/null || true
        sudo rm -f "/etc/xdg/systemd/user/$svc_name"
    done
    echo "  - User services removed."

    # Remove legacy system services
    echo "  - Removing legacy system services..."
    sudo systemctl stop fix-gmux-backlight.service 2>/dev/null || true
    sudo systemctl disable fix-gmux-backlight.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/fix-gmux-backlight.service

    sudo systemctl stop fix-gmux-display.service 2>/dev/null || true
    sudo systemctl disable fix-gmux-display.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/fix-gmux-display.service

    sudo systemctl stop fix-kbd-backlight.service 2>/dev/null || true
    sudo systemctl disable fix-kbd-backlight.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/fix-kbd-backlight.service

    sudo systemctl stop enable-wakeup-devices.service 2>/dev/null || true
    sudo systemctl disable enable-wakeup-devices.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/enable-wakeup-devices.service

    sudo systemctl stop resume-amdgpu-bind.service 2>/dev/null || true
    sudo systemctl disable resume-amdgpu-bind.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/resume-amdgpu-bind.service

    sudo systemctl stop resume-wifi-reload.service 2>/dev/null || true
    sudo systemctl disable resume-wifi-reload.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/resume-wifi-reload.service

    sudo systemctl stop suspend-amdgpu-unbind.service 2>/dev/null || true
    sudo systemctl disable suspend-amdgpu-unbind.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/suspend-amdgpu-unbind.service

    sudo systemctl stop suspend-fix-t2.service 2>/dev/null || true
    sudo systemctl disable suspend-fix-t2.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/suspend-fix-t2.service

    sudo systemctl stop suspend-wifi-unload.service 2>/dev/null || true
    sudo systemctl disable suspend-wifi-unload.service 2>/dev/null || true
    sudo rm -f /etc/systemd/system/suspend-wifi-unload.service
    echo "  - Legacy system services removed."

    # Remove legacy user services
    echo "  - Removing legacy user services..."
    for user in $(awk -F: '$3 >= 1000 && $3 < 60000 {print $1}' /etc/passwd); do
        uid=$(id -u "$user" 2>/dev/null) || continue
        if [ -S "/run/user/$uid/bus" ]; then
            sudo -u "$user" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
                systemctl --user stop kbd-backlight-auto.service 2>/dev/null || true
        fi
    done
    sudo systemctl disable --global kbd-backlight-auto.service 2>/dev/null || true
    sudo rm -f /etc/xdg/systemd/user/kbd-backlight-auto.service
    echo "  - Legacy user services removed."

    # Scripts: remove
    echo "  - Removing scripts..."
    # Remove scripts installed from bin/ folder
    for script in "$(dirname "$0")/bin/"*.sh; do
        [ -f "$script" ] || continue
        sudo rm -f "/usr/local/bin/$(basename "$script")"
    done
    # Legacy scripts for backward compatibility
    sudo rm -f /usr/lib/systemd/system-sleep/90-t2-hibernate-test-brcmfmac.sh
    sudo rm -f /usr/lib/systemd/system-sleep/t2-resync
    sudo rm -f /usr/local/bin/drm-display-off.sh
    sudo rm -f /usr/local/bin/drm-display-on.sh
    sudo rm -f /usr/local/bin/enable-wakeup-devices.sh
    sudo rm -f /usr/local/bin/fix-gmux-backlight.sh
    sudo rm -f /usr/local/bin/fix-kbd-backlight.sh
    sudo rm -f /usr/local/bin/kbd-backlight-auto.sh
    sudo rm -f /usr/local/bin/t2-resume.sh
    sudo rm -f /usr/local/bin/t2-start-audio.sh
    sudo rm -f /usr/local/bin/t2-stop-audio.sh
    sudo rm -f /usr/local/bin/t2-suspend.sh
    sudo rm -f /usr/local/bin/t2-wait-apple-bce.sh
    sudo rm -f /usr/local/bin/t2-wait-brcmfmac.sh
    echo "  - Scripts removed."

    # Library: remove
    echo "  - Removing shared library..."
    sudo rm -rf /usr/local/lib/t2-suspend-fix/
    echo "  - Shared library removed."

    # Configuration: remove
    echo "  - Removing configuration..."
    sudo rm -rf /etc/t2-suspend-fix/
    echo "  - Configuration removed."

    # Reload systemd
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

# Create log file
echo -e "\n${YELLOW}⚙${NC} Creating log file '/var/log/t2-suspend-fix.log'..."
sudo touch /var/log/t2-suspend-fix.log
sudo chmod 666 /var/log/t2-suspend-fix.log
echo -e "${GREEN}Done${NC}"

# Copy shared library files
echo -e "\n${YELLOW}⚙${NC} Installing shared library..."
sudo mkdir -p /usr/local/lib/t2-suspend-fix
sudo cp -r "$(dirname "$0")/lib/"* /usr/local/lib/t2-suspend-fix/
sudo chmod -R 755 /usr/local/lib/t2-suspend-fix/
echo -e "${GREEN}Done${NC}"

# Copy bin scripts
echo -e "\n${YELLOW}⚙${NC} Installing scripts..."
for script in "$(dirname "$0")/bin/"*.sh; do
    [ -f "$script" ] || continue
    sudo cp "$script" /usr/local/bin/
    sudo chmod +x "/usr/local/bin/$(basename "$script")"
done
echo -e "${GREEN}Done${NC}"

# Run hardware detection
echo -e "\n${YELLOW}⚙${NC} Running hardware detection..."
if [ -f "$(dirname "$0")/bin/t2-detect-hardware.sh" ]; then
    sudo "$(dirname "$0")/bin/t2-detect-hardware.sh"
else
    echo -e "${YELLOW}Warning: Hardware detection script not found${NC}"
fi

# Source detected hardware configuration
if [ -f /etc/t2-suspend-fix/hardware.conf ]; then
    # shellcheck source=/dev/null
    . /etc/t2-suspend-fix/hardware.conf
    echo -e "${GREEN}Hardware config loaded: HAS_GMUX=${HAS_GMUX:-unknown}${NC}"
else
    echo -e "${YELLOW}Warning: Hardware config not found, using defaults${NC}"
    HAS_GMUX="true"
fi

# Install system service files
echo -e "\n${YELLOW}⚙${NC} Installing system services..."

sudo cp "$(dirname "$0")/services/system/t2-fix-kbd-backlight.service" /etc/systemd/system/
echo "  - t2-fix-kbd-backlight.service installed"

sudo cp "$(dirname "$0")/services/system/t2-suspend.service" /etc/systemd/system/
echo "  - t2-suspend.service installed"

sudo cp "$(dirname "$0")/services/system/t2-resume.service" /etc/systemd/system/
echo "  - t2-resume.service installed"

if [ "$HAS_GMUX" = "true" ]; then
    sudo cp "$(dirname "$0")/services/system/t2-fix-gmux-display.service" /etc/systemd/system/
    echo "  - t2-fix-gmux-display.service installed"
else
    echo "  - t2-fix-gmux-display.service skipped (no GMUX)"
fi

echo -e "${GREEN}Done${NC}"

# User services
echo -e "\n${YELLOW}⚙${NC} Installing user services..."

sudo mkdir -p /etc/xdg/systemd/user
sudo cp "$(dirname "$0")/services/user/t2-kbd-backlight-auto.service" /etc/xdg/systemd/user/
echo "  - t2-kbd-backlight-auto.service installed (user)"

echo -e "${GREEN}Done${NC}"

# Enable services
echo -e "\n${YELLOW}⚙${NC} Enabling services..."
sudo systemctl daemon-reload

# Enable system services
sudo systemctl enable t2-suspend.service
sudo systemctl enable t2-resume.service
sudo systemctl enable t2-fix-kbd-backlight.service 
if [ "$HAS_GMUX" = "true" ]; then
    sudo systemctl enable t2-fix-gmux-display.service
fi

# Enable user services
sudo systemctl enable --global t2-kbd-backlight-auto.service

echo -e "${GREEN}Done${NC}"

# Kernel parameters info
echo -e "\n${YELLOW}NOTE${NC}: See README.md for more information on modifying kernel parameters."

# Complete
echo -e "\n${GREEN}=== Installation Complete ===${NC}\n"
