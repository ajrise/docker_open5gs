#!/bin/bash
# 网卡静态IP配置脚本 - BBU5900双UPF VoNR场景
# ens37 → N2(AMF) + IMS UPF N3:  10.10.10.100/24
# ens38 → eUPF N3(internet):      10.10.10.101/24
# 执行需要 sudo 权限

set -e

echo "====== 配置 ens37 / ens38 静态IP ======"

NETPLAN_FILE=/etc/netplan/60-bbu5900-n2-n3.yaml

cat > "$NETPLAN_FILE" << 'EOF'
# BBU5900双UPF VoNR场景 - N2/N3接口静态IP配置
# ens37: N2(AMF) + IMS UPF N3
# ens38: eUPF N3 (internet)
network:
  version: 2
  ethernets:
    ens37:
      dhcp4: false
      addresses:
        - 10.10.10.100/24
      # 不设置默认网关，避免覆盖管理网络路由
    ens38:
      dhcp4: false
      addresses:
        - 10.10.10.101/24
EOF

chmod 600 "$NETPLAN_FILE"
echo "netplan配置写入: $NETPLAN_FILE"

netplan apply
echo "netplan apply: OK"

echo "====== 验证 ======"
ip addr show ens37
ip addr show ens38

echo "====== 完成 ======"
