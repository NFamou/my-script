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
  
  ip6tables -F
  ip6tables -X

  ip6tables -P INPUT DROP
  ip6tables -P FORWARD DROP
  ip6tables -P OUTPUT ACCEPT

  # 1. 允许已建立的连接（保证 curl 等出站请求能收到回包）
  ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

  # ⚠️ SSH 放行（如需开启请取消注释）
  # ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

  # 2. 允许 IPv6 底层生存所必需的 ICMPv6 报文
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

  # 3. 拦截外部 Ping 探测
  ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP
  
  # 拦截 Traceroute 等探测回应
  ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP
  ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP

  echo "[+] 保存规则并设置开机自启..."
  mkdir -p /etc/iptables
  ip6tables-save > /etc/iptables/rules.v6

elif [ "$OS_FAMILY" = "rhel" ]; then
  echo "[+] 正在配置 AlmaLinux/RHEL 防火墙 (nftables)..."
  
  # 规避冲突：关闭并禁用 firewalld
  systemctl stop firewalld || true
  systemctl disable firewalld || true

  systemctl enable nftables
  systemctl start nftables

  # 清空旧规则并创建全新纯净的 ip6 表
  nft delete table ip6 filter 2>/dev/null || true
  nft add table ip6 filter

  # 设置默认策略
  nft 'add chain ip6 filter input { type filter hook input priority filter ; policy drop ; }'
  nft 'add chain ip6 filter forward { type filter hook forward priority filter ; policy drop ; }'
  nft 'add chain ip6 filter output { type filter hook output priority filter ; policy accept ; }'

  # 1. 允许已建立的连接（保证 curl 等出站请求能收到回包，这一步极其重要！）
  nft add rule ip6 filter input ct state { established, related } accept

  # ⚠️ SSH 放行（如需开启请取消注释）
  # nft add rule ip6 filter input tcp dport 22 accept

  # 2. 允许 IPv6 底层生存所必需的 NDP 协议和 MTU 协商
  nft add rule ip6 filter input icmpv6 type nd-neighbor-solicit accept
  nft add rule ip6 filter input icmpv6 type nd-neighbor-advert accept
  nft add rule ip6 filter input icmpv6 type packet-too-big accept

  # 3. 拦截外部 Ping 探测
  nft add rule ip6 filter input icmpv6 type echo-request drop
  
  # 拦截 Traceroute 等探测回应
  nft add rule ip6 filter output icmpv6 type time-exceeded drop
  nft add rule ip6 filter output icmpv6 type destination-unreachable drop

  # 4. 写入 AlmaLinux 10 官方正确的持久化路径
  echo "[+] 保存规则并重启 nftables..."
  nft list ruleset > /etc/sysconfig/nftables.conf
  systemctl restart nftables
fi

echo "[✓] 完成！通用 IPv6 防火墙脚本已完美执行。"
