# 04 · 借鉴的项目与方法论

本方案参考多个开源项目，并做了"适合本机 Clash 客户端、住宅与 VPS 出口严格隔离"的落地取舍。项目链接与可用性按 2026-09-10 复核；星标数等易变信息不写入文档。

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

## 2. 手册中的 VPS + 住宅历史参考

- 手册曾引用：https://github.com/yding-git/personal-edge-proxy
- 性质：Xray + Hysteria2 + REALITY + WARP + 固定 SOCKS5 的自建服务器架构

> 复核备注：截至 2026-09-10，该仓库路径通过 GitHub API 返回 Not Found，因此这里只保留手册中的历史设计线索，不把它当作当前可验证的上游实现。

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

## 7. zizifn/edgetunnel（CF Workers/Pages 免费备用线路）

- 仓库：https://github.com/zizifn/edgetunnel
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

## 8. Johnshall/Shadowrocket-ADBlock-Rules-Forever（去广告规则聚合）

- 仓库：https://github.com/Johnshall/Shadowrocket-ADBlock-Rules-Forever（29.7k star）
- 性质：Shadowrocket 格式规则合集，每日自动构建，聚合 GFWList + EasyList China + 乘风规则 + Peter Lowe + blackmatrix7

### 借鉴点

| 理念 | 落地 |
|---|---|
| **去广告聚合**（EasyList China + 乘风 + Peter Lowe 同源数据） | mihomo 一行规则 `GEOSITE,category-ads-all,REJECT` 读取本地 geosite.dat 内置同源分类，零外部依赖 |
| 黑名单/白名单两种分流思路 | 用户已是混合式（已知 AI→住宅、流媒体→机场、CN→直连、未知→代理） |
| 「规则行数不影响速度」 | 规则加载时构建 DFA + 哈希缓存，O(1)——放心加规则 |
| 规则每日自动更新 | geosite.dat 由 Clash Verge 维护更新；远程 rule-provider 可配 interval 自动更新 |

## 9. hoochanlon/fq-book（封锁原理与冷启动方法论）

- 仓库：https://github.com/hoochanlon/fq-book（4.4k+ star，2026-09 仍活跃）
- 性质：《这本书能让你连接互联网》——GFW 封锁原理、代理/VPN 原理科普、工具获取方法论的 docsify 在线书

### 借鉴点

| 项目理念 | 含义 | 本仓库落地 |
|---|---|---|
| **封锁手段分类学** | 关键字过滤/IP 封锁/端口封锁/SSL 阻断/DNS 污染/TCP 回程阻断六类 | docs/09 速查表：症状 → 甄别 → 对策，接入 docs/01 排查流 |
| **TCP 回程阻断判别** | Ping 通 + TCPing 不通 = IP 被墙（99% 定性） | docs/06 VPS 被墙速判（`Test-NetConnection`），自建运维必备 |
| **冷启动方法论** | "记住通道而不是站点"——邮箱自动回复/GitHub 检索/P2P/社工等 8 条获取通道 | docs/09 冷启动预案：全线路瘫痪时的重新起步 |
| **DNS 污染症状学** | `NET::ERR_CERT_AUTHORITY_INVALID` = ISP 假证书 | docs/09 DNS/hosts 抗污染要点 |
| **安全警示** | 异常卡顿站=挖矿；未加密压缩包可被深度检测 | 已并入 docs/09 预案警示 |

### 结论
该项目是**理论与方法论来源**，不提供配置文件；与 bannedbook/fanqiang（工具教程合集）互补——一个讲"为什么会被断、怎么重新开始"，一个讲"用什么工具"。

## 10. GitHub 项目复核：对当前 C+D 最有价值的借鉴

下面是与“VPS 自建线路 + 静态住宅出口”最相关、且当前仍能直接访问的项目。它们分别解决客户端核心、服务端协议、CF 备用或运维问题，没有一个可以在未获住宅服务商许可时自动把 VPS 变成住宅出口。

| 项目 | 可借鉴实现 | 当前取舍 |
|---|---|---|
| [MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo) | `nameserver-policy`、`respect-rules`、`proxy-server-nameserver`、规则分组与健康检查 | 继续作为当前 Clash Verge 核心；代理节点域名解析必须单独验证，不能只看业务域名是否能解析 |
| [SagerNet/sing-box](https://github.com/SagerNet/sing-box) | 显式 DNS detour、路由规则、URLTest/出口选择的结构化表达 | 作为下一代配置模型参考，不为迁移而迁移；当前 Mihomo 已满足 C+D |
| [XTLS/Xray-core](https://github.com/XTLS/Xray-core) | VLESS+REALITY 服务端、配置预检、systemd 管理 | VPS 继续用 Xray；每次服务端改动先 `xray run -test -config <CONFIG>`，再 reload |
| [zizifn/edgetunnel](https://github.com/zizifn/edgetunnel) | CF Workers/Pages 作为独立入口，部署后做端到端出口验证 | 仅作为 `CF备用-JP`，不加入 `MIYA-STATIC`，也不宣称是住宅出口 |
| [go-gost/gost](https://github.com/go-gost/gost) | chain、matcher、链路级健康检查的通用表达 | 只做未来方案参考；当前禁止用它把 VPS 串到 MIYA，除非服务商书面允许且从 VPS 实测通过 |
| [MHSanaei/3x-ui](https://github.com/MHSanaei/3x-ui) / [Hiddify-Manager](https://github.com/hiddify/Hiddify-Manager) | 多协议面板、用户与订阅管理 | 当前单 VPS 不引入面板，避免额外 Web 攻击面、数据库和升级变量 |
| [Oxylabs 静态住宅代理示例](https://github.com/oxylabs/static-residential-proxies) | 静态/轮换会话、认证与并发限制等供应商语义 | 只能借鉴采购验收项，不是自建住宅实现；不写入任何供应商凭据 |

手册中另有 `tytsxai/anyreality-resi-stack` 与 `personal-edge-proxy` 的设计名称；本次复核均未取得可验证的公开仓库内容，暂不作为实施依据。

### 当前架构与这些项目的正确组合

```text
客户端 → Clash rule
       ├─ AI/X/Google/Netflix → MIYA-STATIC → 静态住宅出口（Fail Closed）
       ├─ TG/Discord/YouTube/MATCH → 线路冗余 → SelfHost-TKY-BGP → AI智能优选 → CF备用-JP
       └─ 百度/国内 → DIRECT
```

这属于**并行出口分层**，不是“VPS 进站后再转住宅”。住宅失败不能切 VPS，VPS 失败也不能切住宅；这正是当前约束下最可验证、最少泄漏出口身份的组合。

## 11. 值得补强的验收与运维点

### 11.1 健康检查要检查“身份”，不只检查“活着”

`gstatic generate_204` 只能证明连接与小包 HTTP 可用，不能证明出口身份正确。保留所有组的 `interval: 120`，并在人工验收或定时脚本中增加分出口探针：

| 出口 | 必验条件 | 失败处置 |
|---|---|---|
| MIYA-STATIC | ChatGPT trace 为 `loc=JP`，IP 稳定；再记录 IP 分类结果 | 住宅组保持 Fail Closed，禁止改投线路冗余 |
| SelfHost-TKY-BGP | `api.ipify.org` 为自建 VPS 出口 | 线路冗余继续按组内顺序切换 |
| CF备用-JP | CF 节点端到端 HTTP 成功，并记录实际出口 IP | 只作为最后备用，不提升为主线路 |

脚本或人工记录应同时包含“规则命中、节点组、最终 IP、HTTP 状态、时间”。延迟低或 204 成功而吞吐为零时，仍应判为线路劣化。

### 11.2 VPS 入口按证据逐步开启

- 当前 UDP 探测未通过，因此不启用 Hysteria2；先保持 TCP 443 的 REALITY 主入口。
- REALITY 当前握手正常，不因猜测随意更换 SNI；只有出现可复现的握手失败，才按“先换 SNI、再换协议”的顺序单变量试验。
- VPS 已完成非 root 密钥登录与 firewalld 基础收口；关闭密码登录和 root 远程登录仍需在确认第二个 `codexadmin` 密钥会话成功后再执行。
- 服务端配置先用 Xray 官方 `-test` 预检，再 reload；保留可回滚备份，不把生成的 UUID、私钥或链接写入仓库。

### 11.3 静态住宅采购/接入前置条件

如果未来要讨论“VPS → 静态住宅”的串联，必须先取得服务商明确许可并逐项实测：VPS 源 IP 是否允许、SOCKS5/HTTP 端口是否可从 VPS 建连、静态 IP 是否跨会话保持、并发/流量上限、认证或白名单规则、UDP 支持及服务条款。任何一项未证实，都维持当前本机直连 MIYA 的并行架构。

### 11.4 变更纪律

- Clash 只改 `profiles\\` 四类覆盖层，先备份，`mihomo -t` 通过后重启 Verge；GUI、`clash-verge.yaml`、`config.yaml` 都必须保持 `mode: rule`。
- 命名管道 API 在部分版本上不可靠，持久化变更不依赖 `PUT /proxies`。
- 生产升级采用“版本记录 → 配置预检 → 单次重启 → P0 探针 → 可回滚备份”，不自动追新版本。

## 9. jasonbitsmith/vps-first-steps（VPS 系统加固工程实践）

- 仓库：https://github.com/jasonbitsmith/vps-first-steps（MIT，单文件 bash，全新 Ubuntu/Debian VPS 初始化加固）
- 性质：系统加固脚本（更新/工具/UFW/fail2ban/swap/自动安全更新）+ 面向 AI 的操作规范（SKILL.md）

### 借鉴点

| 项目理念 | 含义 | 本仓库落地 |
|---|---|---|
| **备份 → 校验 → 回滚** | 改 sshd 前备份，`sshd -t` 校验，失败自动还原 | docs/11 加固清单；Clash 侧同构实践 = `verge-mihomo -t` 后再 reload |
| **第二会话验证才关旧入口** | 关闭登录方式前必须在独立会话实测新方式 | docs/11 SSH 加固强制步骤 |
| **只读模式分离** | `--check` / `--status` 零副作用 | 改造自身脚本时的模式 |
| **拒绝非交互破坏性操作** | `--disable-*` 不允许搭配 `-y` | — |
| **仅 HTTPS + 禁重定向降级** | 拉取公钥等高敏内容限协议 | — |
| **报告脱敏** | 输出主动删除 Banned IP 行 | 分享日志前强制 |
| **区分"已验证/未验证"** | REVIEW/TESTING 老实标注覆盖范围 | 本仓库改配置后同样标注 |

### 结论
不提供代理能力（明确声明不含节点部署），价值在**系统加固层 + 工程纪律**。已据其补齐 docs/11，并对照出本仓库部署脚本缺失的 4 项加固（SSH 强化 / fail2ban / swap / 自动更新）。注意其仅支持 apt 系发行版，本机实际 VPS 为 AlmaLinux 9，需按 docs/11 的 dnf 适配版执行。

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
- hoochanlon/fq-book：https://github.com/hoochanlon/fq-book
- yding-git/personal-edge-proxy：https://github.com/yding-git/personal-edge-proxy
- ip-api.com：https://ip-api.com
