#!/bin/bash
# 全流程抓包：N2(NGAP/SCTP) + N4(PFCP) + N3(GTP-U) + N6(UE出口)
# 用法: bash /tmp/reattach_capture.sh [抓包秒数，默认120]
DURATION=${1:-120}
OUTDIR=/tmp/reattach_$(date +%Y%m%d_%H%M%S)
mkdir -p "$OUTDIR"

echo "==== 抓包目录: $OUTDIR ===="
echo "==== 持续 ${DURATION} 秒 ===="

# ---- 并行抓包 ----
# N2: AMF NGAP over SCTP 38412 (ens34 管理网，AMF_IP=172.22.0.x 用桥网)
tcpdump -i any -w "$OUTDIR/n2_ngap.pcap" -s 0 '(sctp port 38412)' &
PID_N2=$!

# N4: PFCP（eUPF host网络:8805，upf_ims桥网:8805）
tcpdump -i any -w "$OUTDIR/n4_pfcp.pcap" -s 0 'udp port 8805' &
PID_N4=$!

# N3-internet: ens38 上的 GTP-U
tcpdump -i ens38 -w "$OUTDIR/n3_internet_ens38.pcap" -s 0 'udp port 2152' &
PID_N3I=$!

# N3-ims: ens37 上的 GTP-U
tcpdump -i ens37 -w "$OUTDIR/n3_ims_ens37.pcap" -s 0 'udp port 2152' &
PID_N3M=$!

# N6: ens39 上 UE 出口流量（10.45/10.46段）
tcpdump -i ens39 -w "$OUTDIR/n6_ens39.pcap" -s 0 '(net 10.45.0.0/16 or net 10.46.0.0/16)' &
PID_N6=$!

echo "抓包 PID: N2=$PID_N2 N4=$PID_N4 N3I=$PID_N3I N3M=$PID_N3M N6=$PID_N6"
echo "等待 ${DURATION} 秒..."
sleep "$DURATION"

kill $PID_N2 $PID_N4 $PID_N3I $PID_N3M $PID_N6 2>/dev/null
wait 2>/dev/null

echo ""
echo "==== 抓包文件大小 ===="
ls -lh "$OUTDIR"/*.pcap

echo ""
echo "==== N2 NGAP 包摘要 (SCTP msg) ===="
tcpdump -r "$OUTDIR/n2_ngap.pcap" -nn 2>/dev/null | head -40

echo ""
echo "==== N4 PFCP 包摘要 ===="
tcpdump -r "$OUTDIR/n4_pfcp.pcap" -nn 2>/dev/null | head -40

echo ""
echo "==== N3 internet (ens38) GTP-U 包数+摘要 ===="
COUNT_I=$(tcpdump -r "$OUTDIR/n3_internet_ens38.pcap" -nn 2>/dev/null | wc -l)
echo "总包数: $COUNT_I"
tcpdump -r "$OUTDIR/n3_internet_ens38.pcap" -nn 2>/dev/null | grep -v 'Echo' | head -20
echo "--- Echo 统计 ---"
tcpdump -r "$OUTDIR/n3_internet_ens38.pcap" -nn 2>/dev/null | grep -c 'Echo' || true

echo ""
echo "==== N3 ims (ens37) GTP-U 包数+摘要 ===="
COUNT_M=$(tcpdump -r "$OUTDIR/n3_ims_ens37.pcap" -nn 2>/dev/null | wc -l)
echo "总包数: $COUNT_M"
tcpdump -r "$OUTDIR/n3_ims_ens37.pcap" -nn 2>/dev/null | grep -v 'Echo' | head -20
echo "--- Echo 统计 ---"
tcpdump -r "$OUTDIR/n3_ims_ens37.pcap" -nn 2>/dev/null | grep -c 'Echo' || true

echo ""
echo "==== N6 ens39 UE出口流量 ===="
tcpdump -r "$OUTDIR/n6_ens39.pcap" -nn 2>/dev/null | head -20

echo ""
echo "==== SMF 日志 (最近 ${DURATION}s) ===="
docker logs smf --since "${DURATION}s" 2>&1 | grep -Ei \
  'PDU Session|session establishment|PFCP.*session|N2.*setup|UE.*attach|dnn|Create session|FAR|PDR|Bearer' | head -60

echo ""
echo "==== eUPF 日志 (最近 ${DURATION}s) ===="
docker logs eupf --since "${DURATION}s" 2>&1 | grep -Ei \
  'session|PDR|FAR|N3|Create|Establish|association' | head -40

echo ""
echo "==== AMF 日志 (最近 ${DURATION}s) ===="
docker logs amf --since "${DURATION}s" 2>&1 | grep -Ei \
  'Registration|PDU.*Session|Attach|ue.*connect|initial' | head -40

echo ""
echo "==== 完成 ===="
echo "pcap 文件保留在: $OUTDIR"
