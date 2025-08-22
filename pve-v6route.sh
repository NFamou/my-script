#!/bin/bash
set -e

# 默认策略
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# 已建立连接
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 必要的 ICMPv6
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 133 -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 134 -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 135 -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 136 -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 1   -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 2   -j ACCEPT
ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type 3   -j ACCEPT

# FORWARD 也要放行 ICMPv6，保证容器能用
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 133 -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 134 -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 135 -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 136 -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 1   -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 2   -j ACCEPT
ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type 3   -j ACCEPT

# 丢掉 ping6 探测
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

# 容器 ↔ 隧道允许
ip6tables -A FORWARD -i vmbr1 -o he-ipv6 -j ACCEPT
ip6tables -A FORWARD -i he-ipv6 -o vmbr1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 保存规则
ip6tables-save > /etc/iptables/rules.v6

echo "[✓] IPv6 防火墙规则已应用并保存"
