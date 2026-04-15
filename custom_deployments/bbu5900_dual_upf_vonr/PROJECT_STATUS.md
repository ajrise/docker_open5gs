# BBU5900 Dual-UPF VoNR 工作成果总结

## 1. 已完成成果

- 完成 **单 SMF + 双 UPF** 分流部署：
  - `internet` → eUPF
  - `ims` → Open5GS UPF
- 修复 eUPF 互联网数据面问题：确认 XDP 同时挂载 `ens38,ens39`
- 验证 UE 地址池分离：
  - `internet`：`10.45.0.0/16`
  - `ims`：`10.46.0.0/16`
- 实测短号 `801003` VoNR 呼叫成功，完整呼叫流程正常
- 新增统一日志审计脚本 `system_log_audit.sh`
- 所有自定义内容保持在当前 overlay 目录内，未改动上游默认场景

## 2. 关键问题与解决方式

### 问题一：UE 注册成功但无法上网
- **根因**：eUPF XDP 仅挂在 N3 `ens38`，下行流量从 N6 `ens39` 入站时未被拦截与重新封装
- **修复**：将 `UPF_INTERFACE_NAME` 调整为 `ens38,ens39`
- **结果**：internet 业务恢复

### 问题二：gNB 间歇性提示 eUPF 不可用
- **根因**：`ens37`、`ens38` 与 gNB 位于同一 VLAN / 同一子网，宿主机 ARP 与回程选路漂移
- **修复**：
  - 设置 `arp_ignore=1`
  - 设置 `arp_announce=2`
  - 为 `10.10.10.100/101` 增加源地址策略路由
- **结果**：gNB 侧恢复正常，eUPF 建链稳定

### 问题三：VoNR 呼叫偶发异常
- **根因**：号码格式会影响 S-CSCF 路由逻辑
- **现状**：短号 `801003` 已验证成功；`tel:+...` 仍可能进入 PSTN/ENUM 分支
- **建议**：当前优先使用本地短号拨测

## 3. 当前遗留项

- `tel:+801003` 这类格式的长期规范化处理仍待结合现场 ENUM / PSTN 配置进一步完善
- 若后续继续扩展双 N3 场景，建议从网络层面将两个 N3 拆到不同 VLAN/子网，避免依赖宿主机策略路由作为长期方案

## 4. 当前建议运维动作

```bash
# 启动后健康检查
sudo docker ps --format 'table {{.Names}}\t{{.Status}}'
sudo docker logs --tail=80 smf
sudo docker logs --tail=80 eupf
sudo docker logs --tail=80 upf

# 日志统一审计
bash ./system_log_audit.sh 30m
```

## 5. 交付结论

当前场景已经具备：
- UE 正常接入
- internet 数据面可用
- IMS 独立承载可用
- 短号 VoNR 呼叫可用
- 空闲态下可通过下行业务恢复业务态
- 基础审计与故障复盘工具可用

## 6. 第一阶段结论

截至 2026-04-15，核心网侧第一阶段目标可以视为完成：
- 基础接入、internet、IMS、VoNR 主流程均已验证
- 最近检查窗口内未发现明确的核心网侧 paging failure 证据
- user-inactivity 释放已确认主要由 gNB 侧触发
- 当前剩余优化重点已偏向无线侧空闲管理与恢复时机

## 7. 后续路线入口

为便于后续持续推进、GitHub 归档与阶段追踪，已新增路线图文档：
- `ROADMAP.md`：统一记录项目定位、阶段目标、工具建议、仓库协作策略与后续演进方向

建议后续所有阶段性推进都围绕该路线图与本状态文档同步更新。
