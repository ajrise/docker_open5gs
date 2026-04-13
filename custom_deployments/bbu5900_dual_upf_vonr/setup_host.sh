#!/bin/bash
# 宿主机环境修复脚本 - BBU5900双UPF VoNR部署前置条件
# 执行需要 sudo 权限

set -e

echo "====== 1. SCTP内核模块 ======"
modprobe sctp
if ! grep -q '^sctp$' /etc/modules-load.d/sctp.conf 2>/dev/null; then
    echo 'sctp' > /etc/modules-load.d/sctp.conf
fi
lsmod | grep sctp && echo "SCTP: OK" || echo "SCTP: 加载失败"

echo "====== 2. bpffs挂载 ======"
if ! mountpoint -q /sys/fs/bpf; then
    mount -t bpf bpffs /sys/fs/bpf
fi
if ! grep -q 'bpffs' /etc/fstab; then
    echo 'bpffs /sys/fs/bpf bpf defaults 0 0' >> /etc/fstab
fi
mountpoint /sys/fs/bpf && echo "bpffs: OK"

echo "====== 3. IP转发 ======"
sysctl -w net.ipv4.ip_forward=1
if ! grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf; then
    echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf
fi
echo "ip_forward: $(cat /proc/sys/net/ipv4/ip_forward)"

echo "====== 4. 项目克隆 ======"
cd /home/ecore
if [ -d docker_open5gs ]; then
    echo "目录已存在，跳过克隆，执行 git pull"
    cd docker_open5gs
    git pull
else
    git clone https://github.com/ajrise/docker_open5gs.git
    echo "克隆完成"
fi

echo "====== 全部完成 ======"
