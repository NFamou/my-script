#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "❌ 请使用 root 用户运行"
  exit 1
fi

echo "[+] 检测系统类型..."

OS_FAMILY=""
if [ -f /etc/debian_version ]; then
  OS_FAMILY="debian"
elif [ -f /etc/redhat-release ]; then
  OS_FAMILY="rhel"
else
  echo "❌ 不支持的系统"
  exit 1
fi

echo "[+] 系统类型：$OS_FAMILY"

# =============================
# 安装依赖
# =============================
echo "[+] 安装必要工具..."

if [ "$OS_FAMILY" = "debian" ]; then
  apt update
  apt install -y \
    curl \
    wget \
    sudo \
    iptables \
    iproute2 \
    net-tools \
    iptables-persistent

elif [ "$OS_FAMILY" = "rhel" ]; then
  dnf install -y \
    curl \
    wget \
    sudo \
    iptables \
    iptables-services \
    iproute \
    net-tools
fi

# =============================
# 启用 ip6tables 服务（RHEL）
# =============================
if [ "$OS_FAMILY" = "rhel" ]; then
  systemctl enable ip6tables
  systemctl start ip6tables
fi

# =============================
# 清空旧规则
# =============================
echo "[+] 清空现有 ip6tables 规则..."
ip6tables -F
ip6tables -X

# =============================
# 设置默认策略
# =============================
echo "[+] 设置默认策略..."
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# =============================
# 已建立连接
# =============================
echo "[+] 允许已建立连接..."
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ⚠️ SSH 放行（建议开启）
# ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

# =============================
# ICMPv6 必要规则
# =============================
echo "[+] 允许必要 ICMPv6..."
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

# =============================
# 限制探测
# =============================
echo "[+] 阻止 ping6..."
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

echo "[+] 阻止 traceroute6..."
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP

echo "[+] 阻止端口不可达提示..."
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP

# =============================
# 持久化规则
# =============================
echo "[+] 保存规则并设置开机自启..."

if [ "$OS_FAMILY" = "debian" ]; then
  mkdir -p /etc/iptables
  ip6tables-save > /etc/iptables/rules.v6

elif [ "$OS_FAMILY" = "rhel" ]; then
  ip6tables-save > /etc/sysconfig/ip6tables
  systemctl restart ip6tables
fi

echo "[✓] 完成。Debian / Ubuntu / AlmaLinux 通用 IPv6 防火墙规则已生效。"
