#!/bin/sh
# T2 Suspend Fix - Wait for kernel module in lsmod
# Usage: t2-wait-lsmod.sh <module_name> [timeout_seconds]

# Source common library
if [ -f /usr/local/lib/t2-suspend-fix/common.sh ]; then
    . /usr/local/lib/t2-suspend-fix/common.sh
else
    exit 1
fi

MODULE="$1"
TIMEOUT="${2:-10}"
LABEL="wait-lsmod"

if [ -z "$MODULE" ]; then
    t2_log "$LABEL" "ERROR: No module name provided"
    exit 1
fi

# Calculate iterations (0.5s sleep per iteration)
ITERATIONS=$((TIMEOUT * 2))

for i in $(seq 1 "$ITERATIONS"); do
    if lsmod | grep -q "^${MODULE}"; then
        t2_log "$LABEL" "OK: $MODULE found in lsmod (attempt $i/$ITERATIONS)"
        exit 0
    fi
    sleep 0.5
done

t2_log "$LABEL" "ERROR: $MODULE not found in lsmod after ${TIMEOUT}s"
exit 1
