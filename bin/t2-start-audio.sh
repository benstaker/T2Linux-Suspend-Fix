#!/bin/sh
# T2 Suspend Fix - Start Audio
# Starts PipeWire sockets after resume

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
    exit 1
fi

if ! command -v pipewire >/dev/null 2>&1; then
    t2_log "start-audio" "SKIP: PipeWire not found (not installed)"
    exit 0
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "start-audio" "SKIP: no user session found"
    exit 0
fi

if [ ! -S "/run/user/$uid/bus" ]; then
    t2_log "start-audio" "SKIP: no D-Bus session found for uid $uid"
    exit 0
fi

username=$(id -nu "$uid" 2>/dev/null) || exit 0

# Check if PipeWire is already running before trying to start
if XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- systemctl --user is-active pipewire.service >/dev/null 2>&1; then
    t2_log "start-audio" "SKIP: PipeWire already running for user $username"
    exit 0
fi

t2_log "start-audio" "Starting PipeWire for user $username (uid=$uid)..."

XDG_RUNTIME_DIR="/run/user/$uid" \
DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
    runuser -u "$username" -- \
    systemctl --user start pipewire.socket pipewire-pulse.socket 2>/dev/null

t2_log "start-audio" "OK: PipeWire started for user $username"
exit 0
