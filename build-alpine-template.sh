#!/bin/bash
set -e

# ========== 可调参数 ==========
CTID=100
HOSTNAME="alpine-template"
PASSWORD="changeme123"
TEMPLATE_NAME="alpine-3.20-default_20240908_amd64.tar.xz"
TEMPLATE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.20/releases/x86_64/$TEMPLATE_NAME"
TEMPLATE_PATH="/var/lib/vz/template/cache/$TEMPLATE_NAME"
OUTPUT_TEMPLATE="/var/lib/vz/template/cache/alpine-3.20-ssh.tar.gz"

BRIDGE="vmbr1"
IP="172.16.1.100/24"
GATEWAY="172.16.1.1"
STORAGE="local"

# ========== 颜色输出函数 ==========
green()  { echo -e "\033[1;32m$1\033[0m"; }
red()    { echo -e "\033[1;31m$1\033[0m"; }

# ========== 检查模板 ==========
if [ ! -f "$TEMPLATE_PATH" ]; then
    green "📥 下载 Alpine 模板..."
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
sleep 3

# pct exec $CTID -- sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories
pct exec $CTID -- apk update
pct exec $CTID -- apk add openssh curl wget sudo nano zip bash

# 设置 root 密码
pct exec $CTID -- sh -c "echo root:$PASSWORD | chpasswd"

# 添加 sshd 到启动项
pct exec $CTID -- rc-update add sshd default

# 修复 sshd 无法启动的问题：/var/empty 权限
pct exec $CTID -- mkdir -p /var/empty
pct exec $CTID -- chown root:root /var/empty
pct exec $CTID -- chmod 755 /var/empty

# 启用 root 登录和密码认证
pct exec $CTID -- sh -c "grep -q '^PermitRootLogin' /etc/ssh/sshd_config && \
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config || \
    echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config"

pct exec $CTID -- sh -c "grep -q '^PasswordAuthentication' /etc/ssh/sshd_config && \
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config || \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config"

# 生成 SSH host key 并启动 sshd
pct exec $CTID -- ssh-keygen -A
pct exec $CTID -- rc-service sshd start
pct exec $CTID -- rc-service sshd status || red "❌ SSHD 启动失败"

# 添加自定义SSH欢迎界面（写入容器内/etc/motd）
pct exec $CTID -- sh -c "cat > /etc/motd <<'EOF'
 _       _       ____  
| |     | |     |  _ \ 
| |     | |     | |_) |
| |     | |     |  __/ 
| |____ | |____ | |    
|______||______||_|    

欢迎使用 Alpine 3.20 LLP 特别版
---------------------------------
crontab中包含了定时三天删除/var/log下的journalctl syslog等日志文件
您可以按需删除定时任务
EOF
"

# 添加定时 清理日志&Ping6任务（在容器内设置crontab）
pct exec $CTID -- sh -c "(crontab -l 2>/dev/null; echo '0 0 */3 * * rm -rf /var/log/journal && rm -f /var/log/syslog /var/log/syslog.1 && mkdir -p /var/log/journal'; echo '*/1 * * * * ping6 -c 2 google.com > /dev/null 2>&1') | crontab -"
pct exec $CTID -- rc-update add crond
pct exec $CTID -- rc-service crond start


# 清理无用缓存
pct exec $CTID -- rm -rf /var/cache/apk/*

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

green "✅ 自定义 Alpine SSH 模板创建完成！"
echo "    模板路径：$OUTPUT_TEMPLATE"
echo "    登录信息：root / $PASSWORD"
echo "    网桥：$BRIDGE，IP：$IP，网关：$GATEWAY"
