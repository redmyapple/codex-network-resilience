# 09 · 封锁原理与冷启动预案（fq-book 整合）

> 来源：[hoochanlon/fq-book](https://github.com/hoochanlon/fq-book)《这本书能让你连接互联网》（4.4k+ star，2026-09 仍活跃更新，docsify 在线书）。
> 本仓库此前的排查手册（docs/01）回答"怎么修"，本篇回答两件更底层的事：**为什么会被断**（封锁原理 → 对症甄别），以及**手里一条线路都没有时怎么重新开始**（冷启动预案）。

## 一、GFW 封锁手段速查（症状 → 甄别 → 对策）

| 封锁手段 | 原理 | 典型症状 | 快速甄别 | 对策 |
|---|---|---|---|---|
| **关键字过滤 + RST** | IDS 嗅探明文 HTTP（80 端口 Host 头等），伪装两端发 RST 掐断连接 | 网页加载到一半突然停止；触发后约 90s 内同 IP 同端口全部失败 | 换 HTTPS 复测是否恢复正常 | 全程加密协议，杜绝明文 HTTP 请求敏感域名 |
| **IP 封锁（路由黑洞）** | 在出口网关加伪造路由，目标 IP 数据包有去无回 | 整个 IP 完全不可达 | `ping` 不通 + `tracert` 断在境内部 | 换 IP / 域名套 CDN 中转 |
| **特定端口封锁** | 丢弃特定 IP + 特定端口的所有包（22 / 443 / 1723 等） | 服务整体可达但某些功能连不上 | 换端口复测 | 换端口；代理流量复用 443 |
| **SSL 连接阻断** | 检测 TLS 握手（SNI 特征），RST 掐断 443 握手 | HTTPS 握手失败、证书报错后 403 | 换 SNI 复测 | REALITY / uTLS 伪装 SNI（本仓库 docs/06 部署即此思路） |
| **DNS 劫持 / 污染** | DNS 查询返回虚假 IP（或 ISP 插广告/假证书） | 解析到怪异 IP；`NET::ERR_CERT_AUTHORITY_INVALID` | 换第三方 DNS 复测（见下节） | 加密 DNS（DoH/DoT/DNSCrypt）+ hosts 固定关键域名 |
| **TCP 回程阻断（GFW 2.0）** | 去程放行、回程拦截：黑名单 IP 的返回包被丢 | **Ping 通但 TCP 全断**；代理表现为超时/空连 | 见下节"被墙速判" | 换 IP / REALITY 抗封锁 / CDN 前置 |

## 二、VPS 被墙速判（自建必会，联动 docs/06）

TCP 回程阻断是当前主流封锁方式，判断一只 VPS 的 IP 是否被墙只需两条命令：

```powershell
ping <VPS_IP>                          # ICMP 通
Test-NetConnection <VPS_IP> -Port 443  # TCP 握手超时
```

- **Ping 通 + TCP 端口超时** → 99% 是 IP 被墙（回程被阻断），不是网络或服务器问题；剩下 1% 是防火墙没放行端口
- 原 TTL 特征：以前要靠"排除法"排查半天，现在这两条命令可以直接定性
- 处置：换 IP、上 REALITY（本仓库 `deploy-vps-xray.sh` 默认），或域名套 CDN 前置

## 三、冷启动预案：手里没有任何可用线路时

> 全线路瘫痪（机场跑路 + 备用失效 + 设备重置）时的工具获取通道。核心思想来自 fq-book 方法论篇：**获取梯子的关键是"留心通道"，而不是记住某个具体工具**——具体站点会死，通道长期有效。

1. **Email 自动回复**：部分工具组织开设自动应答邮箱，如给 `get@psiphon3.com` 发标题 `help`，自动回复下载地址
2. **GitHub 关键词检索**：搜 `vpn`、`v2ray`、`ss 分享` 等关键词；云平台部署站搜二级域名（如 herokuapp 类）
3. **镜像站点 / Web 代理**：找加密 Web 代理打开被屏蔽的工具站；镜像站同理
4. **浏览器扩展离线安装**：扩展下载站拿 `.crx` → 改 `.zip` 解压 → 开发者模式"加载已解压的扩展程序"
5. **P2P 下载**：eMule 等连服务器搜 `tor` 等关键词——P2P 加密传输 + 分布式，GFW 难以关键词过滤
6. **改 hosts / 换 DNS**：先查到工具站真实 IP 写进 hosts，配合加密 DNS 打开被污染的官网
7. **社会工程**：可信朋友/外企同事直接传工具；**传输前压缩包加密**——GFW 具备对未加密压缩文件的深度检测能力
8. **移动设备通道**：改设备地区语言（如新加坡），借内置代理壳应用订阅分享频道先行联网

⚠️ **安全警示**（fq-book 原文提醒）：

- 打开某工具站若**异常卡顿**（非网速原因）→ 大概率被植入挖矿脚本，立即关闭并拉黑
- 站点上的"资助二维码"未必是原作者（部署者可改代码敛财），勿扫码
- 上述具体站点/软件会随时间失效，**记住通道而不是站点**

## 四、DNS / hosts 抗污染要点

**症状**：浏览器报 `NET::ERR_CERT_AUTHORITY_INVALID`（"服务器无法证明它是 xxx"），继续访问又 403。

**原因**：ISP 的 DNS 对部分域名返回假 IP / 错误根证书。

**处置**：

```powershell
# 换第三方 DNS 后刷新缓存
ipconfig /flushdns
```

- 备选公共 DNS：百度 `180.76.76.76`、阿里 `223.5.5.5` / `223.6.6.6`、腾讯 `119.29.29.29`
- 长期方案：DNSCrypt / DoH 加密 DNS（本仓库客户端侧已落地，见 docs/04 §5）；关键域名 hosts 固定
- hosts 批量维护可参考 ineo6/hosts 等聚合源

## 五、参考

- hoochanlon/fq-book：https://github.com/hoochanlon/fq-book （原理与冷启动方法论）
- hoochanlon/hamuleite：https://github.com/hoochanlon/hamuleite （作者配套的站点/资料收录库）
- hoochanlon/Ip-Switch：https://github.com/hoochanlon/Ip-Switch （hosts/DNS 切换工具）
- DNSCrypt：https://github.com/DNSCrypt/dnscrypt-proxy （加密 DNS）
- GFW 原理详述：fq-book 书内「科学普及」篇（GFW 原理和封锁技术 / DNS 劫持与污染 / 数字证书攻防 / TCP 封锁猜想）
