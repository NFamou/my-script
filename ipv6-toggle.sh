#!/bin/bash

set -e

[ "$EUID" -ne 0 ] && { echo "❌ 请使用 root 运行"; exit 1; }

CONF_SYSCTL="/etc/sysctl.conf"
CONF_DIR="/etc/sysctl.d"

# ---------------- 基础函数 ----------------

is_real_iface() {
  [[ ! "$1" =~ ^(lo|sit|he-|ip6tnl) ]]
}

get_real_ifaces() {
  for d in /proc/sys/net/ipv6/conf/*; do
    IF=$(basename "$d")
    is_real_iface "$IF" && echo "$IF"
  done
}

get_ipv4() {
  ip -o -4 addr show "$1" 2>/dev/null | awk '{print $4}' | paste -sd ","
}

get_ipv6() {
  ip -o -6 addr show "$1" scope global 2>/dev/null | awk '{print $4}' | paste -sd ","
}

sysctl_val() {
  cat "/proc/sys/net/ipv6/conf/$1/disable_ipv6" 2>/dev/null || echo "?"
}

apply_sysctl() {
  sysctl --system >/dev/null
}

default_iface() {
  ip route | awk '/default/ {print $5; exit}'
}

remove_all_disable_rules() {
  sed -i '/net.ipv6.conf.*.disable_ipv6/d' "$CONF_SYSCTL" 2>/dev/null || true
  sed -i '/net.ipv6.conf.*.disable_ipv6/d' "$CONF_DIR"/*.conf 2>/dev/null || true
}

# ---------------- 菜单 ----------------

echo "=============================="
echo " IPv6 网口管理 · 终极安全版"
echo "=============================="
echo "1) 查看 IPv6 状态（含关闭来源）"
echo "2) 永久关闭 IPv6（all / default / 指定网口）"
echo "3) 精确恢复 IPv6（按来源恢复）"
echo "0) 退出"
echo
read -rp "请选择操作 [0-3]: " ACTION

# ---------------- 1 查看状态 ----------------

if [ "$ACTION" = "1" ]; then
  echo
  ALL=$(sysctl_val all)
  DEF=$(sysctl_val default)

  echo "全局状态："
  echo "  all.disable_ipv6     = $ALL"
  echo "  default.disable_ipv6 = $DEF"
  echo

  MAIN_IF=$(default_iface)

  for IF in $(get_real_ifaces); do
    VAL=$(sysctl_val "$IF")
    IPV4=$(get_ipv4 "$IF")
    IPV6=$(get_ipv6 "$IF")

    SOURCE="iface"
    [ "$ALL" = "1" ] && SOURCE="all"
    [ "$ALL" = "0" ] && [ "$DEF" = "1" ] && SOURCE="default"

    echo "[$IF]"
    echo "  IPv4   : ${IPV4:-无}"
    echo "  IPv6   : ${IPV6:-无}"
    echo "  状态   : $([ "$VAL" = "1" ] && echo '❌ 已关闭' || echo '✅ 启用')"
    echo "  来源   : $SOURCE"
    [ "$IF" = "$MAIN_IF" ] && echo "  ⚠️ 主路由网口"
    echo
  done
  exit 0
fi

# ---------------- 2 关闭 IPv6 ----------------

if [ "$ACTION" = "2" ]; then
  echo
  echo "请选择关闭级别："
  echo "1) all（所有网口，最危险）"
  echo "2) default（新网口默认关闭）"
  echo "3) 指定网口（推荐）"
  echo
  read -rp "选择 [1-3]: " LEVEL

  MAIN_IF=$(default_iface)

  case "$LEVEL" in
    1)
      echo "⚠️ 警告：这会关闭所有 IPv6"
      read -rp "确认输入 YES: " C
      [ "$C" != "YES" ] && exit 1
      remove_all_disable_rules
      echo "net.ipv6.conf.all.disable_ipv6 = 1" >> "$CONF_DIR/99-ipv6.conf"
      ;;
    2)
      remove_all_disable_rules
      echo "net.ipv6.conf.default.disable_ipv6 = 1" >> "$CONF_DIR/99-ipv6.conf"
      ;;
    3)
      echo
      mapfile -t IFACES < <(get_real_ifaces)
      for i in "${!IFACES[@]}"; do
        IF="${IFACES[$i]}"
        echo "$((i+1))) $IF  IPv4:${get_ipv4 "$IF"}  IPv6:${get_ipv6 "$IF"}"
      done
      echo
      read -rp "选择网口编号: " IDX
      IFACE="${IFACES[$((IDX-1))]}"

      [ -z "$IFACE" ] && exit 1

      if [ "$IFACE" = "$MAIN_IF" ]; then
        echo "❌ 拒绝：这是主路由网口，禁止操作"
        exit 1
      fi

      sed -i "/net.ipv6.conf.$IFACE.disable_ipv6/d" "$CONF_DIR"/*.conf 2>/dev/null || true
      echo "net.ipv6.conf.$IFACE.disable_ipv6 = 1" >> "$CONF_DIR/99-ipv6.conf"
      ;;
    *)
      exit 1
      ;;
  esac

  apply_sysctl
  echo "✅ IPv6 关闭完成"
  exit 0
fi

# ---------------- 3 恢复 IPv6 ----------------

if [ "$ACTION" = "3" ]; then
  echo
  echo "检测 IPv6 关闭来源..."

  ALL=$(sysctl_val all)
  DEF=$(sysctl_val default)

  if [ "$ALL" = "1" ]; then
    echo "发现：all.disable_ipv6 = 1"
    read -rp "是否恢复？[y/N]: " C
    [ "$C" = "y" ] || exit 0
    remove_all_disable_rules
    sysctl -w net.ipv6.conf.all.disable_ipv6=0
  fi

  if [ "$DEF" = "1" ]; then
    echo "发现：default.disable_ipv6 = 1"
    read -rp "是否恢复？[y/N]: " C
    [ "$C" = "y" ] || exit 0
    remove_all_disable_rules
    sysctl -w net.ipv6.conf.default.disable_ipv6=0
  fi

  echo
  echo "检测独立关闭的网口："

  mapfile -t IFACES < <(
    for IF in $(get_real_ifaces); do
      [ "$(sysctl_val "$IF")" = "1" ] && echo "$IF"
    done
  )

  if [ "${#IFACES[@]}" -eq 0 ]; then
    echo "⚠️ 没有独立关闭的网口"
    exit 0
  fi

  select IFACE in "${IFACES[@]}"; do
    [ -n "$IFACE" ] && break
  done

  sed -i "/net.ipv6.conf.$IFACE.disable_ipv6/d" "$CONF_SYSCTL" 2>/dev/null
  sed -i "/net.ipv6.conf.$IFACE.disable_ipv6/d" "$CONF_DIR"/*.conf 2>/dev/null

  sysctl -w net.ipv6.conf.$IFACE.disable_ipv6=0 >/dev/null
  echo "✅ $IFACE IPv6 已恢复"
  exit 0
fi
