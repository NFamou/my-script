#!/bin/bash
# =================================================================
# V2bX 路由配置 + WARP 自动保活集成脚本 (智能前缀 & ID 查重版)
# =================================================================

set -e

# --- 基础路径配置 ---
CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
DEFAULT_API_RAW="https://node-api114514.6868319.xyz"
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
  echo "⚠️ 正在安装缺失组件: $PACKAGES_NEEDED ..."
  if [ -f /etc/debian_version ]; then
    apt update -y && apt install -y $PACKAGES_NEEDED
  elif [ -f /etc/redhat-release ]; then
    dnf install -y $PACKAGES_NEEDED || yum install -y $PACKAGES_NEEDED
  fi
fi

# ===============================
# 1️⃣ 参数设置 (API 前缀自动补全)
# ===============================
echo ""
echo "================ 1. 全局参数设置 ================"
read -p "请输入Xboard API地址(需带https://): " INPUT_PREFIX
USER_PREFIX=${INPUT_PREFIX:-$DEFAULT_API_RAW}

# 智能补全方括号
if [[ "$USER_PREFIX" == [* ]]; then
    API_PREFIX="$USER_PREFIX"
else
    API_PREFIX="[$USER_PREFIX]"
fi
echo "📢 当前使用的API地址: $API_PREFIX"

read -p "请输入 WARP 本地 SOCKS5 端口 (回车默认使用 40000): " INPUT_V2BX_PORT
V2BX_PORT=${INPUT_V2BX_PORT:-40000}

# --- 出口配置查重 ---
if [ ! -f "$OUTBOUND_FILE" ]; then echo '{"outbounds":[]}' > "$OUTBOUND_FILE"; fi
if jq -e '.[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1 \
   || jq -e '.outbounds[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
  echo "✅ socks5-warp 出口已存在，跳过配置。"
else
  SERVER_OBJ=$(jq -n --argjson port "$V2BX_PORT" '{
    "tag": "socks5-warp",
    "protocol": "socks",
    "settings": { "servers": [{"address": "127.0.0.1", "port": $port}] }
  }')
  TOP_TYPE=$(jq -r 'type' "$OUTBOUND_FILE")
  if [ "$TOP_TYPE" = "array" ]; then
    jq ". += [$SERVER_OBJ]" "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
  else
    jq ".outbounds |= (. // []) + [$SERVER_OBJ]" "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
  fi
  echo "✅ 已成功添加 socks5-warp 出口。"
fi

# ===============================
# 2️⃣ 路由规则配置 (强力 ID 查重)
# ===============================
echo ""
echo "================ 2. 路由规则绑定 ================"
echo "请选择协议类型："
echo "1) Shadowsocks"
echo "2) Trojan"
echo "3) Vless"
read -p "请输入选项 [1-3]: " TYPE_CHOICE

case "$TYPE_CHOICE" in
  1) PROTO="shadowsocks" ;;
  2) PROTO="trojan" ;;
  3) PROTO="vless" ;;
  *) echo "❌ 无效输入"; exit 1 ;;
esac

read -p "请输入入站 ID: " PORT
INBOUND_TAG="${API_PREFIX}-${PROTO}:${PORT}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ 配置文件 $CONFIG_FILE 不存在"; exit 1
fi

# 【核心查重逻辑】只匹配ID，不看API地址或协议
if jq -e --arg id ":$PORT" '.rules[]? | .inboundTag[]? | select(contains($id))' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️  查重失败：ID [$PORT] 已经在路由规则中存在，请勿重复添加。"
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
  echo "✅ 已成功插入规则: $INBOUND_TAG -> socks5-warp"
fi

# ===============================
# 3️⃣ 服务管理
# ===============================
echo ""
read -p "是否立即重启 V2bX 服务使配置生效? (y/n): " RESTART_CHOICE
if [[ "$RESTART_CHOICE" =~ ^[yY]$ ]]; then
  systemctl restart V2bX && echo "✅ V2bX 重启成功" || echo "❌ 重启失败"
fi

# ===============================
# 4️⃣ WARP 自动保活配置
# ===============================
echo ""
echo "================ 3. WARP 自动保活配置 ================"
read -p "是否需要安装 WARP 自动保活脚本? (y/n): " ADD_MONITOR

if [[ "$ADD_MONITOR" =~ ^[yY]$ ]]; then
  read -p "请输入保活脚本检测的端口 (回车默认使用 $V2BX_PORT): " M_PORT
  MONITOR_PORT=${M_PORT:-$V2BX_PORT}

  echo "请选择检测失败时调用的重启命令："
  echo "  1) warp y (WARP WireProxy 模式)"
  echo "  2) warp r (WARP ClientProxy模式)"
  read -p "请输入 [1-2]: " M_CHOICE

  case "$M_CHOICE" in
    1) TARGET_CMD="warp y" ;;
    2) TARGET_CMD="warp r" ;;
    *) echo "❌ 选择无效，跳过保活配置"; TARGET_CMD="" ;;
  esac

  if [ -n "$TARGET_CMD" ]; then
    cat > "$MONITOR_SCRIPT_PATH" <<EOF
#!/bin/bash
# WARP 保活脚本 (由脚本自动生成)
CHECK_URL="https://www.cloudflare.com/cdn-cgi/trace"
PROXY="127.0.0.1:$MONITOR_PORT"
if ! curl --socks5 "\$PROXY" -s --max-time 10 "\$CHECK_URL" | grep -Eq "warp=(on|plus)|warp-r"; then
    echo "[\$(date)] ⚠️ WARP 掉线，执行重启: $TARGET_CMD"
    $TARGET_CMD
    sleep 10
fi
EOF
    chmod +x "$MONITOR_SCRIPT_PATH"

    # Crontab 任务查重
    if ! crontab -l 2>/dev/null | grep -Fq "$MONITOR_SCRIPT_PATH"; then
      (crontab -l 2>/dev/null || true; echo "*/5 * * * * /bin/bash $MONITOR_SCRIPT_PATH >> /var/log/warp_monitor.log 2>&1") | crontab -
      echo "✅ 已添加 Crontab 任务 (每5分钟执行一次)。"
    else
      echo "⚠️ Crontab 任务已存在，未重复添加。"
    fi
  fi
fi

echo ""
echo "🎉 所有操作已完成！"
