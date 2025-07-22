#!/bin/bash

INTERVAL=5
CGROUP_BASE="/sys/fs/cgroup/blkio/lxc.payload"

declare -A read1
declare -A write1
declare -A read2
declare -A write2

get_totals() {
    for path in $CGROUP_BASE/v*/blkio.throttle.io_service_bytes; do
        vps=$(echo "$path" | awk -F'/' '{print $(NF-1)}')  # 提取 v100X
        r=$(grep Read "$path" | awk '{sum += $3} END {print sum}')
        w=$(grep Write "$path" | awk '{sum += $3} END {print sum}')
        read1["$vps"]=$r
        write1["$vps"]=$w
    done
}

echo "⏳ Collecting IO stats... please wait $INTERVAL seconds"
get_totals
sleep $INTERVAL

# 第二次采样
for path in $CGROUP_BASE/v*/blkio.throttle.io_service_bytes; do
    vps=$(echo "$path" | awk -F'/' '{print $(NF-1)}')
    r=$(grep Read "$path" | awk '{sum += $3} END {print sum}')
    w=$(grep Write "$path" | awk '{sum += $3} END {print sum}')
    read2["$vps"]=$r
    write2["$vps"]=$w
done

echo -e "\n📊 VPS IO Usage in the last $INTERVAL seconds:"
printf "%-10s %-15s %-15s\n" "VPS_ID" "Read (MB/s)" "Write (MB/s)"
echo "---------------------------------------------"

for vps in "${!read1[@]}"; do
    r_diff=$(( (${read2[$vps]} - ${read1[$vps]}) / 1024 / 1024 / $INTERVAL ))
    w_diff=$(( (${write2[$vps]} - ${write1[$vps]}) / 1024 / 1024 / $INTERVAL ))
    printf "%-10s %-15s %-15s\n" "$vps" "$r_diff" "$w_diff"
done
