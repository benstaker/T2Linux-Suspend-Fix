#!/bin/sh
# T2 Suspend Fix - Set Default Audio Devices
# Sets default speakers and mic (mainly needed for 16" MacBook with custom DSP)

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
else
    exit 1
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "set-default-audio" "SKIP: no user session found"
    exit 0
fi

t2_log "set-default-audio" "Looking for audio devices (polling for 5s)..."

# Poll for up to 5s for devices to appear
for i in $(seq 1 10); do
    # Try different speaker patterns (16" uses filter-chain, 13" uses Apple Audio Device)
    T2_SPEAKERS=$(XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        wpctl status 2>/dev/null | grep -F '[Audio/Sink]' | grep -E 'input.filter-chain-speakers|Apple Audio Device Speakers' | sed -n 's/.* \([0-9]\+\)\.*/\1/p' | head -n1)
    # Try different mic patterns
    T2_MIC=$(XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        wpctl status 2>/dev/null | grep -F '[Audio/Source]' | grep -E 'output.filter-chain-mic|Apple Audio Device.*Mic' | sed -n 's/.* \([0-9]\+\)\.*/\1/p' | head -n1)
    if [ -n "$T2_SPEAKERS" ] || [ -n "$T2_MIC" ]; then
        break
    fi
    sleep 0.5
done

if [ -n "$T2_SPEAKERS" ]; then
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" wpctl set-default "$T2_SPEAKERS" 2>/dev/null
    t2_log "set-default-audio" "OK: speakers set to $T2_SPEAKERS"
else
    t2_log "set-default-audio" "NOTE: speakers not found"
fi

if [ -n "$T2_MIC" ]; then
    XDG_RUNTIME_DIR="/run/user/$uid" DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" wpctl set-default "$T2_MIC" 2>/dev/null
    t2_log "set-default-audio" "OK: mic set to $T2_MIC"
else
    t2_log "set-default-audio" "NOTE: mic not found"
fi

exit 0
