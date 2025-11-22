#!/bin/bash

# 一键安装 Warp WireGuard + Socks5 (WireProxy)

# 支持 Debian/Ubuntu 系统

# 自动修复 hosts/backports 问题，apt 安装不会因 404 中断

set -e

echo "=== 检查并修复 sudo host 问题 ==="
HOSTNAME=$(hostname)
if ! grep -q "$HOSTNAME" /etc/hosts; then
echo "127.0.1.1   $HOSTNAME" | sudo tee -a /etc/hosts
fi

echo "=== 临时屏蔽失效的 backports 源 ==="
if [ -f /etc/apt/sources.list ]; then
sudo mv /etc/apt/sources.list /etc/apt/sources.list.bak
grep -v 'bullseye-backports' /etc/apt/sources.list.bak | sudo tee /etc/apt/sources.list
fi

echo "=== 更新 apt 并安装依赖 ==="
sudo apt update || true
sudo apt install -y wireguard-tools curl iproute2 || true

# 安装 wgcf

if ! command -v wgcf >/dev/null 2>&1; then
echo "下载 wgcf..."
curl -LO [https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_2.2.18_linux_amd64](https://github.com/ViRb3/wgcf/releases/latest/download/wgcf_2.2.18_linux_amd64)
chmod +x wgcf_2.2.18_linux_amd64
sudo mv wgcf_2.2.18_linux_amd64 /usr/local/bin/wgcf
fi

# 注册 Warp 并生成 WireGuard 配置

echo "注册 Warp 账户..."
wgcf register || true
wgcf generate || true

# 移动配置文件

sudo mkdir -p /etc/wireguard
sudo mv wgcf-profile.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf

# 安装 WireProxy

echo "安装 WireProxy..."
curl -LO [https://github.com/octeep/wireproxy/releases/latest/download/wireproxy-linux-amd64](https://github.com/octeep/wireproxy/releases/latest/download/wireproxy-linux-amd64)
chmod +x wireproxy-linux-amd64
sudo mv wireproxy-linux-amd64 /usr/local/bin/wireproxy

# 自动读取 wg0.conf 的私钥和公钥生成 proxy.conf

WG_PRIVATE=$(grep PrivateKey /etc/wireguard/wg0.conf | awk '{print $3}')
WG_PUBLIC=$(sudo wg show wg0 public-key 2>/dev/null || echo "PLACEHOLDER_PUBLIC_KEY")

sudo tee /etc/wireguard/proxy.conf >/dev/null <<EOF
[Interface]
PrivateKey = $WG_PRIVATE
Address = 172.16.0.2/32
Address = 2606:4700:110:8d0a:1e9:4b57:b946:549f/128
DNS = 1.1.1.1,8.8.8.8

[Peer]
PublicKey = $WG_PUBLIC
Endpoint = [2606:4700:d0::a29f:c001]:4500

[Socks5]
BindAddress = 127.0.0.1:40000
EOF

# 配置并启动 systemd 服务

sudo systemctl stop wireproxy.service 2>/dev/null || true
sudo tee /etc/systemd/system/wireproxy.service >/dev/null <<'EOF'
[Unit]
Description=WireProxy Socks5
After=network.target

[Service]
ExecStart=/usr/local/bin/wireproxy -c /etc/wireguard/proxy.conf
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wireproxy.service
sudo systemctl start wireproxy.service

echo "Warp WireGuard + Socks5 已安装完成！"
echo "Socks5 地址: 127.0.0.1:40000"
echo "检查状态: sudo systemctl status wireproxy.service"
