# 10 · 交接给 Codex（项目总结 + 未完成工作）

> 给下一个 Agent 的任务单。先读本文，再读仓库根目录 `HANDOFF.md`（gitignore，含本机路径和最近一次验收 IP）。  
> 策略手册：`d:\网络策略\vps-resi-node-playbook.md`。  
> 整理日期：2026-09-10。

---

## 给 Codex 的一句话任务

在**不改方案、不提交凭据**的前提下，把手册 **方案 C + D** 的剩余项做完并验收。  
不要做成方案 A（VPS 出站再链住宅 SOCKS），除非用户明确同意，并且已经证实该住宅允许从机房 IP 接入。

---

## 1. 这是什么项目

仓库：`redmyapple/codex-network-resilience`  
工作区：`C:\Users\junl3\codex-network-resilience`

这不是业务代码仓库，是一份 **Windows 上让 CodeX / ChatGPT 稳定工作的网络方法论**：

1. 排查 CodeX 连不上（本地中转、端口写错、第三方工具劫持 `.env` / `config.toml` / `auth.json`）。
2. 用 Clash Verge（Mihomo）做规则分流。
3. **AI / 登录 / 风控敏感站**走固定日本静态住宅（Fail Closed）。
4. **一般流量 / 下载 / TG / Discord**走自建东京 VPS，挂了再降级机场、再降级 Cloudflare 备用。
5. 国内直连。三层线路故障域互相独立。

同步命令（用户本机）：`powershell -NoProfile -ExecutionPolicy Bypass -File sync.ps1`  
只入库可复用方法论 / 模板 / 脚本。一次性 IP、节点选择、凭据不要进 Git。

---

## 2. 已定方案（不要改回去）

手册默认「有 VPS + 住宅 → 方案 A+D」。**本机住宅不是整机 VDS，只有 SOCKS5/HTTP 账号**，落地机上装不了 sing-box。因此实际落地是：

| 方案 | 是否采用 | 原因 |
|---|---|---|
| A 两机链式（VPS 出站 dial 住宅机） | 否 | 没有第二台整机；此前 `dialer-proxy` 再套一层会 TLS 失败（部分住宅商拒绝「代理再套代理」） |
| B 只在住宅机上入站 | 否 | 没有住宅整机 |
| **C** VPS 入站 Reality + 客户端分流 | **是** | 自建只负责一般流量加速 |
| **D** 双出口分流 | **是** | AI/X/Google/Netflix 走住宅；TG/Discord/下载走机房 |

**硬约束（违反即做错）：**

- 不要把住宅失败切到 VPS，也不要把 VPS 失败切到住宅。
- `MIYA-STATIC` 组里只能有住宅节点（Fail Closed）。
- `线路冗余` 组里只能有：自建 VPS → 机场优选组 → CF 备用。不要塞住宅。
- Clash 必须是 `mode: rule`。`global` 会让规则全失效，mixed-port 表现成 502。
- 密钥、UUID、订阅 URL、真实服务器 IP、MIYA 账密、`auth.json`、Clash 运行时 yaml **禁止写入仓库、禁止写进聊天回复**。用占位符。

---

## 3. 当前四层角色（已部署）

```
Windows 应用 / CodeX / Chrome
        │
        ▼
Clash Verge Rev  mixed-port 127.0.0.1:7897  mode=rule  TUN 开
        │
        ├─ openai/chatgpt/claude/github/google/x/twitter/netflix
        │     → MIYA-STATIC（仅 SOCKS5 + HTTP 住宅，Fail Closed）
        │
        ├─ telegram / discord / youtube / MATCH
        │     → 线路冗余：SelfHost-TKY-BGP → AI智能优选 → CF备用-JP
        │
        └─ GEOIP CN / 国内域名 → DIRECT
```

| 角色 | 实现 | 状态 |
|---|---|---|
| 中转 VPS | VMISS 东京 BGP，AlmaLinux 9，1C/1G，SSH 22，Xray VLESS+REALITY+Vision TCP 443，SNI/dest=`www.apple.com.cn` | 已部署，ICMP 会抖（丢包 0–25%） |
| 住宅落地 | MIYA 静态 SOCKS5/HTTP，`udp: false` | 已接入 Clash，ChatGPT 实测走住宅 |
| CF 备用 | `CF备用-JP`，vless+ws+tls | 已在覆盖层 |
| 机场 | Clash 订阅「良心云」，组名 `AI智能优选` | 已在，作第三层 |
| 客户端主 | Clash Verge Rev，`D:\Clash Verge\clash-verge.exe` | 主用 |
| 客户端备 | NekoBox（见 `docs/05`） | 文档有，不是当前主路径 |

自建节点名：`SelfHost-TKY-BGP`（reality + vision）。  
VPS 出站仍是 **freedom（机房 IP）**，没有链到住宅。这是方案 C 的正确形态。

---

## 4. 本机路径（改配置只改覆盖层）

Clash 数据目录：

`%APPDATA%\io.github.clash-verge-rev.clash-verge-rev\`

当前档案 UID：`R4P1fpzcbWlO`（良心云）。

| 覆盖文件 | 作用 | 已按 C+D 改过 |
|---|---|---|
| `profiles\pWXpuEzTTsYN.yaml` | 追加节点：MIYA 双协议、CF备用-JP、SelfHost-TKY-BGP | 是 |
| `profiles\gRAJqrfpX3EL.yaml` | 策略组：`MIYA-STATIC` / `线路冗余` / `AI智能优选`；健康检查 interval **120** | 是 |
| `profiles\rOoDjdzC6WHZ.yaml` | 规则 prepend：广告 REJECT、UDP 443 QUIC REJECT、住宅域、线路冗余域、MATCH | 是 |
| `profiles\mS4AB4img2oz.yaml` | merge/DNS：ipv6 false、阿里/DNSPOD DoH + 明文底、fallback 1.1.1.1/8.8.8.8 + CN geoip | 部分（缺国外 DoH detour） |

运行时（会被 Verge 从覆盖层重新生成，不要只改这里）：

- `clash-verge.yaml`
- `clash-verge-check.yaml`
- `config.yaml`（重启后可能把 `mode` 写回 `global`）

API：默认没有 TCP 9097，用命名管道 `\\.\pipe\verge-mihomo`，secret `set-your-secret`。  
`PUT /proxies/...` 经常卡住或 `ReadFile 管道已结束`。**改分组更稳的做法：改覆盖 yaml → 重启 Clash Verge → 确认 7897 起来。**

三处都必须是 `mode: rule`：GUI、`clash-verge.yaml`、`config.yaml`。

---

## 5. 已完成（不要重复做）

- SSH 公钥免密。AlmaLinux 默认 `PubkeyAuthentication no`；`AuthenticationMethods publickey,password`（逗号）= 必须两个都过。已改成空格 OR：`publickey password`。sshd **先出现的值生效**。详见 `docs/06`。
- `scripts/deploy-vps-xray.sh` 已兼容 AlmaLinux（dnf / firewalld / SELinux Permissive）。VPS 上 Xray 已跑，听 `*:443`。
- Clash 已写入自建节点和 C+D 规则（覆盖层 + 运行时曾确认带上 x.com/twitter/netflix → MIYA，telegram/discord/youtube → 线路冗余）。
- 健康检查 300s → 120s。
- 仓库文档 `docs/01`–`09`、部署脚本、节点筛选脚本已在；最近一次 push：`5f88e97 sync: 2026-09-10 10:32`。

**最近一次分流实测（2026-09-10 晚，rule 模式）：**

- ChatGPT `cdn-cgi/trace` → 日本住宅（符合 D）。
- 一般 `api.ipify.org` → 机场 IP（说明当时自建 204 没过，`线路冗余` fallback 在干活，**不是**住宅，符合 C）。
- 不要用「TCP SYN 到 443 只有几毫秒」当质量：TUN/防火墙会代答。要用直连 TLS 握手或真实 204/下载。

凭据位置（**读来用，不要复制进 Git / 聊天**）：

- Clash 覆盖 yaml（MIYA 用户名密码、CF UUID、SelfHost UUID）
- VPS：`/usr/local/etc/xray/config.json`（含 REALITY 私钥）
- 本机 SSH：`%USERPROFILE%\.ssh\id_ed25519`
- 不要把 root 密码、vless 链接写进仓库

---

## 6. 未完成工作（按优先级做）

### P0 · 验收必须先过（每次改 Clash 后）

在 **rule** 模式下，`curl -4 -x http://127.0.0.1:7897`：

| 探测 | 期望 |
|---|---|
| `https://chatgpt.com/cdn-cgi/trace` | `ip=` 为静态住宅，`loc=JP`；**禁止**变成 VPS 机房 IP |
| 访问 x.com / twitter 相关（可用 Clash 连接日志确认规则命中 `MIYA-STATIC`） | 住宅，Fail Closed |
| `https://api.ipify.org`（MATCH） | 自建 VPS 公网 IP；若自建 204 失败，允许机场或 CF，**禁止**住宅 |
| 百度 / 国内站 | DIRECT，不走代理 |
| `config.yaml` + `clash-verge.yaml` + GUI | 都是 `rule`，TUN 按用户当前选择，不要擅自关 |

若覆盖改了但运行时没跟上：重启 `D:\Clash Verge\clash-verge.exe`，等到 7897 监听。`verge-mihomo` 有时死掉只剩 GUI，同样重启。

### P1 · 手册还没落地的项

1. **DNS detour（手册 §4.3）**  
   国外域名的 DoH 应 detour 走代理，国内 DNS 直连，`ipv4_only`，防泄漏。现在 merge 里只有国内 DoH + fallback 1.1.1.1/8.8.8.8，**没有** nameserver-policy / detour。改 `mS4AB4img2oz.yaml`，不要只改运行时。

2. **Hysteria2（可选，弱网）**  
   VPS ICMP 丢包会到 10–25%。手册说 Hy2 与 Reality **并行**，不替代。先测 VPS **UDP 是否通**，不通就不要开。开了以后客户端做 urltest/failover，仍不要把住宅塞进该组。

3. **VPS 加固（手册 Phase 1 剩余）**  
   非 root 用户 + 仅密钥登录；关密码登录需用户同意。firewalld 只放 22/443（+ 可选 Hy2 UDP）。已有 BBR、SELinux Permissive。

4. **SNI**  
   现用 `www.apple.com.cn`。若 Reality 经常握手失败，再换「真实可访问、证书匹配、不是烂大街」的目标。先换 SNI 再换协议。

5. **手册方案 A 全链**  
   默认不做。若用户坚持：先从 VPS 直连测住宅 SOCKS 能否接通；失败则停止，继续 C+D。

### P2 · 仓库文档落后于本机配置（值得入库）

按 `AGENTS.md` 更新，**全部用占位符**：

- `docs/02`：规则表仍写 x/twitter → 机场；应改为 AI/X/Google/Netflix → `MIYA-STATIC`，TG/Discord/YouTube/MATCH → `线路冗余`（自建 → 机场 → CF）。interval 示例 300 → 120。补 `mode=global` 回写 502、命名管道不可靠、覆盖层文件名。
- `README.md` 架构图同样过时（x/twitter 还指向机场）。
- `docs/03` 路径示意图同步。
- `docs/06` AlmaLinux sshd 坑已有；可补「方案 C 已落地、出站仍是 freedom」。
- 提交前自查无真实 IP/密码/订阅。

### P3 · 不要做的

- 不把机房 IP 当 ChatGPT/X 出口。
- 不写「TCP 神优化」脚本。
- 不把证书/私钥/订阅发到公开聊天。
- 不在仓库目录跑 wrangler 还不 gitignore 缓存。
- 不 `git commit` 除非用户明确要求；用户要同步时用 `sync.ps1`。
- 不 force push、不改 git config。

---

## 7. 关键排障（做过，会再遇到）

| 现象 | 原因 | 处理 |
|---|---|---|
| mixed-port 502、规则全无 | `mode: global` | 三处改回 `rule`，重启 Verge |
| 覆盖改了不生效 | 运行时未重生 | 重启 Clash Verge |
| 管道 API 卡住 | Verge 默认关 TCP controller | 改 yaml + 重启，少依赖 PUT |
| SYN 443 只有 1–22ms | TUN/防火墙代答 | 用 TLS 握手 / 真实 HTTP 测 |
| 一般出口变成 Cloudflare `104.28.x` | 线路冗余落到 CF/WARP | 可接受作备用；AI 仍须住宅 |
| ChatGPT 出口变成 VPS | 规则或组配错 | 立刻修，属于事故 |
| AlmaLinux 有密钥仍要密码 | sshd `PubkeyAuthentication no` 或逗号 AND | 见 `docs/06` |
| `verge-mihomo` 没了只剩 GUI | 内核挂了 | 重启 `clash-verge.exe` |

CodeX 自身连不上：先看 `docs/01`（`.codex/.env` 端口必须是 7897，不要指向已死的本地中转）。

---

## 8. 验收标准（手册 §6，按 C+D 解释）

手册原文「出口 IP = 静态住宅」指的是 **AI/X 等方案 D 流量**，不是 MATCH 全局。本机正确验收：

- [ ] ChatGPT / X 出口 = 静态住宅，且稳定不变
- [ ] 国内站不绕代理
- [ ] 一般流量优先自建；自建挂了能自动到机场或 CF（至少一条备用可工作）
- [ ] 住宅挂了时 AI 请求失败，而不是静默变成机房 IP
- [ ] DNS 无泄漏（P1 做完后做 dnsleaktest）
- [ ] 仓库无凭据

---

## 9. 建议执行顺序

1. 读 `HANDOFF.md`（若存在）拿本机 IP / SSH 目标，**不要把其中 IP 写进将要 commit 的文件**。
2. 确认 Clash `rule` + 7897，跑 P0 四条 curl。
3. 做 P1 DNS detour → 再验收。
4. 测 UDP；通再考虑 Hy2。
5. 用户同意后再做 SSH 关密码 / 非 root。
6. 同步 `docs/02`、`README` 架构图（P2）。
7. 用占位符提交；`git status` 确认没暂存 Clash yaml / `.wrangler` / `HANDOFF.md`。

---

## 10. 仓库地图

```
README.md          项目说明（架构图待与 C+D 对齐）
AGENTS.md          入库规则 + 安全红线
docs/01            CodeX 连不上排查
docs/02            Clash 分组/规则/覆盖/管道 API
docs/03            住宅 Fail Closed
docs/04            借鉴项目
docs/05            NekoBox 备用客户端
docs/06            自建 VPS 路线图 + AlmaLinux sshd
docs/07            廉价 VPS 调研
docs/08            客户端矩阵与应急
docs/09            封锁原理与冷启动
docs/10            本文
scripts/deploy-vps-xray.sh     一键 Xray REALITY
scripts/filter-best-node.ps1   机场节点质量筛选
sync.ps1           add + commit + push
```
