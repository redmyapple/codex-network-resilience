# 02 · Clash Verge 分流配置策略

> 环境：Clash Verge Rev（Mihomo 内核），本地混合端口 7897，Windows System Proxy。

## 核心架构

```
所有流量 → Clash Verge (127.0.0.1:7897)
  ├─ AI/账号域名 (openai/chatgpt/anthropic/claude/github/google)
  │        → MIYA-STATIC（住宅固定出口，Fail Closed）
  ├─ 流媒体/社交 (x/twitter/youtube)
  │        → AI智能优选（机场，自动选优）
  └─ 其余（MATCH）→ AI智能优选
```

**原则**：AI 出口与机房 IP 解耦；流媒体走快节点；国内直连（GEOIP CN → DIRECT）。

## 关键分组

### AI智能优选（机场，fallback）
```yaml
- name: AI智能优选
  type: fallback
  interval: 300
  url: http://www.gstatic.com/generate_204
  proxies:
    - <节点A>
    - <节点B>
```
- 只放质量达标（可通过 ip-api.com 过滤 + OpenAI 可达）的新/日/韩/美节点
- `fallback` 而非 `url-test`：当前节点**挂了才切**，避免频繁跳车掉线

### MIYA-STATIC（住宅固定出口，Fail Closed）
```yaml
- name: MIYA-STATIC
  type: fallback
  interval: 300
  url: http://www.gstatic.com/generate_204
  proxies:
    - MIYA-Japan-Static       # SOCKS5 首选
    - MIYA-Japan-Static-HTTP  # HTTP 备用
```
- 只含住宅节点 → **Fail Closed**（住宅不可用时请求失败，绝不静默回落到机房 IP）
- SOCKS5 挂了自动切 HTTP，出口仍为住宅

### 住宅节点定义（proxies override）
```yaml
- name: MIYA-Japan-Static
  type: socks5
  server: <MIYAIP_HOST>
  port: <MIYAIP_PORT>
  username: <USERNAME>
  password: <PASSWORD>
  udp: false
- name: MIYA-Japan-Static-HTTP
  type: http
  server: <MIYAIP_HOST>
  port: <MIYAIP_PORT>
  username: <USERNAME>
  password: <PASSWORD>
```

## 分流规则

```yaml
rules:
- DOMAIN-SUFFIX,openai.com,MIYA-STATIC
- DOMAIN-SUFFIX,chatgpt.com,MIYA-STATIC
- DOMAIN-SUFFIX,oaiusercontent.com,MIYA-STATIC
- DOMAIN-SUFFIX,anthropic.com,MIYA-STATIC
- DOMAIN-SUFFIX,claude.ai,MIYA-STATIC
- DOMAIN-SUFFIX,github.com,MIYA-STATIC
- DOMAIN-SUFFIX,google.com,MIYA-STATIC
- DOMAIN-SUFFIX,googleapis.com,MIYA-STATIC
- DOMAIN-SUFFIX,gstatic.com,MIYA-STATIC
- DOMAIN-SUFFIX,googleusercontent.com,MIYA-STATIC
- DOMAIN-SUFFIX,x.com,AI智能优选
- DOMAIN-SUFFIX,twitter.com,AI智能优选
- DOMAIN-SUFFIX,youtube.com,AI智能优选
- DOMAIN-SUFFIX,googlevideo.com,AI智能优选
# ... GEOIP CN DIRECT ...
- MATCH,AI智能优选
```

## 持久化：Clash Verge 的覆盖文件

直接改生成的 `clash-verge.yaml` 会在订阅刷新后被覆盖。**正确做法**是用订阅的扩展覆盖文件：

| 文件（在 `%APPDATA%\io.github.clash-verge-rev...\profiles\`） | 作用 |
|---|---|
| `<profile>.proxies`（如 `pWXpuEzTTsYN.yaml`） | `append` 自定义代理节点 |
| `<profile>.groups`（如 `gRAJqrfpX3EL.yaml`） | `append` 自定义策略组 |
| `<profile>.rules`（如 `rOoDjdzC6WHZ.yaml`） | `prepend/append/delete` 规则 |

示例（proxies 覆盖）：
```yaml
prepend: []
append:
- name: <自定义节点>
  type: socks5
  server: <HOST>
  port: <PORT>
  username: <USERNAME>
  password: <PASSWORD>
delete: []
```

## 通过命名管道操作 Mihomo（无 HTTP controller 时）

Clash Verge 默认关闭 TCP external controller，改用命名管道 `\\.\pipe\verge-mihomo`。

```powershell
# 重载配置
# PUT /configs  body={"path":"<clash-verge.yaml 绝对路径>"}
# 切换模式
# PATCH /configs body={"mode":"rule"}
# 选择组内节点
# PUT /proxies/<URL编码的组名> body={"name":"<节点>"}
```

`secret` 使用 Clash Verge 默认的 `set-your-secret`（可在其内部配置修改）。

## 验证分流是否正确

```powershell
# 走住宅出口的域名（chatgpt.com）应返回住宅 IP
curl.exe -4 -x http://127.0.0.1:7897 https://chatgpt.com/cdn-cgi/trace
# ip= 应为住宅 IP，loc= 应为对应国家

# 未列入的域名走机场
curl.exe -4 -x http://127.0.0.1:7897 https://api.ipify.org
```

## 稳定性加固

### 1. 屏蔽 QUIC（UDP 443 → REJECT）

住宅节点多为 `udp: false`，应用尝试 HTTP/3（QUIC over UDP 443）会失败，等超时后才回退 TCP，造成明显卡顿。直接在规则最前面 REJECT 掉 QUIC，强制走 TCP：

```yaml
rules:
- AND,((NETWORK,udp),(DST-PORT,443)),REJECT   # 必须是第一条规则
- DOMAIN-SUFFIX,openai.com,MIYA-STATIC
...
```

浏览器会自动回退 HTTP/2 over TCP，无感知；代理链路从此不再有 QUIC 失败重试。

### 2. DNS 加固（DoH 优先，明文兜底）

明文 DNS 易被污染。在 `nameserver` 里加入 DoH（国内阿里/腾讯 DoH 可用性好）：

```yaml
dns:
  nameserver:
  - https://223.5.5.5/dns-query     # 阿里 DoH
  - https://doh.pub/dns-query       # 腾讯 DoH
  - 223.5.5.5                        # 明文兜底
  - 119.29.29.29
```

**持久化注意**：Clash Verge 的 DNS 段可能由订阅链生成。为保证刷新订阅后不丢，把 DNS 块写入活动订阅的 **merge 覆盖文件**（如 `mXXXXX.yaml`），而不是只改运行时配置。

### 3. 改配置前自动备份 + 校验（借鉴 ace-vpn）

- 每次修改覆盖文件前先备份原文件（`xxx.yaml.bak-时间戳`）
- 规则写错会导致整条链路瘫痪，mihomo `-t` 校验通过后再 reload
- reload 后立刻用真实流量验证出口 IP（`cdn-cgi/trace`），确认没改坏

## 常见坑

- `mode=global` 会让所有流量走 GLOBAL 组，**规则全部失效**。分流必须用 `rule` 模式。
- 改完覆盖文件后要让 Verge 重新生成运行时配置并 reload，否则不生效。
- `dialer-proxy`（机场前置 → 住宅落地）在当前住宅中转上会 TLS 失败：部分住宅代理商拒绝"再套一层代理到达"的连接。用**分流规则**替代更可靠。