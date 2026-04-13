#!/bin/bash
set -e

N6_IF="${N6_IF:-ens39}"
if ! ip link show "$N6_IF" >/dev/null 2>&1; then
	N6_IF="ens34"
fi

echo "=== UDP listeners 2152/8805 ==="
ss -unlp | grep -E ":2152|:8805" || true

echo "=== short capture N3 on ens38 (8s) ==="
timeout 8 tcpdump -ni ens38 udp port 2152 -c 20 2>/dev/null || true

echo "=== short capture internet egress on $N6_IF (8s, UE internet subnet) ==="
timeout 8 tcpdump -ni "$N6_IF" net 10.45.0.0/16 -c 20 2>/dev/null || true

echo "=== short capture docker bridge UE subnet (8s) ==="
BR=$(ip -o link | awk -F': ' '/br-d7320f7bfd5a/{print $2}')
timeout 8 tcpdump -ni "$BR" net 10.45.0.0/16 -c 20 2>/dev/null || true
