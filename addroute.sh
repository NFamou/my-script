#!/bin/bash
# =================================================================
# V2bX 集成配置脚本
# =================================================================

set -e

# --- 基础路径 ---
CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
DEFAULT_API_RAW="https://node-api114514.6868319.xyz"
MONITOR_SCRIPT_PATH="/usr/local/bin/warp_keepalive.sh"

# ===============================
# 0️⃣ 依赖与环境检查
# ===============================
if [ "$EUID" -ne 0 ]; then echo "❌ 请使用 root 权限运行"; exit 1; fi

for cmd in jq curl; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "正在安装 $cmd..."
        apt update -y && apt install -y $cmd || yum install -y $cmd
    fi
done

# ===============================
# 1️⃣ 参数获取与方括号处理
# ===============================
echo "================ 1. 参数设置 ================"
read -p "请输入Xboard API地址: " INPUT_PREFIX
USER_PREFIX=${INPUT_PREFIX:-$DEFAULT_API_RAW}

# 修复方括号匹配逻辑
if [[ "$USER_PREFIX" == \[* ]]; then
    API_PREFIX="$USER_PREFIX"
else
    API_PREFIX="[$USER_PREFIX]"
fi
echo "📢 当前API地址: $API_PREFIX"

read -p "请输入 SOCKS5 端口 (回车默认使用 40000): " INPUT_V2BX_PORT
V2BX_PORT=${INPUT_V2BX_PORT:-40000}

# ===============================
# 2️⃣ 处理 Outbound 配置 (带报错捕获)
# ===============================
echo ""
echo "================ 2. 出口配置处理 ================"
[ ! -f "$OUTBOUND_FILE" ] && echo '{"outbounds":[]}' > "$OUTBOUND_FILE"

# 递归查重
if jq -e '.. | select(.tag? == "socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
    echo "✅ socks5-warp 出口已存在，跳过。"
else
    echo "正在添加出口配置..."
    # 尝试修改并捕获错误
    if ! ERROR_MSG=$(jq --argjson port "$V2BX_PORT" '
        if type == "array" then
            . += [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }]
        elif type == "object" then
            .outbounds |= (. // []) + [{ "tag": "socks5-warp", "protocol": "socks", "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] } }]
        else
            error("JSON 顶层必须是 array 或 object")
        end
    ' "$OUTBOUND_FILE" 2>&1 > "$TMP_FILE"); then
        echo "❌ $OUTBOUND_FILE 修改失败！"
        echo "错误详情: $ERROR_MSG"
        exit 1
    fi
    mv "$TMP_FILE" "$OUTBOUND_FILE"
    echo "✅ 出口配置添加成功。"
fi

# ===============================
# 3️⃣ 路由规则处理 (带报错捕获)
# ===============================
echo ""
echo "================ 3. 路由规则绑定 ================"
echo "1) Shadowsocks  2) Trojan  3) Vless"
read -p "请选择协议 [1-3]: " TYPE_CHOICE
case "$TYPE_CHOICE" in
    1) PROTO="shadowsocks" ;; 2) PROTO="trojan" ;; 3) PROTO="vless" ;; *) echo "❌ 无效选择"; exit 1 ;;
esac

read -p "请输入入站 ID: " PORT
INBOUND_TAG="${API_PREFIX}-${PROTO}:${PORT}"

if [ ! -f "$CONFIG_FILE" ]; then echo "❌ 未找到 $CONFIG_FILE"; exit 1; fi

# 强化查重 (匹配 :PORT)
if jq -e --arg id ":$PORT" '.rules[]? | .inboundTag[]? | select(contains($id))' "$CONFIG_FILE" >/dev/null 2>&1; then
    echo "⚠️  查重拦截：ID [$PORT] 规则已存在。"
else
    echo "正在插入路由规则..."
    if ! ERROR_MSG=$(jq --arg tag "$INBOUND_TAG" '
        .rules |= (. // []) |
        (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |
        if $hasOut then
          .rules |= map(if .outboundTag == "IPv4_out" then ({"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}, .) else . end)
        else
          .rules += [{"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}]
        end
    ' "$CONFIG_FILE" 2>&1 > "$TMP_FILE"); then
        echo "❌ $CONFIG_FILE 修改失败！"
        echo "错误详情: $ERROR_MSG"
        exit 1
    fi
    mv "$TMP_FILE" "$CONFIG_FILE"
    echo "✅ 路由规则绑定成功: $INBOUND_TAG"
fi

# ===============================
# 4️⃣ 服务管理与保活
# ===============================
echo ""
read -p "是否立即重启 V2bX? (y/n): " RESTART_CHOICE
[[ "$RESTART_CHOICE" =~ ^[yY]$ ]] && systemctl restart V2bX && echo "✅ V2bX 已重启"

echo ""
read -p "是否安装 WARP 自动保活脚本? (y/n): " ADD_MONITOR
if [[ "$ADD_MONITOR" =~ ^[yY]$ ]]; then
    read -p "检测端口 (默认 $V2BX_PORT): " M_PORT
    MONITOR_PORT=${M_PORT:-$V2BX_PORT}
    echo "重启模式: 1) warp y  2) warp r"
    read -p "请选择: " M_CHOICE
    [ "$M_CHOICE" == "1" ] && TARGET_CMD="warp y" || TARGET_CMD="warp r"

    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
PROXY="127.0.0.1:$MONITOR_PORT"
if ! curl --socks5 "\$PROXY" -s --max-time 10 "https://www.cloudflare.com/cdn-cgi/trace" | grep -Eq "warp=(on|plus)|warp-r"; then
    echo "[\$(date)] 重启 WARP: $TARGET_CMD"
    $TARGET_CMD
fi
EOF
    chmod +x "$MONITOR_SCRIPT_PATH"
    (crontab -l 2>/dev/null | grep -Fv "$MONITOR_SCRIPT_PATH"; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1") | crontab -
    echo "✅ 保活任务已就绪 (每5分钟检测)。"
fi

echo -e "\n🎉 脚本流程执行完毕！"
