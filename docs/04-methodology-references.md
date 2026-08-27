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