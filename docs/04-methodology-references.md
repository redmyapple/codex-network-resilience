# 04 · 借鉴的项目与方法论

本方案的方法论参考了两个开源项目，并做了"适合本机 Clash 客户端"的落地取舍。

## 1. bannedbook/fanqiang

- 仓库：https://github.com/bannedbook/fanqiang
- 性质：翻墙工具与教程合集（工具、免费账号、各平台教程）

### 借鉴点

| 理念 | 落地 |
|---|---|
| 多节点 + 自动切换保稳定 | 机场 `fallback` 组：当前节点挂了才切，避免掉线 |
| 链式代理 / 落地代理概念 | 尝试"机场前置 + 住宅落地"，但当前住宅中转拒绝被中继访问，改为分流规则替代 |
| 多订阅冗余 | 保留多份订阅作为兜底 |

### 结论
该项目主要是**教程集合**，没有可直接搬用的配置文件；真正有用的是"多节点自动切换 + 落地代理"两个理念。

## 2. yding-git/personal-edge-proxy

- 仓库：https://github.com/yding-git/personal-edge-proxy
- 性质：Xray + Hysteria2 + REALITY + WARP + 固定 SOCKS5 的自建服务器架构

### 借鉴点（已在客户端 Clash 上落地）

| 项目理念 | 含义 | 本机落地 |
|---|---|---|
| **入口冗余** | REALITY / Tunnel 解决"怎么进服务器" | 机场多节点 fallback + 多订阅 |
| **出口分层** | Direct / WARP / Fixed SOCKS5 独立出口 | 机场（一般流量）与住宅（AI/账号）分离 |
| **按域名精确分流** | 不同域名走不同出口 | `openai.com → 住宅`，`youtube.com → 机场` |
| **Fail Closed** | 固定出口不可用 → 请求失败而非静默换出口 | `MIYA-STATIC` 只含住宅节点 |
| **出口独立可测** | 每条出口单独验证 | 用 `/cdn-cgi/trace` 验证住宅出口 IP |

### 结论
该项目核心是自建 VPS 服务端（需要 HY2 / REALITY / WARP 部署），**不能直接搬到"机场 + 住宅"的客户端架构**。但它提出的 **Fail Closed** 与 **出口分层** 设计思想，可以在 Clash 侧通过分组 + 分流规则完全实现。

## 3. OpenRung（openrung/openrung）

- 仓库：https://github.com/openrung/openrung
- 性质：志愿者运营的 VLESS+REALITY+Vision 中继网络（Snowflake 思路的全设备隧道版）

### 借鉴点

| 项目理念 | 含义 | 对本方案的意义 |
|---|---|---|
| **中转与落地分离** | 中转节点在资源丰富地区保证速度，落地节点在干净 IP 地区保证纯净 | 验证了"机场前置 + 住宅落地"方向的正确性；但部分住宅中转拒绝被中继访问，落地方式需按服务商实测 |
| **按健康度选路** | Broker 按连接成功率/延迟/测速对中继排序，把用户导向"真正能用"的节点 | 等价于我们的 `filter-best-node.ps1`（ip-api 纯净度 + OpenAI 可达 + 延迟筛选） |
| **Fail Closed** | Broker 无共享 token 拒绝启动 | 与我们住宅组 Fail Closed 同源思想 |
| **直连优先 + 回退** | 直连 REALITY 失败时走签名 WSS/CDN 前置 | 客户端侧等价物：多订阅/多节点冗余 + fallback 自动切换 |
| **控制面与数据面分离** | Broker 只做匹配，不碰用户流量 | 排障时区分"选路问题"与"链路问题" |

## 4. xiaonancs/ace-vpn（同架构：Clash Verge Rev + Mihomo）

- 仓库：https://github.com/xiaonancs/ace-vpn

### 借鉴点

| 项目理念 | 落地方式 |
|---|---|
| **规则写入前 pre-flight 校验** | 坏规则永不进 override；本方案用 `mihomo -t` 校验通过再 reload |
| **改配置前自动备份** | 每次改覆盖文件先 `.bak-时间戳` |
| **本地规则池** | 日常临时规则本机秒级生效，攒后批量提升 |
| **真实配置与公开仓库分离** | 含凭据的配置放私有仓库，公开仓库只放模板 —— 本仓库同理，全占位符 |

## 5. seb0ch/vpn（DNS 加固）

- 仓库：https://github.com/seb0ch/vpn
- 借鉴点：**强制加密 DNS**（所有 53 端口流量 DNAT 到 dnscrypt-proxy / DoH）。客户端侧落地：`nameserver` 优先 DoH（阿里/腾讯），明文 DNS 兜底，防污染防劫持。

## 6. superchaospc/reality-wireguard-relay（两跳中转+落地）

- 仓库：https://github.com/superchaospc/reality-wireguard-relay
- 架构：客户端 → VLESS-XHTTP-REALITY 中转 VPS → WireGuard → 落地 VPS（SNAT 出网），**出口 IP = 落地机**
- 借鉴点：分阶段构建 + 每阶段验证（`verify_egress.py` 绑定源 IP 确认实际出口）。需要自有 VPS，当前不适用；但"出口 IP = 落地机"与我们的住宅落地目标完全一致。

## 7. cmliu/edgetunnel（CF Workers/Pages 免费备用线路）

- 仓库：https://github.com/cmliu/edgetunnel（44k+ star）
- 架构：VLESS/Trojan/SS 跑在 CF Workers/Pages 上，内置管理面板、订阅生成、ProxyIP/SOCKS5 反代、优选订阅生成器

### 借鉴点

| 理念 | 含义 | 适用性 |
|---|---|---|
| **永远不要只准备一套线路** | 机场（主）+ CF 免费节点（备）+ 住宅（AI 落地）三层，故障模式互相独立 | 三层架构设计的核心论据 |
| **入口冗余** | workers.dev / pages.dev / 自定义域 多入口 | 自定义域必须（默认域名在大陆被污染） |
| **优选订阅生成器**（BEST_SUB） | 自动生成优选 IP 订阅 | 需先验证本地到 CF 的真实连通性（见下） |
| **PROXYIP / SOCKS5 反代** | 解决 CF 回源限制 | 服务端能力，客户端无需关心 |

### ⚠️ 实测修正：入口可达性取决于 SNI 域名，而非 CF IP

实测某企业网络：防火墙做 **SNI/域名黑名单**拦截（机场域名被拉黑），CF IP 段本身完全可达（同 IP 换成 `www.cloudflare.com` SNI 即通，无名个人域名在 CF 上也直连正常）。因此：

- edgetunnel 部署在**自己的新域名**上时，企业网络下**同样可用**（域名不在黑名单）
- 部署后必须端到端验证（真实流量穿过节点查出口 IP），并留意流量特征长期是否触发域名进入黑名单
- 优选 IP 只对「SNI 未被拉黑」的节点有效

## 7. Johnshall/Shadowrocket-ADBlock-Rules-Forever（去广告规则聚合）

- 仓库：https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever（29.7k star）
- 性质：Shadowrocket 格式规则合集，每日自动构建，聚合 GFWList + EasyList China + 乘风规则 + Peter Lowe + blackmatrix7

### 借鉴点

| 理念 | 落地 |
|---|---|
| **去广告聚合**（EasyList China + 乘风 + Peter Lowe 同源数据） | mihomo 一行规则 `GEOSITE,category-ads-all,REJECT` 读取本地 geosite.dat 内置同源分类，零外部依赖 |
| 黑名单/白名单两种分流思路 | 用户已是混合式（已知 AI→住宅、流媒体→机场、CN→直连、未知→代理） |
| 「规则行数不影响速度」 | 规则加载时构建 DFA + 哈希缓存，O(1)——放心加规则 |
| 规则每日自动更新 | geosite.dat 由 Clash Verge 维护更新；远程 rule-provider 可配 interval 自动更新 |

## 抽象出的通用方法论

```
1. 分清「入口」与「出口」：
     入口问题 → 换协议/换节点/换入口（机场、自建、隧道）
     出口问题 → 换出口策略（机房 IP、WARP、住宅 IP）
2. 关键服务固定出口：
     住宅/ISP IP 信誉最好，优先给 AI / 账号类服务
3. 固定出口必须 Fail Closed：
     住宅挂了就失败，绝不静默回落成机房 IP
4. 精确分流，不全局代理：
     住宅管 AI/账号，机场管流媒体，国内直连
5. 一切可验证：
     每个出口用独立的 IP 查询 / cdn-cgi/trace 验证
```

## 参考链接

- bannedbook/fanqiang：https://github.com/bannedbook/fanqiang
- yding-git/personal-edge-proxy：https://github.com/yding-git/personal-edge-proxy
- ip-api.com：https://ip-api.com