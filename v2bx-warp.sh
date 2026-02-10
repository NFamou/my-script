#!/bin/bash
# =================================================================
# V2bX 路由配置 + WARP 自动保活集成脚本 (自定义端口版)
# =================================================================

set -e

# --- 基础配置 ---
CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
API_PREFIX="[https://node-api114514.6868319.xyz]"
MONITOR_SCRIPT_PATH="/usr/local/bin/warp_keepalive.sh"

# ===============================
# 0️⃣ 环境检查
# ===============================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行该脚本"
  exit 1
fi

echo "🔍 正在检查系统依赖..."
PACKAGES_NEEDED=""
if ! command -v jq >/dev/null 2>&1; then PACKAGES_NEEDED="$PACKAGES_NEEDED jq"; fi
if ! command -v curl >/dev/null 2>&1; then PACKAGES_NEEDED="$PACKAGES_NEEDED curl"; fi

if [ -n "$PACKAGES_NEEDED" ]; then
  echo "⚠️ 正在安装缺少组件: $PACKAGES_NEEDED ..."
  if [ -f /etc/debian_version ]; then
    apt update -y && apt install -y $PACKAGES_NEEDED
  elif [ -f /etc/redhat-release ]; then
    dnf install -y $PACKAGES_NEEDED || yum install -y $PACKAGES_NEEDED
  else
    echo "❌ 无法自动安装依赖，请手动安装 jq 和 curl"
    exit 1
  fi
fi

# ===============================
# 1️⃣ 配置 socks5-warp Outbound (V2bX侧)
# ===============================
echo ""
echo "================ 1. V2bX Outbound 配置 ================"
read -p "请输入 WARP 本地 SOCKS5 端口 (默认 40000): " INPUT_V2BX_PORT
V2BX_PORT=${INPUT_V2BX_PORT:-40000}

if [ ! -f "$OUTBOUND_FILE" ]; then
  echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
fi

# 检查是否已存在 tag="socks5-warp"
if jq -e '.[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1 \
   || jq -e '.outbounds[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
  echo "⚠️  socks5-warp outbound 已存在，跳过添加 (请确认端口是否匹配)。"
else
  # 构造 JSON 对象
  SERVER_OBJ=$(jq -n --argjson port "$V2BX_PORT" '{
    "tag": "socks5-warp",
    "protocol": "socks",
    "settings": {
      "servers": [{"address": "127.0.0.1", "port": $port}]
    }
  }')

  TOP_TYPE=$(jq -r 'type' "$OUTBOUND_FILE")
  if [ "$TOP_TYPE" = "array" ]; then
    jq ". += [$SERVER_OBJ]" "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
    echo "✅ 已添加 outbound (数组模式)，端口: $V2BX_PORT"
  elif [ "$TOP_TYPE" = "object" ]; then
    jq ".outbounds |= (. // []) + [$SERVER_OBJ]" "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
    echo "✅ 已添加 outbound (对象模式)，端口: $V2BX_PORT"
  else
    echo "❌ JSON 结构异常，无法添加"
    exit 1
  fi
fi

# ===============================
# 2️⃣ 配置路由规则 (Route)
# ===============================
echo ""
echo "================ 2. 路由规则绑定 ================"
echo "请选择入站类型："
echo "1) Shadowsocks"
echo "2) Trojan"
echo "3) VLESS"
read -p "请输入编号 (1/2/3): " TYPE_CHOICE

case "$TYPE_CHOICE" in
  1) read -p "请输入 Shadowsocks ID: " PORT; INBOUND_TAG="${API_PREFIX}-shadowsocks:${PORT}" ;;
  2) read -p "请输入 Trojan ID: " PORT; INBOUND_TAG="${API_PREFIX}-trojan:${PORT}" ;;
  3) read -p "请输入 VLESS ID: " PORT; INBOUND_TAG="${API_PREFIX}-vless:${PORT}" ;;
  *) echo "❌ 输入无效"; exit 1 ;;
esac

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 未找到 $CONFIG_FILE，跳过路由配置。"
else
    # 检查规则是否存在
    if jq -e --arg tag "$INBOUND_TAG" '.rules[]? | select(.inboundTag[]? == $tag)' "$CONFIG_FILE" >/dev/null 2>&1; then
      echo "⚠️  已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
    else
      jq --arg tag "$INBOUND_TAG" '
        .rules |= (. // []) |
        (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |
        if $hasOut then
          .rules |= map(if .outboundTag == "IPv4_out" then ({"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}, .) else . end)
        else
          .rules += [{"type": "field", "outboundTag": "socks5-warp", "inboundTag": [$tag], "network": "udp,tcp"}]
        end
      ' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"
      echo "✅ 已插入路由规则 -> $INBOUND_TAG"
    fi
fi

# ===============================
# 3️⃣ V2bX 重启
# ===============================
echo ""
read -p "是否立即重启 V2bX 服务? (y/n): " RESTART_CHOICE
if [[ "$RESTART_CHOICE" =~ ^[yY]$ ]]; then
  systemctl restart V2bX && echo "✅ V2bX 重启成功" || echo "❌ V2bX 重启失败"
fi

# ===============================
# 4️⃣ WARP 自动保活配置 (独立端口)
# ===============================
echo ""
echo "================ 3. WARP 自动保活配置 ================"
echo "配置独立的 Crontab 任务来检测代理通断并自动重启 WARP。"
read -p "是否配置自动保活? (y/n): " ADD_MONITOR

if [[ "$ADD_MONITOR" =~ ^[yY]$ ]]; then
  
  # 独立询问保活端口，不与 V2bX 配置强关联
  read -p "请输入要检测的 SOCKS5 端口 (回车默认使用 $V2BX_PORT): " INPUT_MONITOR_PORT
  MONITOR_PORT=${INPUT_MONITOR_PORT:-$V2BX_PORT}

  echo ""
  echo "请选择 WARP 启动/重启命令："
  echo "  1) warp y (WireGuard Proxy)"
  echo "  2) warp r (Client Proxy)"
  read -p "请输入选项 [1-2]: " MODE_CHOICE

  case "$MODE_CHOICE" in
      1) TARGET_CMD="warp y" ;;
      2) TARGET_CMD="warp r" ;;
      *) echo "❌ 无效选择，跳过保活配置"; TARGET_CMD="" ;;
  esac

  if [ -n "$TARGET_CMD" ]; then
    # 生成保活脚本
    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
# WARP Keep-alive script
# Mode: $TARGET_CMD
# Port: $MONITOR_PORT

CHECK_URL="https://www.cloudflare.com/cdn-cgi/trace"
PROXY_ADDR="127.0.0.1:$MONITOR_PORT"
WARP_CMD="$TARGET_CMD"
CURL_TIMEOUT=10

check_warp() {
    curl --socks5 "\$PROXY_ADDR" -s --max-time "\$CURL_TIMEOUT" "\$CHECK_URL"
}

# 1. 检测
TRACE_RESULT=\$(check_warp)

# 2. 如果失败则重启
if [ -z "\$TRACE_RESULT" ]; then
    echo "[\$(date)] ❌ 检测失败 (Port: $MONITOR_PORT)，执行: \$WARP_CMD"
    \$WARP_CMD
    sleep 5
fi
EOF

    chmod +x "$MONITOR_SCRIPT_PATH"
    echo "✅ 保活脚本生成于: $MONITOR_SCRIPT_PATH (检测端口: $MONITOR_PORT)"

    # 添加 Crontab
    CRON_CMD="*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1"
    EXISTING_CRON=$(crontab -l 2>/dev/null || true)

    if echo "$EXISTING_CRON" | grep -Fq "$MONITOR_SCRIPT_PATH"; then
      echo "⚠️  Crontab 任务已存在，跳过。"
    else
      (echo "$EXISTING_CRON"; echo "$CRON_CMD") | crontab -
      echo "✅ Crontab 添加成功 (每5分钟执行)。"
    fi
  fi
else
  echo "⏭️  已跳过保活配置。"
fi

echo ""
echo "🎉 全部完成"
