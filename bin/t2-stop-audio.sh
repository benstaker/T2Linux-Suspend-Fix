#!/bin/sh
# T2 Suspend Fix - Stop Audio

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
    exit 1
fi

# Check if PipeWire is installed (check for binary, since we run as root from system service)
if ! command -v pipewire >/dev/null 2>&1; then
    t2_log "stop-audio" "SKIP: PipeWire not found (not installed)"
    exit 0
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "stop-audio" "SKIP: no user session found"
    exit 0
fi

if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "stop-audio" "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi

username=$(id -nu "$uid" 2>/dev/null) || exit 0

# Check if PipeWire is actually running before trying to stop
if ! XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- systemctl --user is-active pipewire.service >/dev/null 2>&1; then
    t2_log "stop-audio" "SKIP: PipeWire already stopped for user $username"
    exit 0
fi

t2_log "stop-audio" "Stopping PipeWire for user $username (uid=$uid)..."

XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user stop pipewire.socket pipewire-pulse.socket \
        pipewire.service pipewire-pulse.service wireplumber.service 2>/dev/null

t2_log "stop-audio" "OK: PipeWire stopped for user $username"
exit 0
