# 部署环境准备说明

本场景面向 Linux 主机，请在 Linux 部署机执行以下命令。

## 1) 主机前置条件

- Ubuntu 22.04 及以上（推荐）
- Docker Engine 24+ 与 Docker Compose v2
- 具备 root 或 sudo 权限
- 内核能力满足 eUPF 与原生 UPF 运行要求：
  - `ip_forward`
  - `nf_tables` / `iptables-nft`
  - `bpffs` 已挂载到 `/sys/fs/bpf`
  - `debugfs` 已挂载到 `/sys/kernel/debug`

## 2) 快速预检查

在 `docker_open5gs/custom_deployments/bbu5900_dual_upf_vonr` 目录执行：

```bash
chmod +x ./prepare_host.sh
./prepare_host.sh check
```

## 3) 一键应用推荐主机设置

```bash
sudo ./prepare_host.sh apply
```

脚本动作：

- 启用 `net.ipv4.ip_forward=1`
- 确保 `bpffs` 与 `debugfs` 已挂载
- 若缺失则创建 `../../log` 目录

## 4) 准备场景变量

编辑 `.custom_env`，至少确认以下字段：

- `DOCKER_HOST_IP`
- `TEST_NETWORK`
- `UPF_IP` / `IMS_UPF_IP`
- `UPF_PFCP_IP`：本场景固定填写宿主机 bridge 地址 `172.22.0.1`，不要填写 `ens38` 地址
- `UPF_ADVERTISE_IP` / `IMS_UPF_ADVERTISE_IP`
- `UE_IPV4_INTERNET` / `UE_IPV4_IMS`
- `MCC` / `MNC` / `TAC`

补充说明：

- eUPF 采用 `network_mode: host`，PFCP 控制面与 N3 用户面地址是分离的。
- `UPF_PFCP_IP` 供 SMF 建立 N4/PFCP，使用 bridge 地址 `172.22.0.1`。
- `UPF_ADVERTISE_IP` 供 PFCP NodeID/N3 advertise 与 gNB 建立 GTP-U，使用 `ens38` 地址 `10.10.10.101`。

## 5) 镜像准备（优先拉取，按需构建）

### 方案A：优先使用预构建镜像（推荐）

```bash
sudo docker pull ghcr.io/herlesupreeth/docker_open5gs:master
sudo docker tag ghcr.io/herlesupreeth/docker_open5gs:master docker_open5gs

sudo docker pull ghcr.io/herlesupreeth/docker_kamailio:master
sudo docker tag ghcr.io/herlesupreeth/docker_kamailio:master docker_kamailio

# 中文注释：eUPF 按官方推荐，直接使用 edgecomllc 官方镜像
sudo docker pull ghcr.io/edgecomllc/eupf:main
```

### 方案B：仅在需要时构建镜像

仅当你修改了对应目录内容，或预构建镜像不可用时再构建：

```bash
cd ../../base && sudo docker build --no-cache --force-rm -t docker_open5gs .
cd ../ims_base && sudo docker build --no-cache --force-rm -t docker_kamailio .

# 仅在必须自定义 eUPF 时才需要本地构建（默认不需要）
# cd ../eupf && sudo docker build --no-cache --force-rm -t local/eupf:latest .
```

## 6) 双 N3 同子网部署的额外建议

如果 `ens37`（AMF/IMS N3）与 `ens38`（eUPF N3）和 gNB 处于**同一 VLAN / 同一子网**，建议在宿主机额外固定 ARP 与源路由，避免 eUPF 回程漂移到错误网卡：

```bash
sudo sysctl -w net.ipv4.conf.all.arp_ignore=1
sudo sysctl -w net.ipv4.conf.all.arp_announce=2

sudo ip rule add from 10.10.10.100/32 table 100
sudo ip route add 10.10.10.0/24 dev ens37 src 10.10.10.100 table 100

sudo ip rule add from 10.10.10.101/32 table 101
sudo ip route add 10.10.10.0/24 dev ens38 src 10.10.10.101 table 101
```

> 长期更优方案是将两个 N3 接口拆到不同 VLAN 或子网。

## 7) 启动场景

```bash
cd ../custom_deployments/bbu5900_dual_upf_vonr
set -a
source .custom_env
set +a
sudo docker compose -f sa-vonr-deploy.yaml up -d
```

## 8) 基础健康检查

```bash
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo docker logs --tail=80 smf
sudo docker logs --tail=80 eupf
sudo docker logs --tail=80 upf
bash ./system_log_audit.sh 30m
```

## 9) 外部商用RAN/UE对接说明

- 当前 fork 已移除模拟 gNB/UE 编排文件。
- 请使用商用 gNB 与实体 UE 接入本场景的 AMF/UPF 地址。
- 重点验证：
  - UE 能在 AMF 正常注册
  - `internet` PDU 会话进入 eUPF
  - `ims` PDU 会话进入原生 Open5GS UPF

## 10) 静态验收执行

请按以下清单逐项验收：

- [STATIC_ACCEPTANCE_CHECKLIST.md](STATIC_ACCEPTANCE_CHECKLIST.md)
