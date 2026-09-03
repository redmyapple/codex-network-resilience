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

### 4. 优选 IP 的「假延迟陷阱」（企业网络必读）

CF 中转节点（`server` 为 CF 域名/优选 IP）可以做「优选 IP」提速：用 CloudflareSpeedTest 测出本地延迟最低的 CF Anycast IP，替换节点的 `server`，保持 `SNI/Host` 不变。

**但某些企业网络/防火墙会对境外 IP 段做 TCP SYN 本地代答**——表现为测速延迟极低（如 2.5ms），实际 TLS 握手根本完成不了。**直接按测速结果配置会全部失效。**

正确的验证流程：

```powershell
# 1. 测速（直连环境，务必临时切 global+DIRECT 排除代理干扰）
.\cfst.exe -tl 250 -dn 5 -p 10 -o result.csv

# 2. 关键一步：验证优选 IP 能否真正完成 TLS 握手
#    用 --resolve 强制连优选 IP，SNI 用节点真实域名
curl.exe -4 -v --resolve "<节点域名>:443:<优选IP>" "https://<节点域名>/" -o NUL
#    看到证书/HTTP 响应 = 真可用；schannel handshake failed = 防火墙代答的假延迟
```

**企业网络实测案例（重要修正）**：某企业网络直连 CF IP 段时，**SNI 为机场域名（已知代理域名）的 TLS 会被拦截，但 SNI 为 `www.cloudflare.com` 或无名个人域名的 TLS 完全正常**——即防火墙做的是 **SNI/域名黑名单**，不是封 CF IP 段。推论：
- 优选 IP 对「SNI 被拉黑的节点」无效（换 IP 没用，ClientHello 里的 SNI 一样被掐）
- CF Workers/Pages 备用线路（edgetunnel 等）部署在**自己的新域名**上时，通常不在黑名单内 → **企业网络下也可用**
- 部署后务必端到端验证：真实流量穿过节点查询出口 IP

## 多线路冗余（备用线路层）

「永远不要只准备一套线路」——在机场之外，用 **Cloudflare Workers/Pages 免费节点**（edgetunnel）做备用线路，故障模式与机场完全独立。

### 三层架构

```yaml
# 出口分层（rules 顺序即优先级）
- openai/chatgpt/anthropic/claude/github/google → MIYA-STATIC   # 住宅固定出口
- x/twitter/youtube/一般流量                     → 线路冗余      # 自动互备
- GEOIP CN → DIRECT

# 线路冗余组：机场全挂时自动切 CF 节点
- name: 线路冗余
  type: fallback
  interval: 300
  url: http://www.gstatic.com/generate_204
  proxies:
  - AI智能优选        # 机场（组引用）
  - CF备用节点        # CF Workers/Pages 免费节点
```

### CF 节点模板（edgetunnel 部署后）

```yaml
- name: CF备用节点
  type: vless
  server: <你的项目>.pages.dev
  port: 443
  uuid: <UUID>
  udp: false
  tls: true
  servername: <你的项目>.pages.dev
  client-fingerprint: chrome
  network: ws
  ws-opts:
    path: /?ed=2560
    headers:
      Host: <你的项目>.pages.dev
```

### 无头部署（Wrangler CLI，免网页操作）

```powershell
# 1. 授权（弹浏览器点 Allow）
npx wrangler login

# 2. 创建 KV 命名空间
npx wrangler kv namespace create KV

# 3. 创建 Pages 项目
npx wrangler pages project create <项目名> --production-branch=main

# 4. 部署目录放 _worker.js + wrangler.toml：
#    name/pages_build_output_dir/kv_namespaces/[vars] ADMIN、UUID
npx wrangler pages deploy . --project-name=<项目名> --branch=main
```

凭据（ADMIN/UUID）保存在本机私有文件，不进仓库。部署后验证：`curl -x <clash> https://<项目>.pages.dev/` 应 200。

### ⚠️ wrangler 非交互环境认证坑

`wrangler login` 的 OAuth token 存在 `%APPDATA%\xdg.config\.wrangler\config\default.toml`，但部分子命令在非交互环境读不到它（报"需要 CLOUDFLARE_API_TOKEN"）。修复：从该文件提取 `oauth_token` 注入环境变量：

```powershell
$tok = (Select-String -Path "$env:APPDATA\xdg.config\.wrangler\config\default.toml" -Pattern 'oauth_token\s*=\s*"([^"]+)"').Matches[0].Groups[1].Value
$env:CLOUDFLARE_API_TOKEN = $tok
```

### ⚠️ wrangler 非交互环境认证坑（实测）

1. **OAuth token 不能直接当 API Bearer 用**：从配置文件提取 `oauth_token` 直接调 CF API 会报 `9109 Invalid access token`——它只供 wrangler 内部使用。需要调 API 时，去 dashboard 创建真正的 API Token。
2. **配置文件双路径坑**：`wrangler login` 写入的位置取决于环境变量——可能是 `%USERPROFILE%\.wrangler\config\default.toml` 或 `%APPDATA%\xdg.config\.wrangler\config\default.toml`。提取 token 前先确认哪个是**新写入的**（按 mtime 判断），否则会拿到过期 token。
3. **OAuth token 约 1-2 小时过期**（有 refresh_token，wrangler 会自动续期；但长期未用会失效需重新 login）。

### ⚠️ Pages 自定义域 DNS 记录需手动创建

通过 API `POST /accounts/{id}/pages/projects/{project}/domains` 绑定自定义域后，域名状态为 `pending`，**CF 不会自动创建 DNS 记录**（即使 zone 在同一账号）。需手动添加：
- `CNAME <子域> → <项目名>.pages.dev`（开启代理/橙云）
- 之后 CF 自动完成 HTTP 验证并签发证书（1-2 分钟）

### ⚠️ Worker 冷启动

首次请求可能失败或超时（Worker 冷启动 + TLS 建连），重试即恢复。给备用线路的监控/测试逻辑加一次重试。

### 4. 全局去广告（一行规则，零维护）

广告流量白白消耗带宽和代理流量。mihomo 的 `geosite.dat`（MetaCubeX 构建）内置 `category-ads-all` 广告域名分类（聚合 EasyList China、乘风规则、Peter Lowe 等同源数据，与 Shadowrocket-ADBlock-Rules-Forever 的去广告策略同源），一行规则开启全局去广告：

```yaml
rules:
- GEOSITE,category-ads-all,REJECT   # 放在规则最前面
```

- 零外部依赖：直接读本地 geosite.dat，无需远程 rule-provider
- 验证：广告域名（如 googleads.g.doubleclick.net）应立即被 REJECT，正常流量不受影响
- 补充知识点：规则行数不影响匹配速度（规则加载时构建 DFA 搜索树 + 哈希缓存，O(1)）

### 5. 机场故障日的应急响应（假活节点甄别 + fixed 钉住）

实测案例：机场大面积故障时，**延迟/健康检查全部通过 ≠ 数据通路正常**——11 个池节点 10 个"gstatic 204 探测通过"，但 8MB 下载吞吐全部为 0（TCP 小包能通、持续数据流被断，典型拥塞/线路劣化特征）。

**应急流程**：

```powershell
# 1. 组测速 API 一次测完整组（mihomo 特性，并行测全部成员）
GET /group/<URL编码组名>/delay?timeout=4000&url=<探测URL>
#    → 返回 {节点: 延迟} 映射，超时节点不出现

# 2. 对存活节点逐个做吞吐实测（延迟通过 ≠ 吞吐正常！）
curl.exe -x http://127.0.0.1:7897 -o NUL -w "%{speed_download}" "https://speed.cloudflare.com/__down?bytes=8000000"

# 3. 把真实吞吐最高的节点排到池首位（覆盖文件 + 运行时都要改）

# 4. fallback 组可用 PUT 钉住节点（mihomo 1.19+ 的 fixed 特性）
PUT /proxies/<组名>  body={"name":"<节点名>"}
#    → 组的 "fixed" 字段生效，绕过自动选择直接用该节点
#    注意：fixed 钉住后该组不再自动切换，机场恢复后记得清除（重新 PUT 或 GUI 取消）
```

**诊断陷阱**：企业防火墙/拥塞线路会造成「TCP 握手极低延迟 + 健康检查通过」的假活节点，小包探测全部通过但吞吐为零。**延迟筛选必须配合吞吐实测才是完整结论。**

## 常见坑

- `mode=global` 会让所有流量走 GLOBAL 组，**规则全部失效**。分流必须用 `rule` 模式。
- 改完覆盖文件后要让 Verge 重新生成运行时配置并 reload，否则不生效。
- `dialer-proxy`（机场前置 → 住宅落地）在当前住宅中转上会 TLS 失败：部分住宅代理商拒绝"再套一层代理到达"的连接。用**分流规则**替代更可靠。