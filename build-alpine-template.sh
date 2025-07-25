#!/bin/bash

# Alpine 模板信息（3.20）
TEMPLATE_NAME="alpine-3.20-default_20240908_amd64.tar.xz"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"
CUSTOM_TEMPLATE="/var/lib/vz/template/cache/alpine-ssh-template.tar.gz"

# 容器配置
CTID=100
HOSTNAME="alpine-ssh"
PASSWORD="root123"
STORAGE="local"
BRIDGE="vmbr1"
IPADDR="172.16.1.200/24"
GATEWAY="172.16.1.1"

echo "📦 检查 Alpine 3.20 模板..."

# 模板存在检查
if [ ! -f "$TEMPLATE_PATH" ]; then
  echo "❌ 模板不存在：$TEMPLATE_PATH"
  echo "请先执行："
  echo "  pveam update"
  echo "  pveam download local $TEMPLATE_NAME"
  exit 1
fi

echo "🚀 创建容器 CTID=$CTID..."
pct create $CTID local:vztmpl/$TEMPLATE_NAME \
  --hostname $HOSTNAME \
  --password $PASSWORD \
  --rootfs ${STORAGE}:4 \
  --unprivileged 0 \
  --net0 name=eth0,bridge=$BRIDGE,ip=$IPADDR,gw=$GATEWAY

echo "▶️ 启动容器并安装组件..."
pct start $CTID

# 切换阿里云镜像源
pct exec $CTID -- sh -c "echo 'https://mirrors.aliyun.com/alpine/v3.20/main' > /etc/apk/repositories"
pct exec $CTID -- sh -c "echo 'https://mirrors.aliyun.com/alpine/v3.20/community' >> /etc/apk/repositories"

# 安装 SSH + 常用工具
pct exec $CTID -- apk update
pct exec $CTID -- apk add openssh curl wget sudo nano zip

# SSH 配置：允许 root 登录 + 密码认证
pct exec $CTID -- sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
pct exec $CTID -- sh -c "echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"
pct exec $CTID -- echo "root:$PASSWORD" | chpasswd
pct exec $CTID -- rc-update add sshd
pct exec $CTID -- rc-service sshd start

# 清理缓存
pct exec $CTID -- apk cache clean

echo "🛑 停止容器准备打包..."
pct stop $CTID

echo "📦 打包为模板：$CUSTOM_TEMPLATE"
tar --numeric-owner -czf "$CUSTOM_TEMPLATE" -C "/var/lib/lxc/$CTID/rootfs" .

echo "✅ 自定义 Alpine SSH 模板已创建："
echo "    $CUSTOM_TEMPLATE"
echo "🌐 IP: $IPADDR 网关: $GATEWAY 网桥: $BRIDGE"
echo "🔧 已预安装：openssh curl wget sudo nano zip"
