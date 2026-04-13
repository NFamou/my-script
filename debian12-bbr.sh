#!/bin/bash
#
# Debian 12 TCP/BBR/FQ auto-tune script
# Author: ChatGPT
# Date: 2025-09-22
#

set -euo pipefail

backup_conflict_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d%H%M%S)
        mv "$file" "${file}.bak.${timestamp}"
        echo "已备份冲突文件: $file -> ${file}.bak.${timestamp}"
    fi
}

# 检测内存
total_mem=$(free -m | awk '/Mem:/ {print $2}')
echo "检测到内存: ${total_mem} MB"
if [[ $total_mem -lt 1024 ]]; then
    echo "⚠️ 内存小于 1G，可能不适合调优"
fi

# 检测默认网卡
default_iface=$(ip route show default | awk '{print $5}' | head -n1)
echo "默认网卡: $default_iface"

# 检测 RTT
client_ip=$(echo "${SSH_CLIENT:-}" | awk '{print $1}')
if [[ -z "$client_ip" ]]; then
    client_ip="1.1.1.1"
fi
rtt=$(ping -c 5 -q "$client_ip" 2>/dev/null | awk -F'/' '/rtt/ {print int($5)}')
if [[ -z "$rtt" ]]; then
    rtt=50
fi
echo "检测到 RTT: ${rtt} ms"

# 默认带宽
bandwidth_mbps=1000
echo "默认带宽: ${bandwidth_mbps} Mbps"

# 计算 BDP
bandwidth_bps=$((bandwidth_mbps * 1000000 / 8))
bdp_bytes=$((bandwidth_bps * rtt / 1000))
echo "计算 BDP: ${bdp_bytes} bytes"

# 取最近的桶值
for candidate in 4194304 8388608 16777216 33554432 67108864; do
    if [[ $bdp_bytes -le $candidate ]]; then
        bucket=$candidate
        break
    fi
done
bucket=${bucket:-67108864}
echo "使用桶值: $bucket ($((bucket/1024/1024)) MB)"

# 清理冲突配置
echo "清理冲突 sysctl 配置..."
sed -i.bak "/net.core.rmem_max/d;/net.core.wmem_max/d;/net.ipv4.tcp_rmem/d;/net.ipv4.tcp_wmem/d;/net.ipv4.tcp_congestion_control/d;/net.core.default_qdisc/d" /etc/sysctl.conf || true

for f in /etc/sysctl.d/*.conf; do
    if grep -Eq 'net\.core\.rmem_max|net\.core\.wmem_max|net\.ipv4\.tcp_rmem|net\.ipv4\.tcp_wmem|net\.ipv4\.tcp_congestion_control|net\.core\.default_qdisc' "$f"; then
        backup_conflict_file "$f"
    fi
done

# 写入新配置
cat >/etc/sysctl.d/999-net-bbr-fq.conf <<EOF
net.core.rmem_max = $bucket
net.core.wmem_max = $bucket
net.ipv4.tcp_rmem = 4096 87380 $bucket
net.ipv4.tcp_wmem = 4096 65536 $bucket
net.ipv4.tcp_congestion_control = bbr
net.core.default_qdisc = fq
EOF

sysctl --system >/dev/null

# 应用 qdisc
tc qdisc replace dev "$default_iface" root fq || true

# 打印结果
echo "==== RESULT ===="
echo "最终使用值 -> 内存: ${total_mem} MB, 带宽: ${bandwidth_mbps} Mbps, RTT: ${rtt} ms"
echo "桶值: $bucket ($((bucket/1024/1024)) MB)"
sysctl net.ipv4.tcp_congestion_control
sysctl net.core.default_qdisc
sysctl net.core.rmem_max
sysctl net.core.wmem_max
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
tc qdisc show dev "$default_iface" | head -n1
echo "================"
