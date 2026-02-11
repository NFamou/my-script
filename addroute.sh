#!/bin/bash
# =================================================================
# V2bX 模块配置工具 (含实时出口实时测试)
# =================================================================

set -e

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' 

# --- 基础配置 ---
CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
DEFAULT_API_RAW="https://node-api114514.6868319.xyz"
MONITOR_SCRIPT_PATH="/usr/local/bin/warp_keepalive.sh"

# ===============================
# 🔧 内部工具函数
# ===============================

print_title() {
    clear
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${CYAN}          V2bX & WARP 自动化集成工具              ${NC}"
    echo -e "${BLUE}==================================================${NC}"
}

print_ok() { echo -e "${GREEN}✅ $1${NC}"; }
print_warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }

init_env() {
    if [ "$EUID" -ne 0 ]; then print_error "请使用 root 权限运行"; exit 1; fi
    for cmd in jq curl; do
        if ! command -v $cmd >/dev/null 2>&1; then
            echo -e "${YELLOW}正在安装必要组件 $cmd...${NC}"
            apt update -y && apt install -y $cmd || yum install -y $cmd
        fi
    done
}

# 1. 添加出口配置 (代码同前，未变)
add_outbound() {
    echo -e "\n${PURPLE}--- [ 1. 添加出口配置 ] ---${NC}"
    read -p "请输入 WARP SOCKS5 端口 (回车默认 40000): " INPUT_PORT
    local port=${INPUT_PORT:-40000}
    [ ! -f "$OUTBOUND_FILE" ] && echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
    if jq -e '.. | select(.tag? == "socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
        print_warn "socks5-warp 出口已存在。"; else
        if ! ERROR_MSG=$(jq --argjson port "$port" 'if type == "array" then . += [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }] elif type == "object" then .outbounds |= (. // []) + [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }] else error("JSON 格式错误") end' "$OUTBOUND_FILE" 2>&1 > "$TMP_FILE"); then
            print_error "修改失败: $ERROR_MSG"; else mv "$TMP_FILE" "$OUTBOUND_FILE"; print_ok "出口配置成功。"; fi
    fi
}

# 2. 添加路由规则 (代码同前，未变)
add_route() {
    echo -e "\n${PURPLE}--- [ 2. 添加路由规则 ] ---${NC}"
    read -p "请输入 Xboard API地址: " INPUT_PREFIX
    local user_prefix=${INPUT_PREFIX:-$DEFAULT_API_RAW}
    local api_prefix; if [[ "$user_prefix" == \[* ]]; then api_prefix="$user_prefix"; else api_prefix="[$user_prefix]"; fi
    echo -e "请选择协议类型:\n  ${CYAN}1)${NC} Shadowsocks  ${CYAN}2)${NC} Trojan  ${CYAN}3)${NC} Vless"
    read -p "选择 [1-3]: " TYPE_CHOICE
    local proto; case "$TYPE_CHOICE" in 1) proto="shadowsocks" ;; 2) proto="trojan" ;; 3) proto="vless" ;; *) return ;; esac
    read -p "请输入入站 ID: " port_id
    local inbound_tag="${api_prefix}-${proto}:${port_id}"
    if jq -e --arg id ":$port_id" '.rules[]? | .inboundTag[]? | select(contains($id))' "$CONFIG_FILE" >/dev/null 2>&1; then
        print_warn "ID [$port_id] 已绑定路由，跳过。"; return; fi
    if ! ERROR_MSG=$(jq --arg tag "$inbound_tag" '.rules |= (. // []) | (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut | if $hasOut then .rules |= map(if .outboundTag == "IPv4_out" then ({"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}, .) else . end) else .rules += [{"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}] end' "$CONFIG_FILE" 2>&1 > "$TMP_FILE"); then
        print_error "修改失败: $ERROR_MSG"; else mv "$TMP_FILE" "$CONFIG_FILE"; print_ok "绑定成功。"; fi
}

# 3. 🚀 查看状态仪表盘 (新增实时测试功能)
show_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║             📊  V2bX 配置 & 实时连接测试          ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # --- 1. 基础服务 & 出口实测 ---
    echo -e "${CYAN}📌 基础服务状态${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────${NC}"
    
    local out_port=$(jq -r '.. | select(.tag? == "socks5-warp") | .settings.servers[0].port // "未配置"' "$OUTBOUND_FILE" 2>/dev/null || echo "未配置")
    
    printf "  %-16s" "📡 WARP 出口:"
    if [[ "$out_port" == "未配置" ]]; then
        echo -e "${RED}未配置${NC}"
    else
        echo -ne "${GREEN}已配置${NC} (端口: $out_port)"
        # 实时出口网络测试
        echo -ne " -> "
        local start_time=$(date +%s%3N)
        # 尝试通过本地 WARP 端口访问谷歌 (http测试)
        if res=$(curl --socks5 "127.0.0.1:$out_port" -sI --max-time 3 "http://www.google.com/generate_204" | grep "HTTP"); then
            local end_time=$(date +%s%3N)
            local diff=$((end_time - start_time))
            echo -e "${GREEN}[ 连通 ]${NC} ${YELLOW}${diff}ms${NC}"
        else
            echo -e "${RED}[ 阻塞 ]${NC}"
        fi
    fi

    printf "  %-16s" "⏰ 自动保活:"
    if crontab -l 2>/dev/null | grep -Fq "$MONITOR_SCRIPT_PATH"; then
        echo -e "${GREEN}已开启${NC} (5min/周期)"
    else
        echo -e "${RED}未开启${NC}"
    fi
    echo ""

    # --- 2. 节点列表 ---
    echo -e "${CYAN}📌 路由规则详情${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────${NC}"
    
    local nodes=$(jq -r '.rules[] | select(.outboundTag == "socks5-warp") | .inboundTag[]' "$CONFIG_FILE" 2>/dev/null || echo "")
    if [ -z "$nodes" ]; then
        echo -e "   ${YELLOW}(当前暂无绑定的节点 ID)${NC}"
    else
        local count=$(echo "$nodes" | wc -l)
        echo "$nodes" | sed "s/^/   ${PURPLE}●${NC} /"
        echo -e "\n   ---------------------------------"
        echo -e "   📊 共计绑定节点: ${GREEN}$count${NC} 个"
    fi
    
    echo -e ""
    echo -e "${BLUE}══════════════════════════════════════════════════════${NC}"
}

# 4. 保活配置 (代码同前，未变)
setup_keepalive() {
    echo -e "\n${PURPLE}--- [ 3. 添加 WARP 保活任务 ] ---${NC}"
    read -p "请输入检测端口 (回车默认 40000): " INPUT_PORT
    local m_port=${INPUT_PORT:-40000}
    echo -e "选择保活执行模式:\n  ${CYAN}1)${NC} warp y\n  ${CYAN}2)${NC} warp r"
    read -p "选择 [1-2]: " M_CHOICE
    local cmd; [ "$M_CHOICE" == "1" ] && cmd="warp y" || cmd="warp r"
    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
PROXY="127.0.0.1:$m_port"
if ! curl --socks5 "\$PROXY" -s --max-time 10 "https://www.cloudflare.com/cdn-cgi/trace" | grep -Eq "warp=(on|plus)|warp-r"; then
    echo "[\$(date)] 检测到异常，重启: $cmd"; $cmd
fi
EOF
    chmod +x "$MONITOR_SCRIPT_PATH"
    (crontab -l 2>/dev/null | grep -Fv "$MONITOR_SCRIPT_PATH"; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1") | crontab -
    print_ok "保活任务已写入。"
}

# 5. 重启
restart_v2bx() {
    echo -e "\n${YELLOW}正在重启 V2bX 服务...${NC}"
    systemctl restart V2bX && print_ok "重启成功！" || print_error "重启失败。"
}

# ===============================
# 📱 主菜单
# ===============================
init_env
while true; do
    print_title
    echo -e "  ${CYAN}1.${NC} 添加出口配置 (Outbound)"
    echo -e "  ${CYAN}2.${NC} 添加路由绑定 (Route)"
    echo -e "  ${CYAN}3.${NC} WARP 配置保活 (Keepalive Warp)"
    echo -e "  ${CYAN}4.${NC} 重启 V2bX 服务"
    echo -e "  ${YELLOW}5. 查看概览 & 实时网络测试 (Dashboard)${NC}"
    echo -e "  ${RED}0. 退出脚本${NC}"
    echo -e "${BLUE}==================================================${NC}"
    read -p "请选择操作 [0-5]: " choice
    case "$choice" in 1) add_outbound ;; 2) add_route ;; 3) setup_keepalive ;; 4) restart_v2bx ;; 5) show_status ;; 0) exit 0 ;; *) print_error "无效选择" ;; esac
    echo -e ""
    read -p "按回车键返回菜单..."
done
