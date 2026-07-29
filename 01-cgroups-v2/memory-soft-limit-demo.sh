#!/usr/bin/env bash
#
# memory-soft-limit-demo.sh
#
# Demonstrates the cgroups v2 memory.high soft limit / throttle mechanism,
# and how it differs from the hard memory.max limit (see
# memory-hard-limit-demo.sh in this same directory).
#
# What this proves:
#   memory.high is NOT a kill switch. When a process crosses it, the kernel
#   throttles it (scheduling penalty + aggressive page reclaim) instead of
#   killing it outright. The process can keep running - slowed down - as
#   long as it stays under the separate, higher memory.max hard ceiling.
#
#   This is the mechanism production systems use to absorb temporary memory
#   spikes (e.g. a burst of traffic, a large batch job) without an abrupt
#   OOM kill, while still guaranteeing a hard ceiling if things truly run away.
#
# Requires: root privileges, cgroups v2 mounted at /sys/fs/cgroup
#
# Usage:
#   sudo ./memory-soft-limit-demo.sh
#   sudo ./memory-soft-limit-demo.sh cleanup

set -euo pipefail

CGROUP_NAME="demo-soft-limit"
CGROUP_PATH="/sys/fs/cgroup/$CGROUP_NAME"
MEMORY_HIGH="50M"
MEMORY_MAX="150M"
TEST_SCRIPT="/tmp/memtest-soft.py"
RUN_SECONDS=8

cleanup() {
    echo "[*] Cleaning up..."
    # Kill anything left running in the cgroup before removing it
    if [[ -f "$CGROUP_PATH/cgroup.procs" ]]; then
        for pid in $(cat "$CGROUP_PATH/cgroup.procs" 2>/dev/null || true); do
            kill -9 "$pid" 2>/dev/null || true
        done
    fi
    rmdir "$CGROUP_PATH" 2>/dev/null || true
    rm -f "$TEST_SCRIPT"
    echo "[*] Cleanup complete."
}

if [[ "${1:-}" == "cleanup" ]]; then
    cleanup
    exit 0
fi

echo "=== Step 1: Create the cgroup with BOTH a soft and hard limit ==="
mkdir "$CGROUP_PATH"
echo "$MEMORY_HIGH" > "$CGROUP_PATH/memory.high"
echo "$MEMORY_MAX"  > "$CGROUP_PATH/memory.max"
echo "[+] memory.high = $(cat "$CGROUP_PATH/memory.high") bytes ($MEMORY_HIGH - throttle line)"
echo "[+] memory.max  = $(cat "$CGROUP_PATH/memory.max") bytes ($MEMORY_MAX - hard kill line)"
echo "[+] Buffer zone between the two: gives the kernel room to throttle and"
echo "    reclaim memory before ever resorting to a kill."

echo
echo "=== Step 2: Create a script that keeps allocating memory ==="
cat > "$TEST_SCRIPT" << 'EOF'
import time
data = []
for i in range(1000):
    data.append('A' * 1024 * 1024)
    print(f"Allocated {i+1} MB")
    time.sleep(0.1)
EOF

echo
echo "=== Step 3: Launch it inside the cgroup and observe throttling ==="
echo "[*] Watch allocation speed visibly slow down once it crosses ${MEMORY_HIGH}:"
echo

python3 "$TEST_SCRIPT" &
PID=$!
echo "$PID" > "$CGROUP_PATH/cgroup.procs"

sleep "$RUN_SECONDS"

echo
echo "=== Step 4: Inspect live state - still alive, throttled, not killed ==="
if kill -0 "$PID" 2>/dev/null; then
    echo "[+] Process $PID is still alive (not OOM-killed)."
else
    echo "[i] Process $PID has exited or been killed - check memory.events below."
fi

echo "[+] Current memory usage: $(cat "$CGROUP_PATH/memory.current") bytes"
echo "[+] memory.events:"
cat "$CGROUP_PATH/memory.events"
echo
echo "    'high' above counts throttle events - should be > 0."
echo "    'oom_kill' should be 0, since this stayed under memory.max (${MEMORY_MAX})."

echo
echo "=== Cleaning up the still-running test process ==="
kill -9 "$PID" 2>/dev/null || true

echo
echo "=== Done. Run 'sudo ./memory-soft-limit-demo.sh cleanup' to remove the cgroup. ==="