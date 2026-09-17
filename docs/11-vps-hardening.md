# 11 · VPS 系统加固（vps-first-steps 借鉴与落地）

> 来源：[jasonbitsmith/vps-first-steps](https://github.com/jasonbitsmith/vps-first-steps)（MIT，单文件 bash，把全新 Ubuntu/Debian VPS 初始化到加固可用状态）
> 本文只提取**可复用的加固策略与工程实践**，并适配到本仓库的实际环境（自建 VPS = **AlmaLinux 9**，跑 Xray REALITY @ TCP 443）。

## 一、为什么需要这一层

`scripts/deploy-vps-xray.sh` 解决的是"**让代理跑起来**"：时钟校准、BBR、Xray 安装、SELinux 处理、放行 443/22。
但它不解决"**服务器本身别被人打进来**"。两者是正交的，缺一层就是敞口。

## 二、来源项目安全审查结论

在上机前对 `vps-init.sh`（403 行）做了逐行审查，**未发现恶意行为**，且工程水准明显高于平均：

| 审查项 | 结论 |
|---|---|
| 数据外传 / 反弹 shell / 挖矿 / 混淆 | 无（全文无对外 POST、无 base64 载荷、无未知下载执行） |
| 公钥获取 | 仅 HTTPS，且 `curl --proto '=https' --proto-redir '=https'` 防重定向降级；`ssh-keygen -lf` 校验格式 |
| sshd 改动 | **先备份 → `sshd -t` 校验 → 失败自动回滚** |
| 危险操作 | 关闭 root/密码登录必须**第二个终端实测登录成功**并手动输入 `VERIFIED`，`--yes` 无法跳过 |
| 防火墙 | 幂等（先 allow 当前 SSH 端口再 enable），不碰其他端口 |
| 隐私 | 状态报告主动 `sed` 删除 Banned IP 列表，避免分享时泄露 |

⚠️ **但不要直接把它跑在你的机器上**：它只支持 Ubuntu/Debian（用 `apt`、服务名 `ssh`）；你的机器是 **AlmaLinux 9**（用 `dnf`、服务名 `sshd`），且**它默认只放行 SSH 端口 —— 会直接把你的 443 挡掉，Xray 立即失联**。

## 三、差距分析：你的 VPS 现在缺什么

把来源项目的加固项与本仓库 `deploy-vps-xray.sh` 对照：

| 加固项 | 来源项目 | 你的部署脚本 | 状态 |
|---|---|---|---|
| 时钟同步 / BBR / SELinux | — | ✅ 已做 | 完成 |
| 443 + 22 放行 | ⚠️ 只放行 SSH | ✅ 两者都放行 | 完成 |
| **SSH 加固（禁 root 登录 / 禁密码登录）** | ✅ | ❌ 无 | **缺口（最高优先）** |
| **fail2ban（SSH 爆破防护）** | ✅ | ❌ 无 | **缺口** |
| **交换空间 swap** | ✅ | ❌ 无 | **缺口** |
| **自动安全更新** | ✅ | ❌ 无 | **缺口** |
| 默认拒绝入站策略 | ✅ | 部分 | 待核查 |

**风险说明**：VMISS 交付的默认状态是 `root` + 密码登录 + 22 端口对全网开放。没有 fail2ban、没有自动安全更新 → 爆破与已知漏洞利用是常态化威胁（VPS 被扫是分钟级的，不是假设）。

## 四、AlmaLinux 9 适配版加固清单（可执行）

> 全部命令在 VPS 上以 root 执行。**顺序很重要**，尤其第 5 项。

### 1. 交换空间（1G）

```bash
swapon --show | grep -q . && echo "已有 swap，跳过" || {
  [[ -e /swapfile ]] && { echo "警告: /swapfile 已存在但未启用，先人工检查"; exit 1; }
  fallocate -l 1G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  sysctl -w vm.swappiness=10
  grep -q '^vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
}
```

### 2. fail2ban（SSH 爆破防护）

```bash
dnf install -y epel-release && dnf install -y fail2ban
mkdir -p /etc/fail2ban/jail.d
cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
port     = 22
backend  = systemd
maxretry = 5
bantime  = 1h
findtime = 10m
EOF
systemctl enable --now fail2ban
systemctl is-active fail2ban && fail2ban-client status sshd
```

> 用 `jail.d/*.local` drop-in，**不要覆盖** `/etc/fail2ban/jail.local`（来源项目的做法）。

### 3. 自动安全更新

```bash
dnf install -y dnf-automatic
sed -i 's/^apply_updates *= *no/apply_updates = yes/' /etc/dnf/automatic.conf
systemctl enable --now dnf-automatic.timer
systemctl list-timers dnf-automatic.timer --no-pager
```

### 4. 防火墙：确认只开必要端口

```bash
firewall-cmd --list-all          # 先看现状
# 应只保留 ssh 与你的 Xray 端口(443)。要移除多余服务：
# firewall-cmd --permanent --remove-service=<多余的服务> && firewall-cmd --reload
```

⚠️ **执行前必须确认 443/tcp 在放行列表中**，否则禁用其他规则后 Xray 会断。

### 5. SSH 加固（最高价值，也最容易把自己锁在外面）

**前置条件（缺一不可）**：
1. 你的**公钥已装到服务器**且能用密钥登录成功；
2. 当前会话**不要关闭**；
3. 另开一个终端实测密钥登录成功。

```bash
# ① 确认密钥登录可用（另开终端执行，不要在这个会话里）
#    ssh -p 22 root@<VPS_IP>    -> 不输密码即登录成功

# ② 备份 → 修改 → 校验 → 重载，失败自动回滚
cp -p /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak-$(date +%F)"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
if sshd -t && systemctl reload sshd; then
  echo "SSH 加固完成：root 仅密钥可登，密码登录已关闭"
else
  cp -p /etc/ssh/sshd_config.bak-* /etc/ssh/sshd_config && systemctl reload sshd
  echo "校验失败，已回滚"
fi
```

> 说明：`PermitRootLogin prohibit-password` 保留 root 密钥登录、只禁密码（比一律 `no` 更不容易锁死自己）。若要彻底禁 root，必须先建好普通 sudo 账号并验证。
> **第三会话再验证一次**：新开终端密钥登录成功，方可关闭当前会话。

## 五、值得抄进本仓库的工程实践（比脚本本身更值钱）

| 实践 | 含义 | 采纳方式 |
|---|---|---|
| **备份 → 校验 → 回滚** | 改关键配置前先备份，改完用官方校验器（`sshd -t` / `visudo -cf` / `mihomo -t`）验证，失败自动还原 | 本仓库已在 Clash 侧用 `verge-mihomo -t` 校验；SSH/系统侧照此办理 |
| **第二会话验证才关旧入口** | 关闭任何登录方式前，必须在独立会话实测新方式可用 | 加固 SSH、切密钥时的强制步骤 |
| **只读模式分离** | `--check`（预检）/ `--status`（验收）不产生副作用 | `scripts/filter-best-node.ps1` 的只读探测可对标 |
| **拒绝非交互执行破坏性操作** | `--disable-*` 不允许与 `-y` 组合 | 破坏性变更一律要求人工确认 |
| **仅 HTTPS + 禁重定向降级** | 拉取公钥等高敏内容时限制协议 | 脚本中所有外部拉取照此约束 |
| **报告脱敏** | 状态输出主动删除 Banned IP 等敏感行 | 分享日志/截图前必须脱敏 |
| **明确"做什么 / 不做什么"** | README 用表格划清边界，避免误解为"全能部署" | docs/06 已用类似写法 |
| **区分"已验证 / 未验证"** | REVIEW.md/TESTING.md 老实标注测试覆盖范围 | 本仓库改配置后同步标注验证程度 |
| **专用 drop-in 而非覆盖主配置** | `jail.d/*.local`、`/etc/sudoers.d/` | 对应 Clash 侧的 `profiles/*.yaml` 组件化 |

## 六、与本仓库其他文档的关系

- `docs/06` 自建 VPS 路线图：**部署**（把代理跑起来）← 本文补上**加固**层
- `docs/09` 封锁原理与冷启动：VPS 被墙后的判断与处置
- `scripts/deploy-vps-xray.sh`：跨发行版部署，本文的加固项可作为它的后续步骤

## 七、参考

- jasonbitsmith/vps-first-steps：https://github.com/jasonbitsmith/vps-first-steps
- OpenSSH sshd_config 手册（前置指令优先级的依据）：https://man.openbsd.org/sshd_config
