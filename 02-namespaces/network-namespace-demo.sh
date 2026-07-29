#!/usr/bin/env bash
#
# network-namespace-demo.sh
#
# Demonstrates Linux network namespace isolation from scratch, without Docker.
#
# What this proves:
#   1. A freshly created network namespace has NO network connectivity at all
#      (not even to the host it's running on).
#   2. A veth (virtual ethernet) pair can bridge the isolated namespace back
#      to the host, exactly like Docker does internally for every container.
#
# Requires: root privileges (iproute2 package - `ip` command)
#
# Usage:
#   sudo ./network-namespace-demo.sh
#   sudo ./network-namespace-demo.sh cleanup   # tear down everything created

set -euo pipefail

NS_NAME="netns-demo"
VETH_HOST="veth-host"
VETH_NS="veth-demo"
HOST_IP="10.200.1.1/24"
NS_IP="10.200.1.2/24"

cleanup() {
    echo "[*] Cleaning up..."
    ip netns delete "$NS_NAME" 2>/dev/null || true
    ip link delete "$VETH_HOST" 2>/dev/null || true
    echo "[*] Cleanup complete."
}

if [[ "${1:-}" == "cleanup" ]]; then
    cleanup
    exit 0
fi

echo "=== Step 1: Create an isolated network namespace ==="
ip netns add "$NS_NAME"
ip netns list

echo
echo "=== Step 2: Prove total network isolation ==="
echo "[*] Attempting to reach 8.8.8.8 from inside the namespace (expected: FAIL)"
if ip netns exec "$NS_NAME" ping -c 2 -W 2 8.8.8.8; then
    echo "[!] Unexpected: ping succeeded. Namespace is not isolated as expected."
else
    echo "[+] Confirmed: namespace has zero network connectivity."
fi

echo
echo "=== Step 3: Create a veth pair (virtual ethernet cable) ==="
ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
ip link show | grep -E "$VETH_HOST|$VETH_NS"

echo
echo "=== Step 4: Move one end of the cable into the namespace ==="
ip link set "$VETH_NS" netns "$NS_NAME"
echo "[+] $VETH_NS moved into $NS_NAME (no longer visible on host):"
ip link show | grep "$VETH_NS" || echo "    (correctly absent from host interface list)"

echo
echo "=== Step 5: Bring both ends up and assign IPs ==="
ip link set "$VETH_HOST" up
ip netns exec "$NS_NAME" ip link set "$VETH_NS" up
ip addr add "$HOST_IP" dev "$VETH_HOST"
ip netns exec "$NS_NAME" ip addr add "$NS_IP" dev "$VETH_NS"

echo
echo "=== Step 6: Prove bidirectional connectivity across the veth pair ==="
echo "[*] Ping from namespace -> host:"
ip netns exec "$NS_NAME" ping -c 2 "${HOST_IP%/*}"

echo
echo "[*] Ping from host -> namespace:"
ping -c 2 "${NS_IP%/*}"

echo
echo "=== Done. Namespace '$NS_NAME' is isolated yet reachable via veth pair. ==="
echo "Run 'sudo ./network-namespace-demo.sh cleanup' to tear everything down."