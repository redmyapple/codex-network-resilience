# 08 · 科学上网客户端矩阵与应急策略

> 客户端级冗余是故障域隔离的最后一环（见 docs/01 三层线路架构的客户端层）。本篇整理 4 款主力客户端、全平台矩阵、5 条应急策略，以及 2026-09 经 GitHub API 核实的维护状态。来源：bannedbook/fanqiang 项目库 + 社区实测。

## 一、主力客户端（4 款）

| # | 客户端 | 平台 | 定位 | 链接 |
|---:|---|---|---|---|
| 1 | v2rayN | Windows | 全能型主力，教程多、上手门槛低 | https://github.com/2dust/v2rayN |
| 2 | NekoBox | Android | 兼容性强，导入节点/更新订阅快 | https://matsuridayo.github.io |
| 3 | Shadowsocks | 全平台 | 经典轻量备用方案，体积仅几 MB | https://shadowsocks.org/doc/getting-started.html#gui-clients |
| 4 | Clash Verge | 桌面端 | 成熟 GUI，新手可用，也支持高级路由分流规则 | https://clashverge.dev |

要点：

- **v2rayN**：Windows 最主流，社区生态最大，出问题容易搜到方案
- **NekoBox**：安卓端兼容性强；⚠️ 2026-02 仍有提交但节奏放缓（MatsuriDayo/NekoBoxForAndroid 未归档），新协议支持可能滞后
- **Shadowsocks**：协议简单稳定，应急备用依然可靠
- **Clash Verge**：活跃维护的是 Clash Verge Rev 分支（clashverge.dev 即其官网）
- 重要场景至少准备**两个不同内核**的客户端互为备份（本机实践：Clash Verge 主 + NekoBox 备，见 docs/05）

## 二、应急策略五条（源自 bannedbook/fanqiang）

> 仓库：https://github.com/bannedbook/fanqiang —— 老牌翻墙教程项目库（30k+ star），全平台客户端教程 + 一键翻墙包 + 自建服务器教程，被封时可作应急检索入口。

### 策略一：客户端轮换法（ChromeGo 一键包思路）

核心思想：**单一工具不可靠，准备一整套可轮换的方案**。"Chrome 一键翻墙包"集成 v2ray、SSR、Trojan、Brook、psiphon、蓝灯等十余种工具，内置免费服务器，按顺序逐个尝试。

- 一键包：Chrome 版 / Edge 版（EdgeGo）/ Mac 版 / Firefox Linux 版，调用浏览器内核免安装
- 注意：解压路径不要含中文或空格
- 适用：主客户端全挂时的应急、临时设备

### 策略二：多客户端矩阵（按平台备选）

| 平台 | 客户端（2026 视角筛选） |
|---|---|
| Windows | v2rayN（主力）、Clash Verge（Cfw 已停更的替代）、SSTap（游戏）、SSR |
| Android | v2rayNG（活跃）、Clash for Android、NekoBox、BifrostV、Surfboard |
| iOS | Shadowrocket（付费）、Quantumult X、Surge、Potatso |
| macOS | V2RayU、Surge；ClashX 原仓库已删库，勿再找原版 |
| 路由器 | 梅林固件、OpenWRT 固件级翻墙 |
| 游戏主机 | PS4/PS5/Switch/Xbox 经局域网共享或旁路由加速 |

### 策略三：自建服务器

节点被批量封禁时自建最可控（完整路线见 docs/06）：

- 自建 V2ray 服务器简明教程：`v2ss/自建V2ray服务器简明教程.md`（bannedbook/fanqiang 仓库内）
- 自建 Shadowsocks 服务器简明教程：同仓库

### 策略四：链式代理与旁路由（进阶）

- v2rayN 支持链式代理（前置代理 → 落地代理），提升隐蔽性
- iOS 设备可经电脑局域网共享翻墙（fqByLan），无需每个设备单独配 APP
- Mac ClashX Pro 可作网关旁路由，给 Switch / Apple TV 等无代理设备加速

### 策略五：协议组合冗余

README 推荐顺序：Goflyway → v2ray → Daze → SSR → Brook → Lightsocks → trojan → 蓝灯 → psiphon。**封锁高峰期不同协议存活率不同**，多层冗余比押注单一协议可靠。

## 三、维护状态速查（2026-09-04 GitHub API 核实）

| 客户端 | 仓库 | 状态 |
|---|---|---|
| v2rayN | 2dust/v2rayN | ✅ 活跃（2026-09-04 有提交） |
| v2rayNG | 2dust/v2rayNG | ✅ 活跃（2026-08-30） |
| Clash Verge Rev | clash-verge-rev/clash-verge-rev | ✅ 活跃（2026-09-04） |
| NekoBox for Android | MatsuriDayo/NekoBoxForAndroid | ⚠️ 维护放缓（2026-02） |
| Shadowsocks Windows | shadowsocks/shadowsocks-windows | ⚠️ 停更（2025-01 最后提交） |
| ClashX | 原仓库 | ❌ 已删库，改用替代分支 |
| Clash for Windows | Fndroid/clash_for_windows_pkg | ❌ 2023 停更删库 |

> 提醒：选型时先 `gh api repos/<owner>/<repo> --jq .pushed_at` 核实维护状态，停更客户端的协议支持会逐渐落后于封锁环境演进。
