# bbu5900_dual_upf_vonr

面向华为 BBU5900 商用基站和实体 UE 的 SA VoNR 自定义部署场景。

## 设计目标

- 保持单 SMF 架构。
- `internet` APN 走 eUPF。
- `ims` APN 保留原生 Open5GS UPF。
- 本场景不依赖任何模拟 gNB/UE 容器。

## 文件说明

- `sa-vonr-deploy.yaml`：主编排文件。
- `.custom_env`：本场景独立环境变量。
- `smf/*`：本场景 SMF 模板与初始化脚本（含双 UPF 的 PFCP 映射）。
- `upf/*`：本场景原生 UPF 模板与初始化脚本（仅承载 `ims` APN）。

## 使用方法

```bash
cd docker_open5gs/custom_deployments/bbu5900_dual_upf_vonr
set -a
source .custom_env
set +a

# 按官方推荐拉取 eUPF 官方镜像
docker pull ghcr.io/edgecomllc/eupf:main

docker compose -f sa-vonr-deploy.yaml up -d
```

## 说明

- 部署前请先按现网地址修改 `.custom_env`（特别是 N2/N3/N6 相关地址）。
- Open5GS 与 IMS 的其余配置仍复用仓库顶层各组件目录。
- 建议将二开内容集中在本目录，便于保持与上游兼容。
