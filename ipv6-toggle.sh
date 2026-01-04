#!/bin/bash

set -e

[ "$EUID" -ne 0 ] && { echo "❌ 请使用 root 运行"; exit 1; }

CONF_FILE="/etc/sysctl.d/99-disable-ipv6.conf"

get_interfaces() {
  ip -o link show | awk -F': ' '{print $2}' \
    | grep -Ev '^(lo|sit|he-|ip6tnl)'
}

get_ipv4() {
  ip -o -4 addr show "$1" 2>/dev/null | awk '{print $4}' | paste -sd ","
}

get_ipv6() {
  ip -o -6 addr show "$1" scope global 2>/dev/null | awk '{print $4}' | paste -sd ","
}

apply_sysctl() {
  sysctl --system >/dev/null
}

echo "=============================="
echo " IPv6 网口管理脚本"
echo "=============================="
echo "1) 永久关闭指定网口 IPv6"
echo "2) 恢复指定网口 IPv6"
echo "3) 查看当前 IPv6 状态"
echo "0) 退出"
echo
read -rp "请选择操作 [0-3]: " ACTION

case "$ACTION" in
1)
  echo
  echo "可用网口（含 IP 信息）："
  mapfile -t IFACES < <(get_interfaces)

  for i in "${!IFACES[@]}"; do
    IF="${IFACES[$i]}"
    IPV4=$(get_ipv4 "$IF")
    IPV6=$(get_ipv6 "$IF")

    echo "$((i+1))) $IF"
    echo "   IPv4: ${IPV4:-无}"
    echo "   IPv6: ${IPV6:-无}"
  done

  echo
  read -rp "选择要关闭 IPv6 的网口编号: " IDX
  IFACE="${IFACES[$((IDX-1))]}"

  [ -z "$IFACE" ] && { echo "❌ 无效选择"; exit 1; }

  echo "[+] 永久关闭 $IFACE 的 IPv6"

  sed -i "/net.ipv6.conf.$IFACE/d" "$CONF_FILE" 2>/dev/null || true
  echo "net.ipv6.conf.$IFACE.disable_ipv6 = 1" >> "$CONF_FILE"

  apply_sysctl
  echo "✅ $IFACE IPv6 已永久关闭"
  ;;

2)
  echo
  echo "检测当前 IPv6 已关闭的网口："

  mapfile -t IFACES < <(
    for d in /proc/sys/net/ipv6/conf/*; do
      IF=$(basename "$d")
      [[ "$IF" =~ ^(lo|sit|he-|ip6tnl) ]] && continue
      [ "$(cat "$d/disable_ipv6")" = "1" ] && echo "$IF"
    done
  )

  if [ "${#IFACES[@]}" -eq 0 ]; then
    echo "⚠️ 当前没有检测到被关闭 IPv6 的真实网口"
    exit 0
  fi

  select IFACE in "${IFACES[@]}"; do
    [ -n "$IFACE" ] && break
  done

  echo "[+] 恢复 $IFACE 的 IPv6"

  # 删除所有 sysctl 中对该网口的 disable 规则
  sed -i "/net.ipv6.conf.$IFACE.disable_ipv6/d" /etc/sysctl.conf 2>/dev/null || true
  sed -i "/net.ipv6.conf.$IFACE.disable_ipv6/d" /etc/sysctl.d/*.conf 2>/dev/null || true

  # 立刻恢复
  sysctl -w net.ipv6.conf.$IFACE.disable_ipv6=0 >/dev/null

  echo "✅ $IFACE IPv6 已恢复（建议重启网络或系统）"
  ;;

3)
  echo
  echo "当前 IPv6 状态："
  for IFACE in $(get_interfaces); do
    STATUS=$(cat /proc/sys/net/ipv6/conf/$IFACE/disable_ipv6 2>/dev/null || echo "?")
    IPV6=$(get_ipv6 "$IFACE")

    if [ "$STATUS" = "1" ]; then
      echo "❌ $IFACE : IPv6 已关闭"
    else
      echo "✅ $IFACE : IPv6 启用 (${IPV6:-无 IPv6 地址})"
    fi
  done
  ;;

0)
  exit 0
  ;;

*)
  echo "❌ 无效选项"
  exit 1
  ;;
esac
