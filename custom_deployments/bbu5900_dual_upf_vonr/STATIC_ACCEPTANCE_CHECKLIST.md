# 静态验收清单（当前配置版）

适用范围：
- 目录：custom_deployments/bbu5900_dual_upf_vonr
- 当前策略：先不改拓扑，仅验证现有配置是否满足联调前提

验收目标：
1. gNB -> AMF 的 N2 可达
2. gNB -> eUPF 的 N3 可达
3. IMS 专载建立后回程链路是否完整
4. DNN 分流是否命中（internet -> eUPF, ims -> 原生 UPF）

--------------------------------------------------

## A. 启动前检查

1) 环境变量加载
- 执行：
  set -a
  source .custom_env
  set +a

- 预期：
  echo $AMF_IP 输出 172.22.0.10（或你当前值）
  echo $UPF_IP 输出 172.22.0.8（或你当前值）
  echo $IMS_UPF_IP 输出 172.22.0.90（或你当前值）

2) 宿主机端口监听
- 执行：
  sudo ss -lpn | grep 38412
  sudo ss -lunp | grep 2152

- 预期：
  38412/sctp 对外监听（AMF）
  2152/udp 对外监听（eUPF）

--------------------------------------------------

## B. N2 可达性验收（gNB -> AMF）

1) 从 gNB 所在网侧做连通性
- 执行（在 gNB 侧）：
  ping <AMF_IP或宿主可达IP>
  nc -zv -u <AMF_IP或宿主可达IP> 38412 （仅做基础探测，SCTP以日志为准）

2) 用 AMF 日志判定是否真正建立 NGAP
- 执行：
  sudo docker logs --tail=200 amf

- 预期关键字：
  gNB 关联建立、NG Setup、UE Registration 相关日志出现

失败判定：
- gNB 侧发起后 AMF 无任何 NGAP 相关日志

--------------------------------------------------

## C. N3 可达性验收（gNB -> eUPF）

1) eUPF 端口检查
- 执行：
  sudo docker logs --tail=200 eupf
  sudo ss -lunp | grep 2152

- 预期：
  eUPF 正常启动，无 PFCP/N3 初始化错误
  2152/udp 处于监听状态

2) 业务触发后观察 GTP-U 迹象
- 执行：
  sudo tcpdump -ni any udp port 2152 -c 20

- 预期：
  UE 建立 internet PDU 后能看到 N3 GTP-U 报文

失败判定：
- UE 触发业务后无任何 2152 报文

--------------------------------------------------

## D. DNN 分流命中验收（核心）

1) SMF 侧查看会话和 UPF 选择
- 执行：
  sudo docker logs --tail=400 smf

- 预期：
  internet 会话对应 UPF_IP
  ims 会话对应 IMS_UPF_IP

2) eUPF / upf_ims 分别观察负载
- 执行：
  sudo docker logs --tail=200 eupf
  sudo docker logs --tail=200 upf_ims

- 预期：
  internet 数据流主要出现在 eupf
  ims 相关会话/转发出现在 upf_ims

失败判定：
- 两个 DNN 都命中同一个 UPF，或命中关系反转

--------------------------------------------------

## E. IMS 专载与回程链路验收

1) 验证 IMS 专载建立
- 执行：
  sudo docker logs --tail=300 smf
  sudo docker logs --tail=300 upf_ims

- 预期：
  ims DNN 的 PDU 会话建立成功
  upf_ims 出现对应会话/转发日志

2) 验证 IMS 子网回程（重点）
- 执行（宿主机）：
  ip route | grep 192.168.101.0/24

- 预期：
  存在到 IMS UE 子网（UE_IPV4_IMS）的明确回程路由

风险说明：
- 当前编排默认只显式创建了 internet 子网回程容器 eupf-routes
- 若 IMS 回程未落地，常见现象是 IMS 注册偶发失败或会话不稳定

--------------------------------------------------

## F. 一次性验收结论模板

通过：
- N2：通过/不通过
- N3：通过/不通过
- DNN 分流：通过/不通过
- IMS 回程：通过/不通过

阻断项（如有）：
- 示例：IMS 子网回程缺失
- 示例：gNB 无法到达 AMF 38412/sctp

建议动作：
- 若 N2/N3 任一不通过，先修网络连通与端口暴露
- 若 IMS 回程不通过，补 IMS 子网宿主回程策略后复验
