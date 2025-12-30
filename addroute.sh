#!/bin/bash
# 一键添加 socks5-warp 路由规则到 /etc/V2bX/route.json
# 支持 Shadowsocks / Trojan / VLESS
# 自动检测 /etc/V2bX/custom_outbound.json 是否存在 socks5-warp 出口

set -e

CONFIG_FILE="/etc/V2bX/route.json"
OUTBOUND_FILE="/etc/V2bX/custom_outbound.json"
TMP_FILE="/tmp/v2bx.tmp"
API_PREFIX="[https://node-api114514.6868319.xyz]"

# ===============================
# 1️⃣ 检查 route.json
# ===============================
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到配置文件: $CONFIG_FILE"
  exit 1
fi

# ===============================
# 2️⃣ 检查 / 创建 socks5-warp outbound
# ===============================
echo "🔍 检查 socks5-warp outbound..."

# 若文件不存在，创建基础结构
if [ ! -f "$OUTBOUND_FILE" ]; then
  echo "⚠️ 未找到 $OUTBOUND_FILE，正在创建..."
  echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
fi

# 检测是否已存在 socks5-warp
if jq -e '.outbounds[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
  echo "✅ socks5-warp outbound 已存在，保持不变。"
else
  echo "➕ 添加 socks5-warp outbound..."
  jq '
    .outbounds |= (. // []) + [
      {
        "tag": "socks5-warp",
        "protocol": "socks",
        "settings": {
          "servers": [
            {
              "address": "127.0.0.1",
              "port": 40000
            }
          ]
        }
      }
    ]
  ' "$OUTBOUND_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$OUTBOUND_FILE"
  echo "✅ socks5-warp outbound 已添加。"
fi

# ===============================
# 3️⃣ 选择入站类型
# ===============================
echo
echo "请选择入站类型："
echo "1) Shadowsocks"
echo "2) Trojan"
echo "3) VLESS"
read -p "请输入编号 (1/2/3): " TYPE_CHOICE

case "$TYPE_CHOICE" in
  1)
    read -p "请输入 Shadowsocks ID: " PORT
    INBOUND_TAG="${API_PREFIX}-shadowsocks:${PORT}"
    ;;
  2)
    read -p "请输入 Trojan ID: " PORT
    INBOUND_TAG="${API_PREFIX}-trojan:${PORT}"
    ;;
  3)
    read -p "请输入 VLESS ID: " PORT
    INBOUND_TAG="${API_PREFIX}-vless:${PORT}"
    ;;
  *)
    echo "❌ 输入无效，请输入 1 / 2 / 3"
    exit 1
    ;;
esac

# ===============================
# 4️⃣ 检查 route 规则是否已存在
# ===============================
if jq -e --arg tag "$INBOUND_TAG" '
  .rules[]? | select(.inboundTag[]? == $tag)
' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️ 已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
  exit 0
fi

# ===============================
# 5️⃣ 插入路由规则
# ===============================
jq --arg tag "$INBOUND_TAG" '
  .rules |= (. // []) |
  (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |

  if $hasOut then
    .rules |= map(
      if .outboundTag == "IPv4_out" then
        {
          "type": "field",
          "outboundTag": "socks5-warp",
          "inboundTag": [$tag],
          "network": "udp,tcp"
        },
        .
      else
        .
      end
    )
  else
    .rules += [
      {
        "type": "field",
        "outboundTag": "socks5-warp",
        "inboundTag": [$tag],
        "network": "udp,tcp"
      }
    ]
  end
' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

echo "✅ 已成功插入 socks5-warp 路由规则"
echo "   inboundTag = $INBOUND_TAG"
echo "🎉 全部操作完成"
