#!/bin/bash
# 基线/双UPF 通用采集脚本
# 用法: bash /tmp/baseline_capture.sh [duration_seconds]
set -e
DUR=${1:-90}
DIR=/tmp/baseline_capture
rm -rf "$DIR"
mkdir -p "$DIR"
echo "=== Baseline capture start: $(date) ===" | tee "$DIR/meta.txt"
echo "Duration: ${DUR}s" >> "$DIR/meta.txt"

# 1) 容器状态快照
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" > "$DIR/containers.txt" 2>&1

# 2) SMF 运行时配置
docker exec smf cat /open5gs/install/etc/open5gs/smf.yaml > "$DIR/smf_runtime.yaml" 2>&1 || true

# 3) 订阅数据快照
docker exec mongo mongosh --quiet open5gs --eval 'db.subscribers.find({},{imsi:1,"slice.session.name":1}).forEach(function(d){printjson(d)})' > "$DIR/subscribers.json" 2>&1 || true

# 4) ens37 抓包 (N2 SCTP + IMS N3 GTP-U + PFCP)
nohup timeout "$DUR" tcpdump -i ens37 -s 0 -w "$DIR/ens37.pcap" "sctp or udp port 2152 or udp port 8805" >"$DIR/ens37_tcpdump.out" 2>&1 </dev/null &
echo $! > "$DIR/pids"

# 5) Docker bridge 抓包 (SBI + PFCP + SIP)
BR_IF=$(ip -o link show | grep 'br-' | head -1 | awk -F'[ :]+' '{print $2}')
if [ -n "$BR_IF" ]; then
  nohup timeout "$DUR" tcpdump -i "$BR_IF" -s 0 -w "$DIR/bridge_sbi.pcap" "tcp port 7777 or udp port 8805 or tcp port 5060 or udp port 5060" >"$DIR/bridge_tcpdump.out" 2>&1 </dev/null &
  echo $! >> "$DIR/pids"
  echo "Bridge interface: $BR_IF" >> "$DIR/meta.txt"
fi

# 6) AMF 日志
nohup timeout "$DUR" docker logs -f amf >"$DIR/amf.log" 2>&1 </dev/null &
echo $! >> "$DIR/pids"

# 7) SMF 日志
nohup timeout "$DUR" docker logs -f smf >"$DIR/smf.log" 2>&1 </dev/null &
echo $! >> "$DIR/pids"

# 8) UPF 日志 (自动检测: upf / eupf / upf_ims)
for c in upf eupf upf_ims; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    nohup timeout "$DUR" docker logs -f "$c" >"$DIR/${c}.log" 2>&1 </dev/null &
    echo $! >> "$DIR/pids"
  fi
done

# 9) IMS 日志 (pcscf / icscf / scscf)
for c in pcscf icscf scscf; do
  if docker ps --format '{{.Names}}' | grep -qx "$c"; then
    nohup timeout "$DUR" docker logs -f "$c" >"$DIR/${c}.log" 2>&1 </dev/null &
    echo $! >> "$DIR/pids"
  fi
done

NPROC=$(wc -l < "$DIR/pids")
echo "All captures started ($NPROC processes). Waiting ${DUR}s..."
sleep "$DUR"
echo "=== Capture done: $(date) ===" >> "$DIR/meta.txt"
echo ""
echo "=== Files collected ==="
ls -lh "$DIR/"
echo "BASELINE_CAPTURE_DONE"
