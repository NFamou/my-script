#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

echo "[+] 检测系统类型..."
OS_FAMILY=""
if [ -f /etc/debian_version ]; then OS_FAMILY="debian"
elif [ -f /etc/redhat-release ]; then OS_FAMILY="rhel"
else echo "❌ 不支持的系统"; exit 1; fi

# =============================
# 🎯 精准自动获取 HE Tunnel 网卡
# =============================
DEFAULT_IFACE=$(ip -6 route show | grep -m1 'via ::' | grep 'dev ' | awk '{print $5}')
DEFAULT_IFACE=${DEFAULT_IFACE:-"he-ipv6"}

read -p "[?] 请输入你的 HE 隧道网卡名称 (默认: $DEFAULT_IFACE): " IFACE
IFACE=${IFACE:-$DEFAULT_IFACE}

if ! ip link show "$IFACE" > /dev/null 2>&1; then
  echo "❌ 网卡 $IFACE 不存在，请检查！"
  exit 1
fi

echo "[+] 开始为 HE 隧道 ($IFACE) 部署无损绝对黑洞策略..."

# =============================
# 安装/检查必要工具
# =============================
if [ "$OS_FAMILY" = "debian" ]; then
  apt update -y && apt install -y iptables iproute2 iptables-persistent
elif [ "$OS_FAMILY" = "rhel" ]; then
  dnf install -y iptables iptables-services iproute
fi

# =============================
# 全局安全兜底（确保不影响其他网卡通畅）
# =============================
# 保持全局默认策略为允许，全靠局部规则隔离
ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT

# 确保本地环回接口放行（无则添加，有则略过，不重复堆叠）
ip6tables -C INPUT -i lo -j ACCEPT 2>/dev/null || ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -C OUTPUT -o lo -j ACCEPT 2>/dev/null || ip6tables -A OUTPUT -o lo -j ACCEPT

# =============================
# 🧼 清理可能存在的旧 HE 隧道黑洞规则
# =============================
# 这一步很关键：先拔除该网卡之前可能运行过的旧规则，防止每次运行脚本都重复堆叠规则
echo "[+] 正在检查并清理 $IFACE 的旧规则补丁..."
ip6tables -D INPUT -i $IFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
ip6tables -D INPUT -i $IFACE -j DROP 2>/dev/null || true

# =============================
# 🚀 精准注入专属黑洞规则（不波及其他网卡）
# =============================
echo "[+] 正在注入 $IFACE 单向出口黑洞规则..."

# 1. 唯一通行证：只允许你主动发起的出站流量、以及与之关联的底层报错（依赖RELATED状态，保网速、防断网）
ip6tables -A INPUT -i $IFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. 绝对黑洞收口：除上面主动请求的回包外，其余任何进入 HE 隧道的盲目探测流量，直接在此网卡处丢弃！
ip6tables -A INPUT -i $IFACE -j DROP

# =============================
# 持久化规则
# =============================
echo "[+] 正在保存当前系统所有 IPv6 规则..."
if [ "$OS_FAMILY" = "debian" ]; then
  mkdir -p /etc/iptables && ip6tables-save > /etc/iptables/rules.v6
elif [ "$OS_FAMILY" = "rhel" ]; then
  ip6tables-save > /etc/sysconfig/ip6tables
fi

echo "[✓] 完美搞定！黑洞规则已精准覆盖 $IFACE 。"
echo "[i] 其他网卡（如管理网卡）原有的 IPv6 规则与网络连通性完好无损。"
