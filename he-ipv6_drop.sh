#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

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

echo "[+] 正在为 HE 隧道 ($IFACE) 部署至简绝对黑洞策略..."

# =============================
# 清空全局旧规则
# =============================
ip6tables -F
ip6tables -X

ip6tables -P INPUT ACCEPT
ip6tables -P FORWARD ACCEPT
ip6tables -P OUTPUT ACCEPT

# 无条件放行本地环回（系统内部通信基础）
ip6tables -A INPUT -i lo -j ACCEPT
ip6tables -A OUTPUT -o lo -j ACCEPT

# =============================
# 核心规则链（单向黑洞模型）
# =============================

# 1. 🔥 唯一通行证：只允许你主动发起的出站流量、以及与之相关的底层报错（如 PMTU 的 packet-too-big）
# 只要是 RELATED 和 ESTABLISHED，HE 隧道绝不可能断网，网络性能也是最优的。
ip6tables -A INPUT -i $IFACE -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 2. 🛑 绝对黑洞：除上面主动请求的回包外，其余任何进入该网卡的流量，无条件直接丢弃！
# 无论别人是用 ping6、traceroute6、还是 nmap 怎么轰炸这个 IP，全部直接人间蒸发，没有任何回应。
ip6tables -A INPUT -i $IFACE -j DROP

# =============================
# 持久化规则
# =============================
echo "[+] 正在持久化写入系统防火墙..."
if [ -f /etc/debian_version ]; then
  mkdir -p /etc/iptables && ip6tables-save > /etc/iptables/rules.v6
elif [ -f /etc/redhat-release ]; then
  ip6tables-save > /etc/sysconfig/ip6tables
fi

echo "[✓] 完美的 HE Tunnel 单向出口黑洞已铸成！该 IPv6 地址对公网的一切主动探测已彻底装聋作哑。"
