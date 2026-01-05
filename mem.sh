#!/bin/bash
# zram 管理脚本
# 支持查看、修改、重启 zram
# 适用于 Debian / Ubuntu

CONFIG_FILE="/etc/default/zramswap"

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

# 查看当前 zram 状态
function view_zram() {
    echo "===== 当前 zram 状态 ====="
    swapon --show
    free -h | grep -i swap
    grep -i ZRAM_SIZE_MB $CONFIG_FILE
    echo "========================="
}

# 修改 zram 大小
function modify_zram() {
    read -p "请输入新的 zram 大小 (MB): " new_size
    if ! [[ "$new_size" =~ ^[0-9]+$ ]]; then
        echo "❌ 输入不合法"
        return
    fi
    # 删除注释并修改
    if grep -q "^#*ZRAM_SIZE_MB=" $CONFIG_FILE; then
        sed -i "s/^#*ZRAM_SIZE_MB=.*/ZRAM_SIZE_MB=$new_size/" $CONFIG_FILE
    else
        echo "ZRAM_SIZE_MB=$new_size" >> $CONFIG_FILE
    fi
    echo "✅ zram 大小已修改为 ${new_size}MB"
    echo "重启 zram 服务中..."
    systemctl restart zramswap
    echo "✅ zram 已重启"
}

# 菜单
while true; do
    echo "===== zram 管理脚本 ====="
    echo "1) 查看 zram 状态"
    echo "2) 修改 zram 大小"
    echo "3) 重启 zram"
    echo "0) 退出"
    read -p "请选择操作 [0-3]: " choice
    case "$choice" in
        1) view_zram ;;
        2) modify_zram ;;
        3) systemctl restart zramswap && echo "✅ zram 已重启" ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done
