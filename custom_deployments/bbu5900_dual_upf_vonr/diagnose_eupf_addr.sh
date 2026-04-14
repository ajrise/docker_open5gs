#!/bin/bash

# 诊断脚本：检验 eUPF N3 地址配置和 PFCP 消息

set -e

DOCKER_HOST="${1:-192.168.1.188}"
CONTAINER="eupf"

echo "========== eUPF 环境变量检查 =========="
ssh root@${DOCKER_HOST} docker exec ${CONTAINER} env | grep -E 'UPF_N3|UPF_PFCP|UPF_ADVERTISE' || echo "未找到相关变量"

echo ""
echo "========== eUPF 启动日志检查 N3 地址 =========="
ssh root@${DOCKER_HOST} docker logs ${CONTAINER} 2>&1 | grep -i "n3 address" | tail -5 || echo "未找到 N3 address 日志"

echo ""
echo "========== eUPF 当前的 PFCP 连接检查 =========="
ssh root@${DOCKER_HOST} docker exec ${CONTAINER} netstat -tlunp 2>/dev/null | grep -E '8805|LISTEN' || echo "未找到 PFCP 连接"

echo ""
echo "========== SMF 日志中的 UPF 地址学习 =========="
ssh root@${DOCKER_HOST} docker logs smf 2>&1 | grep -i "upf.*addr\|n3.*addr" | tail -5 || echo "未找到 SMF UPF 地址学习日志"

echo ""
echo "========== 抓 PFCP N4 包（5秒）=========="
echo "监听 172.22.0.7 (SMF) 到 10.10.10.101 (eUPF) 的 PFCP 流量..."
ssh root@${DOCKER_HOST} timeout 5 tcpdump -i ens38 'udp port 8805' -n -vv 2>/dev/null | grep -E 'F-TEID|GTP|ip-' || echo "未捕获到 PFCP 包（可能需要运行 gNB 重新注册）"

echo ""
echo "========== 验证网络连通性 =========="
ssh root@${DOCKER_HOST} ping -c 1 10.10.10.101 && echo "✓ 主机可达 10.10.10.101" || echo "✗ 主机无法达 10.10.10.101"

echo ""
echo "========== 诊断完成 =========="
