#!/bin/bash
# 一键添加 socks5-warp 路由规则到 /etc/V2bX/route.json
# 支持 Shadowsocks 与 Trojan，若不存在 IPv4_out 则自动追加新 rule

CONFIG_FILE="/etc/V2bX/route.json"
TMP_FILE="/etc/V2bX/route.tmp"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到配置文件: $CONFIG_FILE"
  exit 1
fi

echo "请选择入站类型："
echo "1) Shadowsocks"
echo "2) Trojan"
read -p "请输入编号 (1/2): " TYPE_CHOICE

if [[ "$TYPE_CHOICE" == "1" ]]; then
  read -p "请输入 Shadowsocks 编号: " SS_PORT
  INBOUND_TAG="[https://node-api114514.6868319.xyz]-shadowsocks:${SS_PORT}"
elif [[ "$TYPE_CHOICE" == "2" ]]; then
  read -p "请输入 Trojan 编号: " TJ_PORT
  INBOUND_TAG="[https://node-api114514.6868319.xyz]-trojan:${TJ_PORT}"
else
  echo "❌ 输入无效，请输入 1 或 2"
  exit 1
fi

# 检查重复
if jq -e --arg tag "$INBOUND_TAG" '.rules[]? | select(.inboundTag[]? == $tag)' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️ 已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
  exit 0
fi

# 插入规则：有 IPv4_out → 修改 | 无 IPv4_out → append 新规则
jq --arg tag "$INBOUND_TAG" '
  .rules |= (. // []) |

  # 检查是否存在 IPv4_out
  (any(.rules[]?; .outboundTag == "IPv4_out")) as $hasOut |

  if $hasOut then
    # 在 IPv4_out 那条后插入新规则
    .rules |= map(
      if .outboundTag == "IPv4_out" then
        {"type": "field",
         "outboundTag": "socks5-warp",
         "inboundTag": [$tag],
         "network": "udp,tcp"},
        .
      else
        .
      end
    )
  else
    # 不存在 IPv4_out → 添加独立新规则
    .rules += [
      {"type": "field",
       "outboundTag": "socks5-warp",
       "inboundTag": [$tag],
       "network": "udp,tcp"}
    ]
  end
' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

if [ $? -eq 0 ]; then
  echo "✅ 已成功插入 socks5-warp 规则："
  echo "   inboundTag = $INBOUND_TAG"
else
  echo "❌ 插入失败，请检查 jq 是否安装或 JSON 格式是否正确。"
fi

echo "✅ 命令已安装完成。现在可直接执行： addroute"
