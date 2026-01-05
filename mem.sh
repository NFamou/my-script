#!/bin/bash
# 一键配置 systemd-zram-generator + swappiness
# 只用 generator，兼容 Debian / Ubuntu

set -e

# ====== 配置参数 ======
ZRAM_SIZE_MB=1536        # zram 容量
SWAP_PRIORITY=100        # zram swap 优先级
COMPRESSION="zstd"       # 压缩算法
SWAPPINESS=80            # vm.swappiness 推荐 80

ZRAM_CONF="/etc/systemd/zram-generator.conf"

# ====== 1. 停用/卸载 zram-tools ======
if systemctl list-unit-files | grep -q zramswap; then
    echo "[+] 停用 zramswap 服务..."
    systemctl disable --now zramswap || true
fi

if dpkg -l | grep -q zram-tools; then
    echo "[+] 卸载 zram-tools..."
    apt remove -y zram-tools
fi

# ====== 2. 安装 systemd-zram-generator ======
if ! dpkg -l | grep -q systemd-zram-generator; then
    echo "[+] 安装 systemd-zram-generator..."
    apt update
    apt install -y systemd-zram-generator
fi

# ====== 3. 写 generator 配置 ======
echo "[+] 写入 generator 配置: $ZRAM_SIZE_MB MB"
cat > "$ZRAM_CONF" <<EOF
[zram0]
zram-size = ${ZRAM_SIZE_MB}M
swap-priority = ${SWAP_PRIORITY}
compression-algorithm = ${COMPRESSION}
EOF

# ====== 4. 设置 swappiness ======
echo "[+] 设置 vm.swappiness=${SWAPPINESS}"
sysctl -w vm.swappiness=$SWAPPINESS >/dev/null
echo "vm.swappiness=${SWAPPINESS}" > /etc/sysctl.d/99-swappiness.conf
sysctl --system >/dev/null

# ====== 5. 重建 zram ======
echo "[+] 停用旧 zram 设备并重建..."
swapoff /dev/zram0 2>/dev/null || true
systemctl daemon-reexec
systemctl restart systemd-zram-setup@zram0

# ====== 6. 验证 ======
echo
echo "===== 虚拟内存状态 ====="
swapon --show
echo
echo "===== 内存使用 ====="
free -h
echo
echo "===== swappiness ====="
cat /proc/sys/vm/swappiness

echo
echo "[✓] systemd-zram-generator 配置完成"
