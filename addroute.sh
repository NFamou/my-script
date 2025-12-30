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
# 0️⃣ 检测是否 root
# ===============================
if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行该脚本"
  exit 1
fi

# ===============================
# 1️⃣ 检测并安装 jq
# ===============================
if ! command -v jq >/dev/null 2>&1; then
  echo "⚠️ 未检测到 jq，正在尝试安装..."
  if [ -f /etc/debian_version ]; then
    apt update
    apt install -y jq
  elif [ -f /etc/redhat-release ]; then
    if command -v dnf >/dev/null 2>&1; then
      dnf install -y jq
    else
      yum install -y jq
    fi
  else
    echo "❌ 无法识别的 Linux 发行版，请手动安装 jq"
    exit 1
  fi
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "❌ jq 安装失败，请手动处理"
  exit 1
fi
echo "✅ jq 已就绪"

# ===============================
# 2️⃣ 检查 route.json
# ===============================
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到配置文件: $CONFIG_FILE"
  exit 1
fi

# ===============================
# 3️⃣ 检查 / 创建 socks5-warp outbound
# ===============================
echo "🔍 检查 socks5-warp outbound..."
if [ ! -f "$OUTBOUND_FILE" ]; then
  echo "⚠️ 未找到 $OUTBOUND_FILE，正在创建..."
  echo '{"outbounds":[]}' > "$OUTBOUND_FILE"
fi

# 检测是否已存在 socks5-warp
if jq -e '.[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1 \
   || jq -e '.outbounds[]? | select(.tag=="socks5-warp")' "$OUTBOUND_FILE" >/dev/null 2>&1; then
  echo "✅ socks5-warp outbound 已存在，保持不变。"
else
  TOP_TYPE=$(jq -r 'type' "$OUTBOUND_FILE")
  if [ "$TOP_TYPE" = "array" ]; then
    # 顶层是数组
    jq '
      . += [
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
    echo "✅ socks5-warp outbound 已添加（数组模式）。"
  elif [ "$TOP_TYPE" = "object" ]; then
    # 顶层是对象
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
    echo "✅ socks5-warp outbound 已添加（对象模式）。"
  else
    echo "❌ 无法识别的 JSON 结构，请检查 $OUTBOUND_FILE"
    exit 1
  fi
fi

# ===============================
# 4️⃣ 选择入站类型
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
# 5️⃣ 检查 route 规则是否已存在
# ===============================
if jq -e --arg tag "$INBOUND_TAG" '.rules[]? | select(.inboundTag[]? == $tag)' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️ 已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
  exit 0
fi

# ===============================
# 6️⃣ 插入路由规则
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

# ===============================
# 7️⃣ 提示是否重启 V2bX
# ===============================
read -p "是否需要立即重启 V2bX 服务以生效路由规则? (y/n): " RESTART_CHOICE
case "$RESTART_CHOICE" in
  y|Y)
    if command -v systemctl >/dev/null 2>&1; then
      echo "🔄 正在重启 V2bX 服务..."
      systemctl restart V2bX
      if [ $? -eq 0 ]; then
        echo "✅ V2bX 服务已成功重启"
      else
        echo "❌ V2bX 重启失败，请手动检查"
      fi
    else
      echo "❌ systemctl 未找到，请手动重启 V2bX"
    fi
    ;;
  n|N)
    echo "⚠️ 路由已更新，但 V2bX 未重启，需要手动重启后生效"
    ;;
  *)
    echo "⚠️ 输入无效，跳过重启操作"
    ;;
esac

echo "🎉 全部操作完成"
