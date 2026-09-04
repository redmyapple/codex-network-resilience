# 07 · 低价 VPS 选购调研：DediRock 案例与实时库存抓取

> 背景：docs/06 自建 VPS 路线落地前的厂商调研。低价年付机（$10/年量级）适合探针 / 备份 / 存储 / 练手，**不适合生产业务**。本篇沉淀可复用的调研方法、DediRock 实测结论，以及第三方库存监控站的 API 逆向技巧。

## 一、调研方法（可复用五步）

1. **抓在售价格**：主站 + 购物车页。静态站直接 `curl`；JS 渲染站用 Jina Reader（`https://r.jina.ai/<URL>`）或浏览器 DevTools 看 XHR。
2. **查商家背景**：注册实体、成立年份、上游机房（官网 footer / Whois / LowEndTalk 帖子）。
3. **查口碑**：Trustpilot 星级；LowEndTalk / NodeSeek / hostloc 社区帖，重点搜 `reliability uptime refund`。
4. **查故障史**：RAID / 网络故障记录、退款纠纷、是否有正式 SLA。
5. **定付款通道**：PayPal（保留争议退款通道），新商家避免加密货币直付。

## 二、DediRock 调研结果（2026-09）

### 在售套餐

| 套餐 | 配置 | 价格 |
|---|---|---|
| PROMO VPS NY | 2G RAM / 30G SSD / 2TB 流量 / 1Gbps | $9.88/年 |
| PROMO VPS LA | 2G RAM / 30G SSD / 2TB 流量 | $10.88/年 |
| Storage Promo NY | 三档存储机 | $12.88 / $19.88 / $29.88 |
| 常规 KVM LA/NY | 1C1G20G ~ 4C4G100G | $5.99~$12.99/月 |
| 独立服务器 | E3-1230v3 32G 起 | $59+/月（码 `15OFFDEDI` 终身85折） |

### 商家背景

- 美国注册公司 Atlas Cloud LLC（佛州 Clearwater），约 2024~2025 年成立
- 上游机房：ColoCrossing

### 好评面

- Trustpilot 约 4 星；用户反馈 uptime 98~99%
- 工单真人回复较快
- Buffalo/NY 节点口碑明显好于 LA；LA 本地测速约 920Mbps

### 风险面

- LA 节点晚高峰丢包/抖动投诉多（LET 原话：*"LA is on fire, Buffalo is fine"*）
- 2026 年初存储节点 RAID 故障，有用户数据受损并产生退款纠纷
- 控制面板卡慢；无正式 SLA
- 新商家跑路风险存在（NodeSeek 社区共识：适合挂探针，生产慎用）

### 结论

- $9.88 / $10.88 年付机**值得买**：探针 / 备份 / 存储 / 练手；存储机性价比突出
- **优先 NY/Buffalo，避开 LA**
- 生产业务选 Hetzner / Vultr / RackNerd 等成熟商家
- PayPal 付款，保留争议退款通道

## 三、第三方库存监控站 API 逆向（legacyvps.com 案例）

热门低价套餐经常需要盯库存。JS 渲染的监控站可以从前端 bundle 逆出数据 API 直连轮询：

1. 查看页面源码，找到 main bundle（形如 `assets/index-*.js`）
2. 在 bundle 里搜 `baseURL`、axios 实例、`get("` / `post("`，定位 API 前缀与端点
3. `curl` 直连时带浏览器头（`User-Agent` + `Referer`），可绕过基础防护
4. 实例（2026-09 验证有效）：

```
GET https://www.legacyvps.com/scanidc/api/data/list?providers=<厂商>&stock=in_stock&sort=price_monthly_asc
```

返回字段含 `stock`（剩余数量）、`price_display`、`price_monthly_cny`、`coupon_code`、`location` 等，可写脚本轮询做到货提醒（控制频率，别把监控站打挂）。

## 四、选购决策清单

- 年付 < $15 的机器默认当"可丢弃资源"：不放唯一数据，不承载唯一线路
- 买前用 Looking Glass 测试 IP 从**公司 + 家庭两条网络**分别测延迟/丢包（见 docs/06 第一步）
- 同价位优先：老商家 > 可月付 > 可随时退
- 重要数据本地 + 异地双备份——存储机的 RAID 也会坏（DediRock 2026 初 RAID 故障即案例）
- 关注商家终身折扣码（如 `15OFFDEDI`），常规机型叠码后性价比可能反超促销机
