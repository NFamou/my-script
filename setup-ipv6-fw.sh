#!/bin/bash
set -e

echo "[+] 安装必要软件包..."
dnf install -y iptables iptables-services iproute net-tools wget curl sudo

echo "[+] 配置 IPv6 防火墙规则..."

# 写入规则文件
cat <<EOF > /etc/sysconfig/ip6tables
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]

# 允许已建立和相关连接
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# 允许邻居发现协议(icmpv6 135/136)
-A INPUT -p ipv6-icmp --icmpv6-type neighbor-solicitation -j ACCEPT
-A INPUT -p ipv6-icmp --icmpv6-type neighbor-advertisement -j ACCEPT

# 允许路径 MTU 发现
-A INPUT -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT

# 阻止 ping 请求
-A INPUT -p ipv6-icmp --icmpv6-type echo-request -j DROP

# 阻止 traceroute 的 time-exceeded 响应
-A OUTPUT -p ipv6-icmp --icmpv6-type time-exceeded -j DROP

# 阻止端口不可达响应
-A OUTPUT -p ipv6-icmp --icmpv6-type destination-unreachable -j DROP

COMMIT
EOF

echo "[+] 重新加载并启动 ip6tables 服务..."
systemctl enable ip6tables
systemctl restart ip6tables

echo "[✓] 完成。IPv6 防火墙规则已应用并设置为开机启动。"

# 显示当前规则确认
ip6tables -S
