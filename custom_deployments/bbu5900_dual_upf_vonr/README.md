# bbu5900_dual_upf_vonr

面向华为 BBU5900 商用基站和实体 UE 的 **5G SA VoNR + 双 UPF** 自定义部署场景。

## 架构概览

```
                   ┌─────────┐
                   │  gNB    │ (华为 BBU5900)
                   │ PLMN    │
                   └──┬───┬──┘
                 N2/SCTP  N3/GTP-U
                (ens37)   ├──────────────────────┐
                   │      │                      │
           10.10.10.100  10.10.10.101        10.10.10.100
                   │      │                      │
              ┌────┴──┐  ┌┴──────────┐    ┌──────┴──────┐
              │  AMF  │  │  eUPF     │    │  UPF (IMS)  │
              │bridge │  │host-mode  │    │  bridge     │
              └───────┘  │XDP ens38  │    │  172.22.0.8 │
                         │    ens39  │    └──────┬──────┘
                         └─────┬─────┘           │
                          N6 (ens39)         IMS Bridge
                          192.168.2.87       ┌───┴───┐
                               │             │P/I/S- │
                          ┌────┴───┐         │CSCF   │
                          │Internet│         └───────┘
                          └────────┘

  DNN "internet" → eUPF (eBPF/XDP)  → N6 ens39 → Internet
  DNN "ims"      → Open5GS UPF      → bridge   → Kamailio IMS
```

**核心设计**:
- 单 SMF、双 PFCP 客户端架构
- eUPF 以 `network_mode: host` 运行，XDP 同时挂载 N3 (ens38) + N6 (ens39)
- 原生 Open5GS UPF 仅承载 IMS，通过 `ports: 10.10.10.100:2152` 端口映射接收 N3 GTP-U
- 本场景不依赖任何模拟 gNB/UE 容器

## 所在上游项目中的位置

本目录是 `docker_open5gs` 项目的 **纯覆盖层**（overlay），位于 `custom_deployments/bbu5900_dual_upf_vonr/`。上游项目的所有原始文件**零修改**，本场景的全部自定义内容集中在此目录内。

## 文件说明

| 文件 | 类型 | 用途 |
|------|------|------|
| `sa-vonr-deploy.yaml` | 核心 | Docker Compose 主编排（25个服务） |
| `.custom_env` | 核心 | 场景独立环境变量 |
| `smf/smf.yaml` | 覆盖 | SMF 配置模板，含双 PFCP 客户端（internet→eUPF, ims→UPF） |
| `smf/smf_init.sh` | 覆盖 | SMF 初始化脚本，增加 `UPF_PFCP_IP`/`IMS_UPF_IP` 变量替换 |
| `upf/upf.yaml` | 覆盖 | 原生 UPF 配置模板，仅 IMS DNN |
| `upf/upf_init.sh` | 覆盖 | IMS UPF 初始化脚本，仅创建 ogstun2 |
| `ue_policy_routing.sh` | 运维 | UE 子网策略路由管理（apply/status/remove + systemd） |
| `baseline_capture.sh` | 诊断 | 多接口抓包 + 日志基线采集 |
| `diagnose_eupf_addr.sh` | 诊断 | eUPF 地址与 PFCP 诊断 |
| `system_log_audit.sh` | 运维/审计 | 汇总所有网元日志，统计异常、重连、UE离线与 IMS 呼叫关键事件 |
| `smf/smf.conf`, `smf/make_certs.sh`, `smf/ip_utils.py` | 镜像 | 上游副本（Docker volume mount 整目录替换所需） |
| `upf/tun_if.py`, `upf/ip_utils.py` | 镜像 | 上游副本（Docker volume mount 整目录替换所需） |
| `PREPARE_ENV.md` | 文档 | 部署环境准备详细说明 |
| `PROJECT_STATUS.md` | 文档 | 本次联调成果、问题、修复方式与遗留项总结 |
| `CONFIRMED_FACTS.md` | 文档 | 截至当前阶段已通过抓包、日志、拨测确认的事实清单 |
| `ROADMAP.md` | 文档 | 项目整体规划、阶段路线与后续演进方向 |
| `STATIC_ACCEPTANCE_CHECKLIST.md` | 文档 | 静态验收检查清单 |

> **为什么存在"镜像"文件？** Docker volume mount (`./smf:/mnt/smf`) 是整目录替换，容器内原有文件被遮蔽。因此容器 init 脚本所依赖的辅助文件（`ip_utils.py`、`tun_if.py`、`make_certs.sh`、`smf.conf`）必须在覆盖目录中保留一份副本。

## 实施路径与关键修改

### 相对于上游 `with_eupf` 场景的主要变更

1. **双 UPF 分流**：SMF pfcp.client 从单 UPF 改为双 PFCP 客户端（`UPF_PFCP_IP→internet`, `IMS_UPF_IP→ims`），实现 DNN 级分流
2. **eUPF 双网卡 XDP**：`UPF_INTERFACE_NAME=ens38,ens39`，XDP 同时挂载 N3 和 N6 接口。XDP 仅处理入方向（ingress），下行包从 N6 到达 ens39 后才能被 GTP 封装
3. **IMS UPF 端口映射**：原生 UPF 在 bridge 内运行，通过 `ports: 10.10.10.100:2152:2152/udp` 暴露 N3 端口，gNB 通过物理 IP 直达
4. **AMF N2 绑定**：SCTP 绑定到物理 NIC `10.10.10.100:38412`，供商用基站直连
5. **UE 子网策略路由**：`ue_policy_routing.sh` 通过 ip rule + ip route table 将 UE 子网（10.45.0.0/16, 10.46.0.0/16）流量从 N6 接口（ens39）出站
6. **eUPF FTUP**：启用 `UPF_FEATURE_FTUP=true`，由 eUPF 自行上报 F-TEID（N3 IP=10.10.10.101），避免手动配置 GTP-U 节点地址

### 网络拓扑（物理 NIC 分配）

| 接口 | IP 地址 | 用途 |
|------|---------|------|
| ens37 | 10.10.10.100 | N2 (AMF SCTP) + IMS N3 (UPF 端口映射) |
| ens38 | 10.10.10.101 | eUPF N3 (internet GTP-U, XDP) |
| ens39 | 192.168.2.87 | N6 (internet 出口, XDP) |
| docker bridge | 172.22.0.0/24 | 核心网 SBI + IMS SIP |

## 快速部署

详细环境准备见 [PREPARE_ENV.md](PREPARE_ENV.md)，阶段性成果与遗留问题见 [PROJECT_STATUS.md](PROJECT_STATUS.md)，整体规划与后续路线见 [ROADMAP.md](ROADMAP.md)。

```bash
# 1. 拉取镜像
docker pull ghcr.io/herlesupreeth/docker_open5gs:master
docker tag ghcr.io/herlesupreeth/docker_open5gs:master docker_open5gs
docker pull ghcr.io/herlesupreeth/docker_kamailio:master
docker tag ghcr.io/herlesupreeth/docker_kamailio:master docker_kamailio
docker pull ghcr.io/edgecomllc/eupf:main

# 2. 应用 UE 策略路由（首次或重启后）
cd docker_open5gs/custom_deployments/bbu5900_dual_upf_vonr
sudo ./ue_policy_routing.sh apply

# 3. 启动
set -a && source .custom_env && set +a
docker compose -f sa-vonr-deploy.yaml up -d

# 4. 验证
docker ps --format 'table {{.Names}}\t{{.Status}}'
docker logs --tail=30 smf   # 确认双 PFCP Association
docker logs --tail=30 eupf  # 确认 XDP on ens38,ens39
```

## 当前已验证结果

- **internet 数据业务恢复正常**：UE `internet` PDU 会话经 eUPF 转发，地址池为 `10.45.0.0/16`
- **IMS 业务保持独立承载**：`ims` PDU 会话走 Open5GS UPF，地址池为 `10.46.0.0/16`
- **VoNR 呼叫已实测成功**：现场以短号 `801003` 直拨，链路完成 `INVITE → 100 Trying → 200 OK → ACK → BYE`
- **空闲态恢复链已验证可用**：UE 在空闲或被 user-inactivity 释放后，只要有下行业务触发，能够重新恢复业务态
- **系统审计脚本可用**：已新增 `system_log_audit.sh`，可统一汇总 Open5GS / IMS / eUPF 日志并生成时间线

## 已验证陷阱

| 陷阱 | 原因 | 正确做法 |
|------|------|----------|
| eUPF PFCP 事务匹配失败 | `UPF_PFCP_IP` 设为 `10.10.10.101`，但 eUPF 回包源为 `172.22.0.1` | `UPF_PFCP_IP=172.22.0.1`（bridge 网关地址） |
| UE 无法上网 | XDP 仅在 ens38(N3)，下行包在 ens39(N6) 无法被拦截封装 | `UPF_INTERFACE_NAME=ens38,ens39` |
| gNB 间歇性提示 eUPF 不可用 | `ens37/ens38/gNB` 同 VLAN 同子网，Linux 回程与 ARP 选择漂移 | 为 `10.10.10.100/101` 配置 `arp_ignore=1`、`arp_announce=2` 与源地址策略路由；长期建议拆分 VLAN/子网 |
| XDP 流量不经过 iptables | `bpf_redirect()` 完全绕过 netfilter | 使用上游网关静态路由而非 MASQUERADE |
| 环境变量未加载 | compose 默认读 `.env`，本场景用 `.custom_env` | `set -a && source .custom_env` 或 `--env-file .custom_env` |
| IMS_UPF_IP 替换污染 | sed 替换 `UPF_IP` 时意外匹配 `IMS_UPF_IP` 子串 | `smf_init.sh` 中先替换带前缀的 `IMS_UPF_IP`，再替换 `UPF_PFCP_IP` |

## IMS 拨号建议

- **优先使用本地短号直拨**：当前实测 `801003` 可稳定走本地 IMS terminating route
- **谨慎使用 `tel:+...` 格式**：该格式更容易进入 PSTN/ENUM 分支，若现场未配置完整外部 ENUM / PSTN 网关，可能出现呼叫失败或不稳定

## 日志审计与运维

```bash
# 最近30分钟统一审计
bash ./system_log_audit.sh

# 审计最近2小时并输出到指定目录
bash ./system_log_audit.sh 2h /tmp/open5gs_audit
```

脚本输出内容：
- `host_snapshot.txt`：容器、路由、关键监听端口快照
- `summary.txt`：各网元错误/重连/UE状态/IMS事件统计
- `important_timeline.log`：跨容器关键事件时间线

建议在 **UE 重入网、拨测前后、故障复盘后** 各执行一次，用于快速比较系统状态。
