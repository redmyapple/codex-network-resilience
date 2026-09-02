# 05 · 备用客户端：NekoBox（nekoray）

> 策略：**客户端级冗余**。Clash Verge 的故障面是「配置生成流水线」（一处覆盖文件损坏 → 全部代理瘫痪，实测发生过）。NekoBox 基于 sing-box 内核，节点互相独立、无流水线，**正好互补**。两者本地端口不同（7897 vs 2080），可同时运行互不干扰。

## Clash Verge Rev vs NekoBox (nekoray 4.x) 对比

| 维度 | Clash Verge Rev | NekoBox (nekoray 4.x) |
|---|---|---|
| 内核 | Mihomo (Clash Meta) | sing-box |
| 配置方式 | YAML 订阅 + 覆盖文件链（流水线） | 节点数据库（每个节点独立 JSON 文件） |
| 规则分流 | ★★★★★（域名/GEOIP 丰富） | ★★★（可用但生态弱） |
| 订阅管理 | ★★★★★ 原生+自动更新+覆盖链 | ★★★ 格式兼容性一般（Clash 订阅需手动添加节点） |
| 协议广度 | ★★★★ | ★★★★★（Hysteria2/TUIC/SSH 原生） |
| 故障模式 | ❌ 配置链一处损坏全瘫 | ✅ 节点独立，故障域隔离 |

## 直接注入节点（免 GUI 配置）

nekoray 4.x 数据库结构：

```
<安装目录>\config\
├── nekobox.json          # 全局设置（inbound_socks_port: 2080 等）
├── groups\<id>.json      # 组（gid=0 为默认组）
└── profiles\<id>.json    # 每个节点一个 JSON（扁平结构，bean 嵌套在 "bean" 键下）
```

### Profile JSON 格式（从 nekoray 源码 db/Database.cpp + fmt/*Bean.hpp 核实）

```json
{
    "type": "vless",
    "id": 1,
    "gid": 0,
    "yc": 0,
    "bean": {
        "_v": 0,
        "name": "节点名",
        "addr": "服务器地址",
        "port": 443,
        "pass": "<UUID或密码>",
        "flow": "",
        "stream": {
            "net": "ws",
            "sec": "tls",
            "sni": "<SNI>",
            "host": "<WS Host>",
            "path": "/?ed=2560",
            "utls": "chrome",
            "pbk": "<REALITY公钥，REALITY时必填>",
            "sid": "<REALITY shortId>"
        }
    }
}
```

字段要点（源码核实）：

- `type`：socks / http / vless / trojan / vmess / shadowsocks / hysteria2 / tuic / naive / chain / custom
- socks5 节点：`"type": "socks"` + `"v": 5` + `username` + `password`（http 类型则 `"v": -80`）
- REALITY：`stream.sec = "tls"` + 非空 `stream.pbk` 即触发（无需特殊 sec 值）
- **`_v` 必填**：缺失时 bean.version == -114514，启动时该节点会被**自动删除**（损坏清理机制）
- 启动时解析失败的节点同样被静默删除——注入后必须验证文件是否存活

### 注入流程

```powershell
# 1. 确认 NekoBox 已关闭（运行中会在退出时覆盖数据库）
Stop-Process -Name nekobox,nekobox_core -ErrorAction SilentlyContinue

# 2. 写入 profiles/<id>.json

# 3. 启动并验证文件存活（存活 = 加载成功；被删 = 格式错误）
Start-Process "<安装目录>\nekobox.exe"
Start-Sleep 10
Get-ChildItem "<安装目录>\config\profiles"
```

## 备用切换操作（Clash 瘫痪时）

1. 关掉 Clash Verge（避免系统代理打架）
2. 打开 NekoBox → 双击选中节点 → 开启**系统代理**
3. NekoBox 本地端口 `127.0.0.1:2080`（与 Clash 7897 不冲突，可共存）
4. 修好 Clash 后：关 NekoBox 系统代理 → 重启 Clash Verge → 恢复

## 注意事项

- ⚠️ 不要同时开两家的 TUN/系统代理
- 节点测试：NekoBox 右键 → 测试延迟
- 机场订阅是 Clash YAML 格式，NekoBox 导入兼容性一般——手动注入核心节点更可靠
- 新工具在仓库目录运行会生成缓存（如 wrangler 的 `.wrangler/`），第一时间加 `.gitignore`（参见 AGENTS.md 安全红线）