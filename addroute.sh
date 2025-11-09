#!/bin/bash
# 一键添加 socks5-warp 路由规则到 /etc/V2bX/route.json

CONFIG_FILE="/etc/V2bX/route.json"
TMP_FILE="/etc/V2bX/route.tmp"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ 未找到配置文件: $CONFIG_FILE"
  exit 1
fi

read -p "请输入 shadowsocks 编号: " SS_PORT
INBOUND_TAG="[https://node-api114514.6868319.xyz]-shadowsocks:${SS_PORT}"

# 检查是否已存在相同 inboundTag，防止重复添加
if jq -e --arg tag "$INBOUND_TAG" '.rules[]? | select(.inboundTag[]? == $tag)' "$CONFIG_FILE" >/dev/null 2>&1; then
  echo "⚠️  已存在 inboundTag: $INBOUND_TAG，无需重复添加。"
  exit 0
fi

jq --arg ssid "$INBOUND_TAG" '
  .rules |= (. // []) |
  .rules |= map(
    if .outboundTag == "IPv4_out" then
      {"type": "field",
       "outboundTag": "socks5-warp",
       "inboundTag": [$ssid],
       "network": "udp,tcp"},
      .
    else
      .
    end
  )
' "$CONFIG_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

if [ $? -eq 0 ]; then
  echo "✅ 已成功插入 socks5-warp 规则："
  echo "   inboundTag = $INBOUND_TAG"
else
  echo "❌ 插入失败，请检查 jq 是否安装或 JSON 格式是否正确。"
fi

echo "✅ 命令已安装完成。现在可直接执行： addroute"
