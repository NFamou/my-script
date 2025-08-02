#!/bin/bash
set -e

# ========== 可调参数 ==========
CTID=100
HOSTNAME="debian-template"
PASSWORD="changeme123"
TEMPLATE_NAME="debian-11-standard_11.7-1_amd64.tar.zst"
TEMPLATE_URL="https://images.linuxcontainers.org/images/debian/bullseye/amd64/default/20240710_22:42/rootfs.tar.xz"  # 自定义镜像源
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"
OUTPUT_TEMPLATE="/var/lib/vz/template/cache/debian-11-ssh.tar.gz"

BRIDGE="vmbr1"
IP="172.16.1.100/24"
GATEWAY="172.16.1.1"
STORAGE="local"

# ========== 颜色输出函数 ==========
green()  { echo -e "\033[1;32m$1\033[0m"; }
red()    { echo -e "\033[1;31m$1\033[0m"; }

# ========== 检查模板 ==========
if [ ! -f "$TEMPLATE_PATH" ]; then
    green "📥 下载 Debian 模板..."
    wget -O "$TEMPLATE_PATH" "$TEMPLATE_URL" || { red "❌ 模板下载失败"; exit 1; }
else
    green "📦 模板已存在：$TEMPLATE_NAME"
fi

# ========== 创建容器 ==========
green "🚀 创建容器 CTID=$CTID..."
pct destroy $CTID 2>/dev/null || true
pct create $CTID "$TEMPLATE_PATH" \
    --storage "$STORAGE" \
    --hostname "$HOSTNAME" \
    --password "$PASSWORD" \
    --net0 "name=eth0,bridge=$BRIDGE,ip=$IP,gw=$GATEWAY" \
    --features nesting=1 \
    --unprivileged 0

# ========== 安装软件 ==========
green "▶️ 启动容器并安装组件..."
pct start $CTID
sleep 5

pct exec $CTID -- apt update
pct exec $CTID -- apt install -y openssh-server curl wget sudo nano zip bash

# 设置 root 密码
pct exec $CTID -- sh -c "echo root:$PASSWORD | chpasswd"

# 启用 root 登录和密码认证
pct exec $CTID -- sh -c "grep -q '^PermitRootLogin' /etc/ssh/sshd_config && \
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"

pct exec $CTID -- sh -c "grep -q '^PasswordAuthentication' /etc/ssh/sshd_config && \
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

# 启用 SSH 服务
pct exec $CTID -- systemctl enable ssh
pct exec $CTID -- systemctl restart ssh
pct exec $CTID -- systemctl is-active ssh || red "❌ SSH 启动失败"


# 添加 crontab 定时任务（清理日志 + ping6）
pct exec $CTID -- sh -c "(crontab -l 2>/dev/null; echo '0 0 */3 * * rm -rf /var/log/journal && rm -f /var/log/syslog /var/log/syslog.1 && mkdir -p /var/log/journal'; echo '*/1 * * * * ping6 -c 2 google.com > /dev/null 2>&1') | crontab -"
pct exec $CTID -- systemctl enable cron
pct exec $CTID -- systemctl start cron

# 清理 apt 缓存
pct exec $CTID -- apt clean

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

green "✅ 自定义 Debian SSH 模板创建完成！"
echo "    模板路径：$OUTPUT_TEMPLATE"
echo "    登录信息：root / $PASSWORD"
echo "    网桥：$BRIDGE，IP：$IP，网关：$GATEWAY"
