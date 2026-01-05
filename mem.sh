#!/bin/bash
# zram 管理脚本（增强版）
CONFIG_FILE="/etc/default/zramswap"

# 检查是否 root
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

# 检测 zram-tools 是否安装
function check_install() {
    if ! command -v zramswapctl &>/dev/null && ! dpkg -l | grep -q zram-tools; then
        echo "⚠️ zram-tools 未安装"
        read -p "是否现在安装？[y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            apt update && apt install -y zram-tools
            echo "✅ zram-tools 已安装"
        else
            echo "❌ 脚本无法继续，退出"
            exit 1
        fi
    fi
}

# 查看当前 zram 状态
function view_zram() {
    echo "===== 当前 zram 状态 ====="
    swapon --show
    free -h | grep -i swap
    if [ -f "$CONFIG_FILE" ]; then
        grep -i ZRAM_SIZE_MB $CONFIG_FILE
    fi
    echo "========================="
}

# 获取总内存 (MB)
function get_mem_mb() {
    awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo
}

# 修改 zram 大小
function modify_zram() {
    total_mem=$(get_mem_mb)
    echo "💡 系统总内存: ${total_mem} MB"
    read -p "请输入新的 zram 大小 (MB, 建议不超过总内存一半): " new_size

    if ! [[ "$new_size" =~ ^[0-9]+$ ]]; then
        echo "❌ 输入不合法"
        return
    fi

    if [ "$new_size" -gt "$total_mem" ]; then
        echo "❌ 警告：zram 大小超过系统总内存，可能启动失败"
        read -p "是否继续？[y/N]: " confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "取消修改"
            return
        fi
    fi

    # 修改配置文件
    if grep -q "^#*SIZE=" $CONFIG_FILE; then
        sed -i "s/^#*SIZE=.*/SIZE=$new_size/" $CONFIG_FILE
    else
        echo "SIZE=$new_size" >> $CONFIG_FILE
    fi

    echo "✅ zram 大小已修改为 ${new_size}MB"
    echo "重启 zram 服务中..."
    swapoff -a
    systemctl restart zramswap
    swapon -a
    echo "✅ zram 已重启"
}

# 菜单
check_install
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
        3) swapoff -a && systemctl restart zramswap && swapon -a && echo "✅ zram 已重启" ;;
        0) exit 0 ;;
        *) echo "❌ 无效选项" ;;
    esac
done
