#!/bin/bash
# =================================================================
# V2bX 路由配置 + WARP 自动保活集成脚本 (强化 ID 查重版)
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
# 1️⃣ 配置 socks5-warp Outbound (出口查重)
# ===============================
echo ""
echo "================ 1. V2bX Outbound 配置 ================"
read -p "请输入 WARP 本地 SOCKS5 端口 (默认 40000): " INPUT_V2BX_PORT
V2BX_PORT=${INPUT_V2BX_PORT:-40000}

if [ ! -f "$OUTBOUND_FILE" ]; then
  echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
fi

# 查重：标签 tag 为 socks5-warp
if jq -e '.[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1 \
   || jq -e '.outbounds[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
  echo "⚠️  socks5-warp 出口配置已存在，跳过添加。"
else
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
  elif [ "$TOP_TYPE" = "object" ]; then
    jq ".outbounds |= (. // []) + [$SERVER_OBJ]" "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
  fi
  echo "✅ 已成功添加 socks5-warp 出口配置。"
fi

# ===============================
# 2️⃣ 配置路由规则 (ID 强化查重)
# ===============================
echo ""
echo "================ 2. 路由规则绑定 ================"
echo "请选择入站协议类型："
echo "1) Shadowsocks"
echo "2) Trojan"
echo "3) Vless"
read -p "请输入编号 (1/2/3): " TYPE_CHOICE

case "$TYPE_CHOICE" in
  1) read -p "请输入 ID (端口号): " PORT; INBOUND_TAG="${API_PREFIX}-shadowsocks:${PORT}" ;;
  2) read -p "请输入 ID (端口号): " PORT; INBOUND_TAG="${API_PREFIX}-trojan:${PORT}" ;;
  3) read -p "请输入 ID (端口号): " PORT; INBOUND_TAG="${API_PREFIX}-vless:${PORT}" ;;
  *) echo "❌ 无效输入"; exit 1 ;;
esac

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 配置文件 $CONFIG_FILE 不存在"
else
    # 【强化查重】：只检测 ID（如 :379），不检测前面的协议字符串
    if jq -e --arg id ":$PORT" '.rules[]? | .inboundTag[]? | select(contains($id))' "$CONFIG_FILE" >/dev/null 2>&1; then
      echo "⚠️  查重失败：ID [$PORT] 已存在于路由规则中（无论何种协议），操作已取消。"
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
      echo "✅ 已成功插入路由规则: $INBOUND_TAG -> socks5-warp"
    fi
fi

# ===============================
# 3️⃣ V2bX 重启
# ===============================
echo ""
read -p "是否立即重启 V2bX 服务? (y/n): " RESTART_CHOICE
if [[ "$RESTART_CHOICE" =~ ^[yY]$ ]]; then
  systemctl restart V2bX && echo "✅ V2bX 已重启" || echo "❌ 重启失败，请手动检查"
fi

# ===============================
# 4️⃣ WARP 自动保活配置 (独立端口)
# ===============================
echo ""
echo "================ 3. WARP 自动保活配置 ================"
read -p "是否添加 WARP 定时检测任务? (y/n): " ADD_MONITOR

if [[ "$ADD_MONITOR" =~ ^[yY]$ ]]; then
  read -p "请输入要检测的 SOCKS5 端口 (默认使用 $V2BX_PORT): " INPUT_MONITOR_PORT
  MONITOR_PORT=${INPUT_MONITOR_PORT:-$V2BX_PORT}

  echo "请选择 WARP 重启方式："
  echo "  1) warp y (WireGuard)"
  echo "  2) warp r (Client)"
  read -p "请选择 [1-2]: " MODE_CHOICE

  case "$MODE_CHOICE" in
      1) TARGET_CMD="warp y" ;;
      2) TARGET_CMD="warp r" ;;
      *) TARGET_CMD="" ;;
  esac

  if [ -n "$TARGET_CMD" ]; then
    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
# WARP 保活脚本 - 检测端口: $MONITOR_PORT
CHECK_URL="https://www.cloudflare.com/cgi-bin/trace"
PROXY="127.0.0.1:$MONITOR_PORT"
if ! curl --socks5 "\$PROXY" -s --max-time 10 "\$CHECK_URL" | grep -q "warp=on\|warp=plus\|warp-r"; then
    echo "[\$(date)] ⚠️ WARP 异常，尝试执行: $TARGET_CMD"
    $TARGET_CMD
fi
EOF
    chmod +x "$MONITOR_SCRIPT_PATH"

    # Crontab 查重
    if ! crontab -l 2>/dev/null | grep -Fq "$MONITOR_SCRIPT_PATH"; then
      (crontab -l 2>/dev/null; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1") | crontab -
      echo "✅ Crontab 任务已添加 (每5分钟执行一次)。"
    else
      echo "⚠️ Crontab 任务已存在，跳过添加。"
    fi
  fi
fi

echo ""
echo "🎉 所有流程已处理完毕。"
