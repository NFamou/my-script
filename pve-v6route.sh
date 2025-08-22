#!/bin/bash
set -e

# 安装必要工具
apt update
apt install -y iptables iptables-persistent

# 开启 IPv6 转发
sysctl -w net.ipv6.conf.all.forwarding=1
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf

# 清理原有规则（可选）
ip6tables -F
ip6tables -t nat -F
ip6tables -X

# 默认策略
ip6tables -P INPUT DROP
ip6tables -P FORWARD DROP
ip6tables -P OUTPUT ACCEPT

# 已建立连接放行
ip6tables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 必要 ICMPv6 类型放行
for t in 133 134 135 136 1 2 3; do
    ip6tables -A INPUT  -p ipv6-icmp --icmpv6-type $t -j ACCEPT
    ip6tables -A FORWARD -p ipv6-icmp --icmpv6-type $t -j ACCEPT
done

# 丢掉 ping6 探测
ip6tables -A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

# 容器 ↔ 隧道允许
ip6tables -A FORWARD -i vmbr1 -o he-ipv6 -j ACCEPT
ip6tables -A FORWARD -i he-ipv6 -o vmbr1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 源 NAT，让 LXC 容器 IPv6 能出网
ip6tables -t nat -A POSTROUTING -s 2001:470:1f0b:225::/64 -o he-ipv6 -j MASQUERADE

# 保存规则
ip6tables-save > /etc/iptables/rules.v6

echo "[✓] 宿主机 + LXC 容器 IPv6 防火墙配置完成"
