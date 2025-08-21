#!/bin/bash

# 网桥接口
BRIDGE_IF="vmbr0"

# 内网IP范围
START=200
END=254

# 清理已有相关规则（可选，防止重复添加）
iptables -t nat -F PREROUTING
iptables -F FORWARD

for i in $(seq $START $END); do
    IP="172.16.1.$i"

    # SSH端口映射：公网61xxx → 内网IP:22
    SSH_PORT=$((61000 + i))
    for PROTO in tcp udp; do
        iptables -t nat -A PREROUTING -i $BRIDGE_IF -p $PROTO --dport $SSH_PORT -j DNAT --to-destination $IP:22
        iptables -A FORWARD -p $PROTO -d $IP --dport 22 -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT
    done

    # 可用端口范围映射：10000 + i*10 + 1~9 → 内网对应端口
    BASE_PORT=$((10000 + i * 10))
    for j in $(seq 1 9); do
        PUB_PORT=$((BASE_PORT + j))
        for PROTO in tcp udp; do
            iptables -t nat -A PREROUTING -i $BRIDGE_IF -p $PROTO --dport $PUB_PORT -j DNAT --to-destination $IP:$PUB_PORT
            iptables -A FORWARD -p $PROTO -d $IP --dport $PUB_PORT -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT
        done
    done
done

# 保存规则，确保重启后生效
netfilter-persistent save

echo "端口转发规则已应用并保存（TCP/UDP）。"
