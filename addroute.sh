#!/bin/bash
# 一键添加 socks5-warp 路由规则到 /etc/V2bX/route.json
# 支持 Shadowsocks / Trojan / VLESS
# 若不存在 IPv4_out 则自动追加新 rule

CONFIG_FILE="/etc/V2bX/route.json"
TMP_FILE="/etc/V2bX/route.tmp"
API_PREFIX="[https://node-api114514.6868319.xyz]"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到配置文件: $CONFIG_FILE"
  exit 1
fi

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

# 检查是否已存在该 inboundTag
if jq -e --arg tag "$INBOUND_TAG" '
  .rules[]? | select(.inboundTag[]? == $tag)
' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️ 已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
  exit 0
fi

# 插入规则
jq --arg tag "$INBOUND_TAG" '
  .rules |= (. // []) |

  # 是否存在 IPv4_out
  (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |

  if $hasOut then
    # 在 IPv4_out 后插入
    .rules |= map(
      if .outboundTag == "IPv4_out" then
        {"type":"field",
         "outboundTag":"socks5-warp",
         "inboundTag":[$tag],
         "network":"udp,tcp"},
        .
      else
        .
      end
    )
  else
    # 不存在 IPv4_out，直接追加
    .rules += [
      {"type":"field",
       "outboundTag":"socks5-warp",
       "inboundTag":[$tag],
       "network":"udp,tcp"}
    ]
  end
' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

if [ $? -eq 0 ]; then
  echo "✅ 已成功插入 socks5-warp 规则："
  echo "   inboundTag = $INBOUND_TAG"
else
  echo "❌ 插入失败，请检查 jq 是否安装或 JSON 是否正确。"
fi

echo "✅ 命令执行完成。"
