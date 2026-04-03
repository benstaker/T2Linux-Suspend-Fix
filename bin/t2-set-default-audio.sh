#!/bin/sh
# T2 Suspend Fix - Set Default Audio Devices
# Sets default speakers and mic (mainly needed for 16" MacBook with custom DSP)

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/t2-common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/t2-common.sh
else
    echo "Error: t2-common.sh not found" >&2
    exit 1
fi

uid=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $2}' | head -n1)
if [ -z "$uid" ]; then
    t2_log "set-default-audio" "SKIP: no user session found"
    exit 0
fi

t2_log "set-default-audio" "Looking for audio devices (polling for 5s)..."

# Extract numeric ID from a line containing device pattern
# Works regardless of field position - just finds the first number followed by a dot
extract_id() {
    grep -oE '[0-9]+\.' | tr -d '.' | head -n1
}

# Poll for up to 5s for devices to appear
for i in $(seq 1 10); do
    WPCTL_STATUS=$(XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        wpctl status 2>/dev/null)

    # 16" MacBook: Uses filter-chain DSP (in Filters section)
    # 13" MacBook: Uses direct Apple Audio Device (in Sinks/Sources section)

    # For speakers: try filter-chain first (16"), then Apple Audio Device Speakers (13")
    T2_SPEAKERS=$(echo "$WPCTL_STATUS" | grep -i 'input.filter-chain-speakers' | extract_id)
    if [ -z "$T2_SPEAKERS" ]; then
        T2_SPEAKERS=$(echo "$WPCTL_STATUS" | grep -i 'Apple Audio Device Speakers' | extract_id)
    fi

    # For mic: prefer builtin mic (13") or filter-chain-mic (16")
    T2_MIC=$(echo "$WPCTL_STATUS" | grep -i 'Apple Audio Device.*BuiltinMic' | extract_id)
    if [ -z "$T2_MIC" ]; then
        T2_MIC=$(echo "$WPCTL_STATUS" | grep -i 'output.filter-chain-mic' | extract_id)
    fi

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
