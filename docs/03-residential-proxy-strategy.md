# 03 · 住宅代理固定出口策略

> 目标：让 AI / GPT / 账号类服务走"干净的住宅 IP"出口，避开机房 IP 封锁与风控，同时不影响流媒体速度。

## 为什么需要住宅出口

机场节点绝大多数是**机房/数据中心 IP**（`hosting=true`），部分还被标记 `proxy=true`。对 AI 服务、账号登录这类场景，机房 IP 信誉往往更差，更容易遇到：地区不可用、验证码、风控提示等。

住宅/ISP IP（`proxy=false` + `hosting=false`）信誉通常更好，适合固定给关键服务使用。

## 如何判断一个出口 IP 的"纯净度"

用免费的 `ip-api.com` 交叉核验（无需 key）：

```powershell
curl.exe -x http://127.0.0.1:7897 -G --data-urlencode "fields=status,query,country,isp,as,mobile,proxy,hosting" "http://ip-api.com/json/"
```

| 字段 | 纯净住宅 | 机房 |
|---|---|---|
| `proxy` | `false` | 多为 `true` |
| `hosting` | `false` | `true` |
| `as/isp` | 当地运营商（如 TIS Inc.） | AWS / GSL / 云厂商 |

再配合多个 IP 服务交叉验证：`api.ipify.org`、`ipinfo.io/ip`、`ifconfig.me/ip`。

## 住宅代理的获取方式

| 方式 | 说明 | 成本 |
|---|---|---|
| 机场自带住宅/原生节点 | 订阅里标注"住宅IP/原生IP/家宽"的节点 | 低 |
| 住宅代理服务商 | Bright Data / Oxylabs / Smartproxy / IPRoyal / Webshare / Soax 等，提供 HTTP/SOCKS5 | 按量/按月 |
| 自建住宅 | 海外家宽/手机热点搭 v2ray | 高门槛 |

> 本项目以 **MIYAIP 静态住宅 IP** 为例（HTTP / SOCKS5 中转 `<MIYAIP_HOST>`）。所有真实凭据用占位符替代。

## 配置要点

### 1. SOCKS5 优先，HTTP 备用
实测同网络中 SOCKS5 延迟通常更低，故作为 fallback 组首选；HTTP 作为备用入口，主入口失效时自动顶上。

### 2. Fail Closed
住宅组（如 `MIYA-STATIC`）**只放住宅节点**，不要放机场作为回退。这样住宅不可用时请求失败，而不是悄悄换成本机 IP / 机房 IP 泄露出口身份。

### 3. 健康检查
`fallback` 组 + `interval` + `url`，每 300s 探测一次，主节点失效自动切换。

### 4. 按域名精确分流
只把需要固定出口的服务（AI/账号）路由到住宅，其余走机场，避免拖慢大流量场景。

## 出口链路（最终形态）

```
Client → Clash(7897) → [openai/chatgpt/...] → MIYA-STATIC → <MIYAIP_HOST>:8001 → <住宅IP>（住宅）
                          [x/youtube/...]     → AI智能优选   → 机场节点            → 机房 IP
```

## 验证命令

```powershell
# 住宅出口确认（chatgpt.com 在住宅规则里）
curl.exe -4 -x http://127.0.0.1:7897 https://chatgpt.com/cdn-cgi/trace
# → ip=<住宅IP>  loc=JP

# 非住宅域名走机场
curl.exe -4 -x http://127.0.0.1:7897 https://api.ipify.org

# 纯净度核验
curl.exe -x http://127.0.0.1:7897 -G --data-urlencode "fields=proxy,hosting,isp,as" "http://ip-api.com/json/"
```

## 安全注意

- 住宅代理的账号密码只写入本机 Clash 私有配置，**不要提交到仓库 / 聊天 / 日志**
- 仓库内一律用 `<USERNAME>` / `<PASSWORD>` / `<HOST>` 占位符
- 密码一旦泄露（如出现在截图），及时到服务商后台重置