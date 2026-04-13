#!/bin/bash
set -e

echo "=== START $(date '+%F %T') ==="

echo "--- Capture 40s: N3 on ens38 (all GTP-U) ---"
(timeout 40 tcpdump -ni ens38 udp port 2152 -w /tmp/n3_all.pcap >/tmp/n3_all.log 2>&1) &
P1=$!

echo "--- Capture 40s: Internet side on ens34 (ICMP or DNS to 8.8.8.8) ---"
(timeout 40 tcpdump -ni ens34 'icmp or (udp and port 53) or host 8.8.8.8' -w /tmp/wan_probe.pcap >/tmp/wan_probe.log 2>&1) &
P2=$!

wait $P1 || true
wait $P2 || true

echo "--- Packet count summary ---"
echo -n "ens38 gtp packets: "
tcpdump -nn -r /tmp/n3_all.pcap 2>/dev/null | wc -l
echo -n "ens34 wan probe packets: "
tcpdump -nn -r /tmp/wan_probe.pcap 2>/dev/null | wc -l

echo "--- Top ens38 samples ---"
tcpdump -nn -r /tmp/n3_all.pcap 2>/dev/null | head -n 20 || true

echo "--- Top ens34 samples ---"
tcpdump -nn -r /tmp/wan_probe.pcap 2>/dev/null | head -n 20 || true

echo "=== END $(date '+%F %T') ==="
