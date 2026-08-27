# 01 · CodeX 网络故障排查手册

## 症状

- `unexpected status 502 Bad Gateway: Provider unreachable: unknown certificate verification error, url: http://127.0.0.1:10100/v1/responses`
- `failed to connect to websocket: IO error: connection refused (os error 10061)`
- `failed to refresh available models: timeout waiting for child process to exit`
- `Incorrect API key provided: sk-<第三方Key>...`
- 大量 `Reconnecting... n/5`

这些现象**不是网络断了**，而是 CodeX 被本地代理 / 中转 / 第三方工具劫持，或端口指向错误。

## 排查清单（按顺序）

### 1. 端口监听是否正常

```powershell
Get-NetTCPConnection -State Listen | ? { $_.LocalPort -in 7890,7891,7892,7897,10100,3001,9090 } |
  Select LocalAddress,LocalPort,OwningProcess
```

| 端口 | 期望 |
|---|---|
| 7897 | Clash/Mihomo 本地混合端口 |
| 10100 | 若有 = opencodex 本地中转（应移除） |
| 3001 | 若报错 = 某个未启动的 MCP server |

### 2. CodeX 的 `.env` 代理端口

文件：`C:\Users\<user>\.codex\.env`

```ini
HTTP_PROXY="http://127.0.0.1:<CLASH_PORT>"   # 必须是实际监听的端口
HTTPS_PROXY="http://127.0.0.1:<CLASH_PORT>"
NO_PROXY="localhost,127.0.0.1,::1"
```

**坑**：如果这里写了一个没程序监听的端口（如 7890 而实际是 7897），所有请求都会 `connection refused`。

### 3. `config.toml` 里的 `openai_base_url`

文件：`C:\Users\<user>\.codex\config.toml`

```toml
# 官方渠道 = 不要出现任何 openai_base_url 覆盖
# 如果出现以下任意一行，删除它：
# openai_base_url = "http://127.0.0.1:10100/v1"
# openai_base_url = "https://api.teamorouter.cn/v1"
```

**常见来源**：opencodex、teamorouter 等工具通过注释 `# Auto-injected by ...` 注入。删除后重启 Codex。

### 4. `auth.json` 的认证模式与 API Key

文件：`C:\Users\<user>\.codex\auth.json`

```json
{
  "auth_mode": "chatgpt",            // 官方登录应为此值
  "OPENAI_API_KEY": "sk-<第三方注入Key>",  // 若被第三方工具注入，删除该字段
  "tokens": { ... }                  // 官方 OAuth token，保留
}
```

- `auth_mode=apikey` + 一个 `sk-<第三方注入Key>` 的 key → 说明被 teamorouter 劫持，CodeX 会拿无效 key 打官方接口 → `invalid_api_key`
- 修复：备份后删除 `OPENAI_API_KEY`，把 `auth_mode` 改回 `chatgpt`（保留 `tokens`）

### 5. 本地中转/代理服务的自启

如果 10100 中转仍在跑，找到并禁用自启：

```powershell
# 查找
Get-ScheduledTask | ? { $_.TaskName -match 'opencodex|teamorouter|mihomo' } | Select TaskName,State
# 注册表启动项
Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' | ? { $_ -match 'open|codex|team' }

# 禁用 + 停止
Disable-ScheduledTask -TaskName 'opencodex-proxy','TeamoRouter HTTP Proxy'
Stop-Process -Id <pid> -Force
```

### 6. 验证官方链路恢复

```powershell
codex exec --skip-git-repo-check "只回复 OK，不调用工具"
# 应返回 OK，且错误日志不再出现 10100 / 502 / invalid_api_key
```

## 诊断命令速查

| 目的 | 命令 |
|---|---|
| 端口监听 | `Get-NetTCPConnection -State Listen` |
| CodeX 进程去向 | 运行 codex 时抓 `netstat`，看它连的是 7897 还是 10100 |
| 环境变量 | `Get-ChildItem Env: | ? { $_.Name -match 'OPENAI|PROXY|CODEX' }` |
| 第三方覆盖 | `Select-String -Path ~\.codex\config.toml -Pattern 'openai_base_url'` |

## 结论

CodeX "网络问题" 90% 是**配置被劫持或端口写错**，不是真的没网。先查 `.env` 端口 → `openai_base_url` → `auth.json` 认证模式，基本都能修复。