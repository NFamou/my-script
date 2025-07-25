#!/bin/bash

# ========== 可调参数 ==========
CTID=100
HOSTNAME="alpine-template"
PASSWORD="changeme123"                      # 容器内 root 密码，至少5位
TEMPLATE_NAME="alpine-3.20-default_20240908_amd64.tar.xz"
TEMPLATE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/$TEMPLATE_NAME"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"
OUTPUT_TEMPLATE="/var/lib/vz/template/cache/alpine-ssh-template.tar.gz"

BRIDGE="vmbr1"
IP="172.16.1.100/24"
GATEWAY="172.16.1.1"
STORAGE="local"                     # 可改为 local-lvm，如果你有这个存储池

# ========== 颜色输出函数 ==========
_color() { echo -e "\033[$1m$2\033[0m"; }
green()  { _color "32;1" "$1"; }
red()    { _color "31;1" "$1"; }

# ========== 检查模板 ==========
if [ ! -f "$TEMPLATE_PATH" ]; then
    green "📥 下载 Alpine 3.20 模板..."
    wget -O "$TEMPLATE_PATH" "$TEMPLATE_URL" || { red "❌ 下载失败"; exit 1; }
else
    green "📦 模板已存在：$TEMPLATE_NAME"
fi

# ========== 创建容器 ==========
green "🚀 创建容器 CTID=$CTID..."
pct destroy $CTID 2>/dev/null
pct create $CTID "$TEMPLATE_PATH" \
    --storage "$STORAGE" \
    --hostname "$HOSTNAME" \
    --password "$PASSWORD" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=$IP,gw=$GATEWAY" \
    --features nesting=1 \
    --unprivileged 1 || { red "❌ 容器创建失败"; exit 1; }

# ========== 启动容器并安装组件 ==========
green "▶️ 启动容器并安装组件..."
pct start $CTID
sleep 3

# 更换源、安装软件
pct exec $CTID -- sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories
pct exec $CTID -- apk update
pct exec $CTID -- apk add openssh curl wget sudo nano zip

# 设置 root 密码
pct exec $CTID -- sh -c "echo root:$PASSWORD | chpasswd"

# 修复 /var/empty 权限，避免 sshd 启动失败
pct exec $CTID -- mkdir -p /var/empty
pct exec $CTID -- chown root:root /var/empty
pct exec $CTID -- chmod 711 /var/empty

# 设置 SSH 登录策略
pct exec $CTID -- sh -c "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"
pct exec $CTID -- sh -c "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

# 开机自启 sshd + 初始化 key + 启动服务
pct exec $CTID -- rc-update add sshd default
pct exec $CTID -- ssh-keygen -A
pct exec $CTID -- rc-service sshd start || pct exec $CTID -- rc-service sshd restart
pct exec $CTID -- rc-service sshd status
sleep 2

# ========== 打包模板 ==========
green "🛑 停止容器准备打包..."
pct stop $CTID

green "📦 挂载容器目录..."
MOUNT_DIR=$(pct mount $CTID | awk -F"'" '{print $2}')
[ -d "$MOUNT_DIR" ] || { red "❌ 挂载失败"; exit 1; }

green "📦 打包模板为：$OUTPUT_TEMPLATE"
tar --numeric-owner -czf "$OUTPUT_TEMPLATE" -C "$MOUNT_DIR" .

pct unmount $CTID
pct destroy $CTID

green "✅ 自定义 Alpine SSH 模板已创建："
echo "    $OUTPUT_TEMPLATE"
green "🌐 IP: $IP 网关: $GATEWAY 网桥: $BRIDGE"
green "🔧 已预安装：openssh curl wget sudo nano zip"
