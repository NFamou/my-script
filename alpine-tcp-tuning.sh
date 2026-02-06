#!/bin/sh
# alpine-tcp-tuning-v2.sh
# 适用环境: Alpine Linux + LXC + 128MB RAM + 代理服务
# 优化重点: 引入 BBR 算法, 维持 8MB 安全缓存, 提升高延迟下的四线程稳定性
# 回滚命令: rm -f /etc/sysctl.d/99-tcp-tuning.conf && sysctl --system

CONF_FILE="/etc/sysctl.d/99-tcp-tuning.conf"

echo "[*] 开始写入 TCP 优化配置到 $CONF_FILE"

cat > "$CONF_FILE" << 'EOF'
# ============================================
# Alpine TCP Tuning (Optimized for 128MB LXC)
# ============================================

# ---- 1. 拥塞控制算法 (关键: 提升高延迟/丢包表现) ----
# 如果内核支持，优先使用 BBR
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ---- 2. TCP Socket Buffer (8MB 黄金平衡点) ----
# 防止多线程下内存溢出 (OOM)，同时支持约 240Mbps 单线带宽
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608

# ---- 3. 全局套接字限制 (适配 128MB 内存) ----
# 虽然 LXC 可能会拦截 net.core.*，但写入此处以防万一
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608

# ---- 4. 连接生命周期优化 (减少 TIME_WAIT 积压) ----
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# ---- 5. TCP Fast Open (提升首包响应速度) ----
net.ipv4.tcp_fastopen = 3
EOF

echo "[*] 确保 Alpine sysctl 服务已启用"
# Alpine 默认 sysctl 启动逻辑
rc-service sysctl start >/dev/null 2>&1
rc-update add sysctl boot >/dev/null 2>&1

echo "[*] 正在应用配置..."
sysctl --system

echo "------------------------------------------------"
echo "[*] 核心参数应用状态检查:"
echo "------------------------------------------------"

# 检查 BBR
BBR_STATUS=$(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}')
if [ "$BBR_STATUS" = "bbr" ]; then
    echo "[OK] 拥塞算法: BBR 已成功启用"
else
    echo "[!] 拥塞算法: BBR 启用失败 (当前为 $BBR_STATUS)，可能是宿主机内核限制"
fi

# 检查 缓存
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem

# 检查 FastOpen
sysctl net.ipv4.tcp_fastopen

echo "------------------------------------------------"
echo "[*] 优化完成！"
echo "[*] 提示: 128MB 内存建议保持 4-8 线程使用，不建议超过 16 线程。"
