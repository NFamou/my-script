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
    iproute \
    net-tools \
    nftables
fi

# =============================
# 防火墙规则配置
# =============================

if [ "$OS_FAMILY" = "debian" ]; then
  echo "[+] 正在配置 Debian/Ubuntu 防火墙 (ip6tables)..."
  
  # 清空旧规则
  ip6tables -F
  ip6tables -X

  # 设置默认策略
  ip6tables -P INPUT DROP
  ip6tables -P FORWARD DROP
  ip6tables -P OUTPUT ACCEPT

  # 已建立连接
  ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # ⚠️ SSH 放行（原脚本默认注释）
  # ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

  # ICMPv6 必要规则
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

  # 限制探测
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP
  ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP

  # 持久化规则
  echo "[+] 保存规则并设置开机自启..."
  mkdir -p /etc/iptables
  ip6tables-save > /etc/iptables/rules.v6


elif [ "$OS_FAMILY" = "rhel" ]; then
  echo "[+] 正在配置 AlmaLinux/RHEL 防火墙 (nftables)..."
  
  # 启用并启动 nftables 服务
  systemctl enable nftables
  systemctl start nftables

  # 清空现有的独立 IPv6 过滤表（不影响 IPv4 流量）
  nft delete table ip6 filter 2>/dev/null || true
  nft add table ip6 filter

  # 设置默认策略 (INPUT/FORWARD 拒绝，OUTPUT 允许)
  nft 'add chain ip6 filter input { type filter hook input priority filter ; policy drop ; }'
  nft 'add chain ip6 filter forward { type filter hook forward priority filter ; policy drop ; }'
  nft 'add chain ip6 filter output { type filter hook output priority filter ; policy accept ; }'

  # 允许已建立的连接
  nft add rule ip6 filter input ct state { established, related } accept

  # ⚠️ SSH 放行（如需开启，请取消下行的注释）
  # nft add rule ip6 filter input tcp dport 22 accept

  # ICMPv6 必要规则 (适配 AlmaLinux 10 新版 nftables 语法)
  nft add rule ip6 filter input icmpv6 type nd-neighbor-solicit accept
  nft add rule ip6 filter input icmpv6 type nd-neighbor-advert accept
  nft add rule ip6 filter input icmpv6 type packet-too-big accept

  # 限制探测 (阻止 ping6、traceroute6 等)
  nft add rule ip6 filter input icmpv6 type echo-request drop
  nft add rule ip6 filter output icmpv6 type time-exceeded drop
  nft add rule ip6 filter output icmpv6 type destination-unreachable drop

  # 持久化规则
  echo "[+] 保存规则并重启 nftables..."
  nft list ruleset > /etc/nftables/main.nft
  systemctl restart nftables
fi

echo "[✓] 完成。防火墙规则已成功适配当前系统架构并生效。"
