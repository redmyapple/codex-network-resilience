# AGENTS.md — 维护说明（给 AI / 协作者）

本仓库记录「CodeX 网络排查 + Clash 分流 + 住宅代理」方法论。后续配置/排查有变更时，按以下规则同步更新。

## 变更时该做什么

1. **先判断是否值得入库**：只同步**可复用的方法论 / 配置模板 / 排查步骤 / 脚本**。本机临时状态（一次性的 IP、临时节点选择）不必要入库。
2. **新增排查经验** → 更新 `docs/01-codex-network-troubleshooting.md`（按"症状 → 排查清单 → 命令 → 结论"结构追加）。
3. **Clash 配置策略变化** → 更新 `docs/02-clash-verge-configuration.md`（分组、规则、覆盖文件、命名管道 API）。
4. **住宅/出口策略变化** → 更新 `docs/03-residential-proxy-strategy.md`。
5. **借鉴的项目/方法更新** → 更新 `docs/04-methodology-references.md`。
6. **脚本更新** → 更新 `scripts/`（如 `filter-best-node.ps1`），并保证不含真实凭据。

## 安全红线（必须遵守）

- **绝不提交**：密码、token、API Key、订阅 URL、真实服务器 IP / 域名、`auth.json`、`.env`、Clash 运行时配置。
- 所有敏感值一律用占位符：`<USERNAME>`、`<PASSWORD>`、`<HOST>`、`<PORT>`、`<住宅IP>`、`<MIYAIP_HOST>` 等。
- 提交前自查：`Select-String -Path <repo> -Pattern '<真实IP>|<真实密码>|<订阅URL>'`。
- `.gitignore` 已排除 `*.env`、`auth.json`、`clash-verge.yaml`、`profiles/`、`.wrangler/` 等。
- **在仓库目录运行 wrangler 等工具会生成缓存文件**（如 `.wrangler/cache/wrangler-account.json` 含账号信息）——曾被误提交后清除。教训：新工具生成的本地文件第一时间加入 `.gitignore`，每次 `git push` 前必须 `git status` 核对暂存内容。

## 同步命令

```powershell
# 一键提交并推送（本机）
powershell -NoProfile -ExecutionPolicy Bypass -File sync.ps1

# 手动
git add -A
git commit -m "sync: <描述>"
git push
```

## 快速验证（每次改完）

```powershell
# 确认无真实凭据残留
Select-String -Path .\README.md, .\docs\*.md, .\scripts\* -Pattern '<USERNAME>|<PASSWORD>|<住宅IP>|<HOST>|订阅URL|auth.json' -ErrorAction SilentlyContinue
# 应无输出