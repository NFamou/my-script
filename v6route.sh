#!/bin/bash

set -e  # 一旦出错就退出，避免后续命令执行错误

# 安装必要工具
apt install -y curl wget sudo iptables net-tools iproute2 iptables-persistent

# 配置 ip6tables 防火墙规则（最小可用）
echo "[+] 设置默认策略..."
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

echo "[+] 允许已建立连接..."
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# ⚠️ SSH建议默认放行，除非你提前有IPv4或串口控制，否则可能断连
# ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT

echo "[+] 允许必要ICMPv6：NDP / MTU..."
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

echo "[+] 阻止 ping6 探测..."
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

echo "[+] 阻止 traceroute6..."
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP

echo "[+] 阻止端口不可达提示..."
ip6tables -A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP

# 保存规则
echo "[+] 保存防火墙规则为开机自启..."
ip6tables-save > /etc/iptables/rules.v6

echo "[✓] 完成。当前规则已加载并设置开机持久化。"
