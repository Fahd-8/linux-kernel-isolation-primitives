#!/usr/bin/env bash
#
# memory-hard-limit-demo.sh
#
# Demonstrates the cgroups v2 memory.max hard limit, built entirely by hand
# from the raw /sys/fs/cgroup filesystem - no systemd, no Docker.
#
# What this proves:
#   A cgroup created with a plain `mkdir` under /sys/fs/cgroup/ is
#   automatically populated by the kernel with resource-control files.
#   Writing a byte value into memory.max and adding a process's PID into
#   cgroup.procs causes the kernel to hard-kill that process (OOM kill)
#   the instant it crosses the limit - no grace period, no warning.
#
# Requires: root privileges, cgroups v2 mounted at /sys/fs/cgroup
#           (check with: cat /sys/fs/cgroup/cgroup.controllers)
#
# Usage:
#   sudo ./memory-hard-limit-demo.sh
#   sudo ./memory-hard-limit-demo.sh cleanup   # remove the cgroup if left over

set -euo pipefail

CGROUP_NAME="demo-hard-limit"
CGROUP_PATH="/sys/fs/cgroup/$CGROUP_NAME"
MEMORY_LIMIT="100M"
TEST_SCRIPT="/tmp/memtest-hard.py"

cleanup() {
    echo "[*] Cleaning up..."
    rmdir "$CGROUP_PATH" 2>/dev/null || true
    rm -f "$TEST_SCRIPT"
    echo "[*] Cleanup complete."
}

if [[ "${1:-}" == "cleanup" ]]; then
    cleanup
    exit 0
fi

echo "=== Step 1: Create the cgroup (a plain mkdir under /sys/fs/cgroup) ==="
mkdir "$CGROUP_PATH"
echo "[+] Kernel auto-populated control files:"
ls "$CGROUP_PATH" | head -5
echo "    ... ($(ls "$CGROUP_PATH" | wc -l) files total)"

echo
echo "=== Step 2: Set the hard memory limit ==="
echo "$MEMORY_LIMIT" > "$CGROUP_PATH/memory.max"
echo "[+] memory.max set to: $(cat "$CGROUP_PATH/memory.max") bytes ($MEMORY_LIMIT)"

echo
echo "=== Step 3: Create a script that allocates memory forever ==="
cat > "$TEST_SCRIPT" << 'EOF'
import time
data = []
for i in range(1000):
    data.append('A' * 1024 * 1024)  # allocate 1MB per iteration
    print(f"Allocated {i+1} MB")
    time.sleep(0.1)
EOF

echo
echo "=== Step 4: Launch it and immediately assign it to the cgroup ==="
echo "[*] Watch it grow until it hits ${MEMORY_LIMIT} and gets OOM-killed by the kernel:"
echo

python3 "$TEST_SCRIPT" &
PID=$!
echo "$PID" > "$CGROUP_PATH/cgroup.procs"
wait "$PID" 2>/dev/null || true

echo
echo "=== Step 5: Confirm the kernel's own OOM accounting ==="
echo "[+] memory.events for this cgroup:"
cat "$CGROUP_PATH/memory.events"
echo
echo "    'oom_kill' above should be >= 1, proving the kernel enforced the limit."

echo
echo "=== Done. Run 'sudo ./memory-hard-limit-demo.sh cleanup' to remove the cgroup. ==="