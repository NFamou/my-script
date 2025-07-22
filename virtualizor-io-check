#!/bin/bash

CGROUP_BASE="/sys/fs/cgroup/blkio/lxc.payload"
INTERVAL=1  # 间隔 1 秒
LOOP=10     # 连续采样次数（10秒）

declare -A read_prev
declare -A write_prev

# 初始化 read/write 值
init_values() {
    for path in $CGROUP_BASE/v*/blkio.throttle.io_service_bytes; do
        vps=$(basename $(dirname "$path"))
        r=$(grep Read "$path" | awk '{sum += $3} END {print sum}')
        w=$(grep Write "$path" | awk '{sum += $3} END {print sum}')
        read_prev["$vps"]=$r
        write_prev["$vps"]=$w
    done
}

# 每秒循环采样
monitor_io() {
    for ((i=1; i<=LOOP; i++)); do
        echo -e "\n[$(date +%T)] VPS IO Rate (${INTERVAL}s interval):"
        printf "%-10s %-15s %-15s\n" "VPS_ID" "Read (MB/s)" "Write (MB/s)"
        echo "---------------------------------------------"

        for path in $CGROUP_BASE/v*/blkio.throttle.io_service_bytes; do
            vps=$(basename $(dirname "$path"))
            r_now=$(grep Read "$path" | awk '{sum += $3} END {print sum}')
            w_now=$(grep Write "$path" | awk '{sum += $3} END {print sum}')

            r_diff=$(( (r_now - ${read_prev[$vps]}) / 1024 / 1024 ))
            w_diff=$(( (w_now - ${write_prev[$vps]}) / 1024 / 1024 ))

            read_prev["$vps"]=$r_now
            write_prev["$vps"]=$w_now

            printf "%-10s %-15s %-15s\n" "$vps" "$r_diff" "$w_diff"
        done

        sleep $INTERVAL
    done
}

init_values
monitor_io
