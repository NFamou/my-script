#!/bin/bash
# =================================================================
# V2bX 模块配置工具
# =================================================================

set -e

# --- 基础配置 ---
CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
DEFAULT_API_RAW="https://node-api114514.6868319.xyz"
MONITOR_SCRIPT_PATH="/usr/local/bin/warp_keepalive.sh"

# ===============================
# 🔧 内部工具函数
# ===============================

init_env() {
    if [ "$EUID" -ne 0 ]; then echo "❌ 请使用 root 权限运行"; exit 1; fi
    for cmd in jq curl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo "正在安装 $cmd..."
            apt update -y && apt install -y $cmd || yum install -y $cmd
        fi
    done
}

# 1. 添加出口配置
add_outbound() {
    echo -e "\n--- [出口配置处理] ---"
    read -p "请输入 WARP SOCKS5 端口 (回车默认使用 40000): " INPUT_PORT
    local port=${INPUT_PORT:-40000}
    [ ! -f "$OUTBOUND_FILE" ] && echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
    if jq -e '.. | select(.tag? == "socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        echo "✅ socks5-warp 出口已存在。如需修改端口，请手动编辑 $OUTBOUND_FILE"
    else
        if ! ERROR_MSG=$(jq --argjson port "$port" '
            if type == "array" then . += [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }]
            elif type == "object" then .outbounds |= (. // []) + [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }]
            else error("JSON 格式错误") end
        ' "$OUTBOUND_FILE" 2>&1 > "$TMP_FILE"); then
            echo "❌ 失败: $ERROR_MSG"; else mv "$TMP_FILE" "$OUTBOUND_FILE"; echo "✅ 出口配置成功。"; fi
    fi
}

# 2. 绑定路由规则
add_route() {
    echo -e "\n--- [路由规则绑定] ---"
    read -p "请输入 Xboard API地址: " INPUT_PREFIX
    local user_prefix=${INPUT_PREFIX:-$DEFAULT_API_RAW}
    local api_prefix; if [[ "$user_prefix" == \[* ]]; then api_prefix="$user_prefix"; else api_prefix="[$user_prefix]"; fi
    echo "1) Shadowsocks  2) Trojan  3) Vless"
    read -p "请选择协议 [1-3]: " TYPE_CHOICE
    local proto; case "$TYPE_CHOICE" in 1) proto="shadowsocks" ;; 2) proto="trojan" ;; 3) proto="vless" ;; *) return ;; esac
    read -p "请输入入站 ID (端口号): " port_id
    local inbound_tag="${api_prefix}-${proto}:${port_id}"
    if jq -e --arg id ":$port_id" '.rules[]? | .inboundTag[]? | select(contains($id))' "$CONFIG_FILE" >/dev/null 2>&1; then
        echo "⚠️  ID [$port_id] 已存在，跳过。"; return; fi
    if ! ERROR_MSG=$(jq --arg tag "$inbound_tag" '
        .rules |= (. // []) | (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |
        if $hasOut then .rules |= map(if .outboundTag == "IPv4_out" then ({"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}, .) else . end)
        else .rules += [{"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}] end
    ' "$CONFIG_FILE" 2>&1 > "$TMP_FILE"); then
        echo "❌ 失败: $ERROR_MSG"; else mv "$TMP_FILE" "$CONFIG_FILE"; echo "✅ 绑定成功: $inbound_tag"; fi
}

# 3. 查看当前配置概览
show_status() {
    echo -e "\n================ [ 当前配置概览 ] ================"
    
    # 1. 检查出口
    local out_port=$(jq -r '.. | select(.tag? == "socks5-warp") | .settings.servers[0].port // "未配置"' "$OUTBOUND_FILE" 2>/dev/null || echo "文件解析错误")
    echo -e "🟢 WARP 出口端口: \033[32m$out_port\033[0m"

    # 2. 检查绑定的节点
    echo -e "🔵 已绑定 WARP 的节点 ID:"
    local nodes=$(jq -r '.rules[] | select(.outboundTag == "socks5-warp") | .inboundTag[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -z "$nodes" ]; then
        echo "   (暂无绑定节点)"
    else
        echo "$nodes" | sed 's/^/   - /'
    fi

    # 3. 检查保活脚本
    echo -n "🟡 WARP 保活任务: "
    if crontab -l 2>/dev/null | grep -Fq "$MONITOR_SCRIPT_PATH"; then
        echo -e "\033[32m✅ 已开启 (每5分钟检测一次)\033[0m"
    else
        echo -e "\033[31m❌ 未开启\033[0m"
    fi
    echo "=================================================="
}

# 4. 添加 WARP 保活
setup_keepalive() {
    echo -e "\n--- [WARP 自动保活配置] ---"
    read -p "请输入检测端口 (回车默认使用 40000): " INPUT_PORT
    local m_port=${INPUT_PORT:-40000}
    echo "1) warp y (WARP WireProxy) 2) warp r (WARP ClientProxy)"
    read -p "请选择模式: " M_CHOICE
    local cmd; [ "$M_CHOICE" == "1" ] && cmd="warp y" || cmd="warp r"
    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
PROXY="127.0.0.1:$m_port"
if ! curl --socks5 "\$PROXY" -s --max-time 10 "https://www.cloudflare.com/cdn-cgi/trace" | grep -Eq "warp=(on|plus)|warp-r"; then
    echo "[\$(date)] 重启 WARP: $cmd"; $cmd
fi
EOF
    chmod +x "$MONITOR_SCRIPT_PATH"
    (crontab -l 2>/dev/null | grep -Fv "$MONITOR_SCRIPT_PATH"; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1") | crontab -
    echo "✅ 保活已就绪。"
}

restart_v2bx() { systemctl restart V2bX && echo "✅ V2bX 已重启"; }

# ===============================
# 📱 主菜单
# ===============================
init_env
while true; do
    echo -e "\n1. 添加出口 | 2. 添加路由 | 3. 添加WARP保活 | 4. 重启服务 | \033[33m5. 查看概览\033[0m | 0. 退出"
    read -p "请选择 [0-5]: " choice
    case "$choice" in
        1) add_outbound ;; 2) add_route ;; 3) setup_keepalive ;; 4) restart_v2bx ;; 5) show_status ;; 0) exit 0 ;; *) echo "❌ 无效输入" ;;
    esac
    read -p "按回车返回..."
done
