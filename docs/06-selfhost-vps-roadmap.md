# 06 · 自建 VPS 路线图：彻底摆脱机场依赖

> 机场的三大不可控：**节点质量随它摆布**（大面积故障/假活节点）、**订阅可被随时 403**（实测两次）、**账号规则单方面变更**。要真正稳定，唯一方案是拥有一条自己控制的线路。本仓库的其他层（CF 备用、住宅出口、NekoBox 备用客户端）都已完成，这是最后一块拼图。

## 目标架构（完成后）

```
Clash Verge (rule 模式)
  ├─ 线路1 (主用): 自建 VPS — VLESS+REALITY+Vision   ← 你完全掌控
  ├─ 线路2 (备用): CF Workers 免费节点 (edgetunnel)   ← 已部署 ✅
  ├─ 线路3 (应急): 机场（降级为第三层，可有可无）
  └─ AI/账号出口: MIYA 住宅 (Fail Closed)             ← 已部署 ✅
```

三层线路来自三个完全独立的提供商（VPS 厂商 / Cloudflare / 住宅代理商），任何一家出事都自动切换。

## 第一步：买 VPS（约 5 分钟）

**配置要求**（个人代理足够，来源 personal-edge-proxy 实测）：

```
1 vCPU / 1GB RAM / Ubuntu 24.04 LTS 或 Debian 12+
公网 IPv4 + TCP/UDP 可用
```

**选购要点**：
1. **买之前先测线路**：用厂商提供的 Looking Glass/测试 IP 从你的网络 `ping -n 50 <TEST_IP>` 和 `tracert -d <TEST_IP>`——稳定的 200Mbps 远胜晚高峰严重丢包的"共享 1Gbps"
2. 关注**晚高峰丢包**和**UDP 是否可用**（影响 Hysteria2 备用入口）
3. 确认厂商 AUP 允许个人代理用途

**常见选择**：

| 厂商 | 参考价 | 特点 |
|---|---|---|
| Vultr Tokyo | $6/月 | 按小时计费，不满意随时删 |
| 搬瓦工 | $50/年起 | CN2 GIA 线路好，需抢购 |
| RackNerd | ~$11/年 | 极便宜，性能一般，适合备用 |
| Oracle Cloud Always Free | 0 元 | ARM 4C/24G 免费额度（注册门槛高） |

## 第二步：SSH 引导（由人完成，约 5 分钟）

安全原则（personal-edge-proxy）：**不要把 root 密码给任何工具/聊天**。

```powershell
# 1. 本地生成密钥（如已有可跳过）
ssh-keygen -t ed25519

# 2. 用厂商控制台给的初始密码登录一次，把公钥放进服务器
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@<VPS_IP> "umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys"

# 3. 验证密钥登录成功（这一步之后密码登录可以关，也可以先留着）
ssh root@<VPS_IP>
```

## 第三步：一键部署（把本仓库脚本传上去执行）

```powershell
scp scripts/deploy-vps-xray.sh root@<VPS_IP>:/root/
ssh root@<VPS_IP> "bash /root/deploy-vps-xray.sh"
```

脚本自动完成：时间校准 → BBR 加速 → Xray 官方安装 → UUID/REALITY 密钥自动生成 → 配置 VLESS+REALITY+Vision (TCP 443) → 防火墙放行 → systemd 启动 → **打印客户端 vless:// 链接**。

所有密钥在 VPS 上现生成，只出现在输出里（含隐私，不要外传）。

## 第四步：交给 AI 接入 Clash

把输出的 `vless://` 链接发给 AI（或者只给：服务器 IP、UUID、PUBLIC_KEY、SHORT_ID 四项），AI 会：

1. 在 Clash 新增自建节点（vless + reality + vision）
2. 重组线路结构：自建为主用、机场降级为应急、CF/住宅保持现有角色
3. 端到端验证出口与吞吐
4. 同步本仓库

## 可选升级（档位 C → E，来源 personal-edge-proxy）

| 档位 | 内容 | 解决的问题 |
|---|---|---|
| A | REALITY → VPS Direct | 最小自建可用 |
| C | + AI 域名 → WARP 出口 | AI 与 VPS 机房 IP 解耦 |
| D | + Claude/Anthropic → 固定 SOCKS5（你的 MIYA 即此角色） | 关键服务稳定最终出口 |
| E | + Hysteria2 (UDP 24443) 备用入口 / Cloudflare Tunnel | UDP 受限/入口冗余 |

WARP 出口（服务端）：`warp-svc` 本地 SOCKS5 `127.0.0.1:40000`，Xray 按域名分流把 OpenAI/Gemini 流量从 VPS 原生出口切到 WARP——与你的 MIYA 住宅出口策略互补。

## 安全清单

- SSH 私钥、root 密码、UUID、REALITY 私钥**不进任何仓库/聊天**
- 部署脚本输出含隐私凭据，截图前打码
- 服务器只开 22/443（+可选 UDP 端口），禁用无认证的公共代理
- `fail2ban` 可选加固 SSH

## 成本对比

| 方案 | 月成本 | 稳定性 | 可控性 |
|---|---|---|---|
| 机场（现状主用） | 已付 | ❌ 今天这种大面积故障无法避免 | ❌ 零 |
| **自建 VPS（推荐）** | **$5-11/月** | ✅ 自己控制，REALITY 抗封锁 | ✅ 完全 |
| CF Workers 备用（已部署） | 0 | 免费但 pages.dev 有被重点盯防风险 | 部分 |
| MIYA 住宅（已部署） | 已付 | AI/账号出口稳定 | 部分 |