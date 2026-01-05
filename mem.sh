#!/bin/bash
# ZRAM + Swapfile + Swappiness 终极管理脚本
# Debian / Ubuntu

ZRAM_CONF="/etc/default/zramswap"
SWAP_FILE="/swapfile"
SYSCTL_CONF="/etc/sysctl.d/99-swappiness.conf"

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 运行"
  exit 1
fi

install_zram() {
  echo "[+] 安装 zram-tools..."
  apt update
  apt install -y zram-tools
}

set_zram_size() {
  read -rp "请输入 ZRAM 容量（MB，例如 1024）: " SIZE
  [[ "$SIZE" =~ ^[0-9]+$ ]] || { echo "❌ 必须是数字"; return; }

  [ -f "$ZRAM_CONF" ] || touch "$ZRAM_CONF"

  echo "[+] 禁用 ZRAM_PERCENT（防止覆盖）"
  sed -i 's/^ZRAM_PERCENT=.*/#ZRAM_PERCENT=/' "$ZRAM_CONF"

  if grep -q '^ZRAM_SIZE_MB=' "$ZRAM_CONF"; then
    sed -i "s/^ZRAM_SIZE_MB=.*/ZRAM_SIZE_MB=${SIZE}/" "$ZRAM_CONF"
  else
    echo "ZRAM_SIZE_MB=${SIZE}" >> "$ZRAM_CONF"
  fi

  echo "[+] 重建 zramswap..."
  systemctl stop zramswap 2>/dev/null || true
  modprobe -r zram 2>/dev/null || true
  systemctl start zramswap

  echo "[✓] ZRAM 已设置为 ${SIZE} MB"
}

zram_on() {
  systemctl enable --now zramswap
  echo "[✓] ZRAM 已启用"
}

zram_off() {
  systemctl disable --now zramswap
  echo "[✓] ZRAM 已停用"
}

create_swap() {
  read -rp "请输入 Swapfile 大小（GB，例如 1）: " SIZE
  [[ "$SIZE" =~ ^[0-9]+$ ]] || { echo "❌ 必须是数字"; return; }

  if swapon --show | grep -q "$SWAP_FILE"; then
    echo "⚠️ Swapfile 已存在并启用"
    return
  fi

  echo "[+] 创建 swapfile ${SIZE}G ..."
  fallocate -l ${SIZE}G "$SWAP_FILE" || dd if=/dev/zero of="$SWAP_FILE" bs=1G count="$SIZE"
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE"
  swapon "$SWAP_FILE"

  grep -q "$SWAP_FILE" /etc/fstab || echo "$SWAP_FILE none swap sw 0 0" >> /etc/fstab

  echo "[✓] Swapfile 创建并启用完成"
}

swap_off() {
  if swapon --show | grep -q "$SWAP_FILE"; then
    swapoff "$SWAP_FILE"
    echo "[✓] Swap 已停用"
  else
    echo "⚠️ Swap 未启用"
  fi
}

delete_swap() {
  swap_off
  sed -i "\|$SWAP_FILE|d" /etc/fstab
  rm -f "$SWAP_FILE"
  echo "[✓] Swapfile 已删除"
}

set_swappiness() {
  read -rp "请输入 vm.swappiness (0-100，推荐 zram+swap 用 80): " VALUE
  [[ "$VALUE" =~ ^([0-9]|[1-9][0-9]|100)$ ]] || {
    echo "❌ 必须是 0-100 的整数"
    return
  }

  sysctl -w vm.swappiness="$VALUE" >/dev/null

  cat >"$SYSCTL_CONF" <<EOF
vm.swappiness=${VALUE}
EOF

  sysctl --system >/dev/null
  echo "[✓] swappiness 已设置为 ${VALUE}"
}

status_all() {
  echo "===== 虚拟内存状态（zram / swap）====="
  swapon --show

  echo
  echo "===== 内存使用 ====="
  free -h

  echo
  echo "===== swappiness ====="
  cat /proc/sys/vm/swappiness
}

while true; do
  echo
  echo "========= 内存交换管理 ========="
  echo "1) 安装 zram-tools"
  echo "2) 设置 ZRAM 容量"
  echo "3) 启用 ZRAM"
  echo "4) 停用 ZRAM"
  echo "5) 创建并启用 Swapfile"
  echo "6) 停用 Swapfile"
  echo "7) 删除 Swapfile"
  echo "8) 设置 vm.swappiness"
  echo "9) 查看状态"
  echo "0) 退出"
  echo "================================"
  read -rp "请选择操作 [0-9]: " CHOICE

  case "$CHOICE" in
    1) install_zram ;;
    2) set_zram_size ;;
    3) zram_on ;;
    4) zram_off ;;
    5) create_swap ;;
    6) swap_off ;;
    7) delete_swap ;;
    8) set_swappiness ;;
    9) status_all ;;
    0) exit 0 ;;
    *) echo "❌ 无效选项" ;;
  esac
done
