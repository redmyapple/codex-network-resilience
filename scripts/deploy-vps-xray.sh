#!/usr/bin/env bash
# ============================================================
# deploy-vps-xray.sh — 全新 Ubuntu/Debian VPS 一键部署
# Xray VLESS + REALITY + Vision (TCP 443)
#
# 用法 (root):
#   bash deploy-vps-xray.sh
#
# 可选环境变量:
#   DEST=www.apple.com.cn   REALITY 伪装目标站点 (默认 www.apple.com.cn)
#   PORT=443                监听端口 (默认 443)
#
# 设计参考: yding-git/personal-edge-proxy (档位A: HY2/REALITY -> VPS Direct)
# 输出: 客户端 vless:// 链接 (含全部参数)。链接含 UUID,请妥善保管,不要外传。
# ============================================================
set -euo pipefail

[[ $EUID -ne 0 ]] && { echo "[错误] 请用 root 运行"; exit 1; }

DEST="${DEST:-www.apple.com.cn}"
PORT="${PORT:-443}"
XRAY_BIN=/usr/local/bin/xray

echo "==> [1/6] 系统时间校准 (时间偏差会导致 TLS 失败)"
timedatectl set-timezone Asia/Shanghai 2>/dev/null || true
apt-get install -y -qq chrony >/dev/null 2>&1 || true
systemctl enable --now chrony >/dev/null 2>&1 || true

echo "==> [2/6] 开启 BBR 拥塞控制 (改善高丢包线路吞吐)"
grep -q "tcp_congestion_control=bbr" /etc/sysctl.conf 2>/dev/null || {
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null
}
sysctl net.ipv4.tcp_congestion_control | grep -q bbr && echo "    BBR 已启用" || echo "    [警告] BBR 未生效(内核不支持?),继续"

echo "==> [3/6] 安装 Xray-core (官方安装脚本)"
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install >/dev/null 2>&1
[[ -x $XRAY_BIN ]] || { echo "[错误] Xray 安装失败"; exit 1; }
echo "    $($XRAY_BIN version | head -1)"

echo "==> [4/6] 生成 UUID / REALITY 密钥对 / shortId"
UUID=$($XRAY_BIN uuid)
KEYS=$($XRAY_BIN x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep -i "private" | awk '{print $NF}')
PUBLIC_KEY=$(echo "$KEYS" | grep -i "public"  | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 8)
[[ -n $PRIVATE_KEY && -n $PUBLIC_KEY ]] || { echo "[错误] 密钥生成失败"; exit 1; }

echo "==> [5/6] 写入配置 (VLESS+REALITY+Vision @ TCP $PORT, dest=$DEST)"
mkdir -p /usr/local/etc/xray
cat > /usr/local/etc/xray/config.json <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "listen": "0.0.0.0",
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          { "id": "$UUID", "flow": "xtls-rprx-vision", "level": 0 }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "$DEST:443",
          "xver": 0,
          "serverNames": [ "$DEST" ],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": [ "$SHORT_ID" ]
        }
      },
      "sniffing": { "enabled": true, "destOverride": [ "http", "tls" ] }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

echo "==> [6/6] 防火墙放行 + 启动服务"
if command -v ufw >/dev/null 2>&1; then
  ufw allow "$PORT/tcp" >/dev/null 2>&1 || true
  ufw allow 22/tcp >/dev/null 2>&1 || true
fi
systemctl enable xray >/dev/null 2>&1
systemctl restart xray
sleep 2
systemctl is-active xray >/dev/null || { journalctl -u xray --no-pager -n 20; exit 1; }

PUBIP=$(curl -4 -s --max-time 10 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')

echo ""
echo "============================================================"
echo " 部署完成。以下为客户端配置 (妥善保管,含隐私凭据):"
echo "------------------------------------------------------------"
echo " 协议:      VLESS + REALITY + Vision"
echo " 服务器:    $PUBIP"
echo " 端口:      $PORT"
echo " UUID:      $UUID"
echo " SNI:       $DEST"
echo " PUBLIC_KEY: $PUBLIC_KEY"
echo " SHORT_ID:  $SHORT_ID"
echo "------------------------------------------------------------"
echo " vless://$UUID@$PUBIP:$PORT?encryption=none&security=reality&sni=$DEST&fp=safari&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&flow=xtls-rprx-vision#SelfHost-Reality"
echo "============================================================"
echo " 提示:"
echo "  - 备份 /usr/local/etc/xray/config.json 与以上信息"
echo "  - 后续加节点/改端口: 编辑 config.json 后 systemctl restart xray"
echo "  - 可选加固: Hysteria2 (UDP) 入口冗余、WARP 出口 (AI 解耦),见仓库 docs/06"
