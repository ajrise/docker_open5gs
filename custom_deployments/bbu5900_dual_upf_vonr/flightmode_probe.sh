#!/bin/bash
set -e

N6_IF="${N6_IF:-ens39}"
if ! ip link show "$N6_IF" >/dev/null 2>&1; then
  N6_IF="ens34"
fi

echo "=== FLIGHTMODE PROBE START $(date '+%F %T') ==="
BR_IF="br-d7320f7bfd5a"
if ! ip link show "$BR_IF" >/dev/null 2>&1; then
  BR_IF=$(ip -o link | awk -F': ' '/br-/{print $2; exit}')
fi

echo "Bridge IF: $BR_IF"
echo "N6 IF: $N6_IF"

echo "--- NAT before ---"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E '10.45.0.0/16|10.46.0.0/16|Chain POSTROUTING' || true

echo "--- Start 70s captures ---"
rm -f /tmp/fm_n3_ens38.pcap /tmp/fm_br_inet.pcap /tmp/fm_br_ims.pcap /tmp/fm_ens34_dnsicmp.pcap

(timeout 70 tcpdump -ni ens38 udp port 2152 -w /tmp/fm_n3_ens38.pcap >/tmp/fm_n3_ens38.log 2>&1) & P1=$!
(timeout 70 tcpdump -ni "$BR_IF" net 10.45.0.0/16 -w /tmp/fm_br_inet.pcap >/tmp/fm_br_inet.log 2>&1) & P2=$!
(timeout 70 tcpdump -ni "$BR_IF" net 10.46.0.0/16 -w /tmp/fm_br_ims.pcap >/tmp/fm_br_ims.log 2>&1) & P3=$!
(timeout 70 tcpdump -ni "$N6_IF" '(icmp or (udp and port 53) or host 8.8.8.8)' -w /tmp/fm_ens34_dnsicmp.pcap >/tmp/fm_ens34_dnsicmp.log 2>&1) & P4=$!

wait $P1 || true
wait $P2 || true
wait $P3 || true
wait $P4 || true

echo "--- NAT after ---"
iptables -t nat -L POSTROUTING -n -v --line-numbers | grep -E '10.45.0.0/16|10.46.0.0/16|Chain POSTROUTING' || true

echo "--- Packet counts ---"
echo -n "ens38 gtp(2152): "; tcpdump -nn -r /tmp/fm_n3_ens38.pcap 2>/dev/null | wc -l
echo -n "bridge internet subnet: "; tcpdump -nn -r /tmp/fm_br_inet.pcap 2>/dev/null | wc -l
echo -n "bridge ims subnet: "; tcpdump -nn -r /tmp/fm_br_ims.pcap 2>/dev/null | wc -l
echo -n "$N6_IF dns/icmp/8.8.8.8: "; tcpdump -nn -r /tmp/fm_ens34_dnsicmp.pcap 2>/dev/null | wc -l

echo "--- Top samples: ens38 ---"
tcpdump -nn -r /tmp/fm_n3_ens38.pcap 2>/dev/null | head -n 20 || true

echo "--- Top samples: bridge internet ---"
tcpdump -nn -r /tmp/fm_br_inet.pcap 2>/dev/null | head -n 20 || true

echo "--- Top samples: bridge ims ---"
tcpdump -nn -r /tmp/fm_br_ims.pcap 2>/dev/null | head -n 20 || true

echo "--- Top samples: $N6_IF dns/icmp ---"
tcpdump -nn -r /tmp/fm_ens34_dnsicmp.pcap 2>/dev/null | head -n 20 || true

echo "=== FLIGHTMODE PROBE END $(date '+%F %T') ==="
