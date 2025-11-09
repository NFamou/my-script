#!/bin/bash
CONFIG_FILE="/etc/V2bX/route.json"
TMP_FILE="/tmp/route.tmp"

# 自动安装 jq
if ! command -v jq >/dev/null 2>&1; then
    echo "⚠️ jq 未安装，正在安装..."
    if command -v apt-get >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y jq
    else
        echo "❌ 请手动安装 jq"
        exit 1
    fi
fi

[ ! -f "$CONFIG_FILE" ] && echo "❌ $CONFIG_FILE 不存在" && exit 1

read -p "请输入 shadowsocks 编号: " P
T="[https://node-api114514.6868319.xyz]-shadowsocks:$P"

# 防重复
jq -e --arg t "$T" '.[1][]? | select(.inboundTag[]? == $t)' "$CONFIG_FILE" >/dev/null 2>&1 \
  && echo "⚠️ 已存在 $T" && exit 0

# 找 IPv4_out 索引
IDX=$(jq '[.[1][]?.outboundTag=="IPv4_out"] | index(true)' "$CONFIG_FILE")

# 插入新规则在 IPv4_out 前
jq --arg s "$T" --argjson idx "$IDX" '
  .[1] |= (.[0:$idx] + [{"type":"field","outboundTag":"socks5-warp","inboundTag":[$s],"network":"udp,tcp"}] + .[$idx:])
' "$CONFIG_FILE" | jq '.' > "$TMP_FILE" && mv "$TMP_FILE" "$CONFIG_FILE"

echo "✅ 已插入 $T"
