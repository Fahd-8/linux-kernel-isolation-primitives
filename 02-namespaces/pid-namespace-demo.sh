#!/usr/bin/env bash
#
# pid-namespace-demo.sh
#
# Demonstrates Linux PID namespace isolation.
#
# What this proves:
#   A process inside a new PID namespace believes it is PID 1 (like init/systemd),
#   and can only see itself in its process list - even though, on the real host,
#   it has a completely different, unremarkable PID.
#
# Requires: root privileges (util-linux package - `unshare` command)
#
# Usage:
#   sudo ./pid-namespace-demo.sh

set -euo pipefail

echo "=== Real host view, before entering the namespace ==="
echo "Current shell PID on the real host: $$"
echo "(This process is one of many - see 'ps aux' for the full picture)"

echo
echo "=== Entering a new PID namespace ==="
echo "Launching a fresh bash shell inside an isolated PID namespace..."
echo "Inside, run:"
echo "    echo \$\$        # will print 1, not a real host PID"
echo "    ps aux        # will show only 2 processes: this shell + ps itself"
echo "Type 'exit' to leave the namespace and return to the real host."
echo

unshare --pid --fork --mount-proc bash