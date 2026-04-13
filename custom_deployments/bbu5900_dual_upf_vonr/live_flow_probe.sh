#!/bin/bash
set -e

N6_IF="${N6_IF:-ens39}"
if ! ip link show "$N6_IF" >/dev/null 2>&1; then
  N6_IF="ens34"
fi

echo "=== START $(date '+%F %T') ==="
BR_IF="br-d7320f7bfd5a"

if ! ip link show "$BR_IF" >/dev/null 2>&1; then
  BR_IF=$(ip -o link | awk -F': ' '/br-/{print $2; exit}')
fi

echo "Bridge IF: $BR_IF"
echo "N6 IF: $N6_IF"

echo "--- NAT counter BEFORE ---"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E '10.45.0.0/16|Chain POSTROUTING' || true

echo "--- Capture 30s on ens38/br/$N6_IF ---"
rm -f /tmp/n3_ens38.pcap /tmp/ue_br.pcap /tmp/egress_ens34.pcap

(timeout 30 tcpdump -ni ens38 udp port 2152 -w /tmp/n3_ens38.pcap >/tmp/n3_ens38.log 2>&1) &
P1=$!
(timeout 30 tcpdump -ni "$BR_IF" net 10.45.0.0/16 -w /tmp/ue_br.pcap >/tmp/ue_br.log 2>&1) &
P2=$!
(timeout 30 tcpdump -ni "$N6_IF" net 10.45.0.0/16 -w /tmp/egress_ens34.pcap >/tmp/egress_ens34.log 2>&1) &
P3=$!

wait $P1 || true
wait $P2 || true
wait $P3 || true

echo "--- NAT counter AFTER ---"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E '10.45.0.0/16|Chain POSTROUTING' || true

echo "--- Packet count summary ---"
echo -n "ens38 N3 packets: "
tcpdump -nn -r /tmp/n3_ens38.pcap 2>/dev/null | wc -l
echo -n "bridge UE subnet packets: "
tcpdump -nn -r /tmp/ue_br.pcap 2>/dev/null | wc -l
echo -n "$N6_IF UE-subnet packets: "
tcpdump -nn -r /tmp/egress_ens34.pcap 2>/dev/null | wc -l

echo "--- Sample ens38 N3 ---"
tcpdump -nn -r /tmp/n3_ens38.pcap 2>/dev/null | head -n 10 || true

echo "--- Sample bridge UE subnet ---"
tcpdump -nn -r /tmp/ue_br.pcap 2>/dev/null | head -n 10 || true

echo "--- Sample $N6_IF UE subnet ---"
tcpdump -nn -r /tmp/egress_ens34.pcap 2>/dev/null | head -n 10 || true

echo "=== END $(date '+%F %T') ==="
