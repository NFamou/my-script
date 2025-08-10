#!/bin/bash

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # 恢复默认颜色

# 欢迎信息
echo -e "${GREEN}============================================${NC}"
echo -e "${CYAN}        隧道服务器网络质量测试工具        ${NC}"
echo -e "${GREEN}============================================${NC}"

# 检查是否为root用户
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${YELLOW}提示: 建议使用root权限运行以获得更准确的网络测试结果${NC}"
        sleep 2
    fi
}

# 检查必要的工具是否安装
check_dependencies() {
    local dependencies=("ping" "sort" "awk" "grep" "bc")
    local missing=()
    
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}缺少必要的工具: ${missing[*]}${NC}"
        echo -e "${YELLOW}正在尝试安装...${NC}"
        
        if command -v apt &> /dev/null; then
            apt update && apt install -y inetutils-ping bc procps
        elif command -v yum &> /dev/null; then
            yum install -y iputils bc procps-ng
        elif command -v dnf &> /dev/null; then
            dnf install -y iputils bc procps-ng
        else
            echo -e "${RED}无法自动安装依赖，请手动安装以下工具: ${missing[*]}${NC}"
            exit 1
        fi
    fi
}

# 定义IP地址列表
declare -a ip_list=(
    "216.66.22.2"        # Ashburn, VA, US
    "216.218.200.58"     # Calgary, AB, CA
    "184.105.253.14"     # Chicago, IL, US
    "184.105.253.10"     # Dallas, TX, US
    "184.105.250.46"     # Denver, CO, US
    "72.52.104.74"       # Fremont, CA, US
    "64.62.134.130"      # Fremont, CA, US
    "64.71.156.86"       # Honolulu, HI, US
    "216.66.77.230"      # Kansas City, MO, US
    "66.220.18.42"       # Los Angeles, CA, US
    "209.51.161.58"      # Miami, FL, US
    "209.51.161.14"      # New York, NY, US
    "66.220.7.82"        # Phoenix, AZ, US
    "216.218.226.238"    # Seattle, WA, US
    "216.66.38.58"       # Toronto, ON, CA
    "184.105.255.26"     # Winnipeg, MB, CA
    "216.66.86.114"      # Berlin, DE
    "216.66.87.14"       # Budapest, HU
    "216.66.80.30"       # Frankfurt, DE
    "216.66.87.102"      # Lisbon, PT
    "216.66.80.26"       # London, UK
    "216.66.88.98"       # London, UK
    "216.66.84.42"       # Paris, FR
    "216.66.86.122"      # Prague, CZ
    "216.66.80.90"       # Stockholm, SE
    "216.66.80.98"       # Zurich, CH
    "216.218.221.6"      # Hong Kong, HK
    "216.218.221.42"     # Singapore, SG
    "74.82.46.6"         # Tokyo, JP
    "216.66.87.98"       # Djibouti City, DJ
    "216.66.87.134"      # Johannesburg, ZA
    "216.66.64.154"      # Bogota, CO
    "216.218.142.50"     # Sydney, NSW, AU
    "216.66.90.30"       # Dubai, AE
)

# 定义位置映射
declare -A locations
locations["216.66.22.2"]="Ashburn, VA, US"
locations["216.218.200.58"]="Calgary, AB, CA"
locations["184.105.253.14"]="Chicago, IL, US"
locations["184.105.253.10"]="Dallas, TX, US"
locations["184.105.250.46"]="Denver, CO, US"
locations["72.52.104.74"]="Fremont, CA, US"
locations["64.62.134.130"]="Fremont, CA, US"
locations["64.71.156.86"]="Honolulu, HI, US"
locations["216.66.77.230"]="Kansas City, MO, US"
locations["66.220.18.42"]="Los Angeles, CA, US"
locations["209.51.161.58"]="Miami, FL, US"
locations["209.51.161.14"]="New York, NY, US"
locations["66.220.7.82"]="Phoenix, AZ, US"
locations["216.218.226.238"]="Seattle, WA, US"
locations["216.66.38.58"]="Toronto, ON, CA"
locations["184.105.255.26"]="Winnipeg, MB, CA"
locations["216.66.86.114"]="Berlin, DE"
locations["216.66.87.14"]="Budapest, HU"
locations["216.66.80.30"]="Frankfurt, DE"
locations["216.66.87.102"]="Lisbon, PT"
locations["216.66.80.26"]="London, UK"
locations["216.66.88.98"]="London, UK"
locations["216.66.84.42"]="Paris, FR"
locations["216.66.86.122"]="Prague, CZ"
locations["216.66.80.90"]="Stockholm, SE"
locations["216.66.80.98"]="Zurich, CH"
locations["216.218.221.6"]="Hong Kong, HK"
locations["216.218.221.42"]="Singapore, SG"
locations["74.82.46.6"]="Tokyo, JP"
locations["216.66.87.98"]="Djibouti City, DJ"
locations["216.66.87.134"]="Johannesburg, ZA"
locations["216.66.64.154"]="Bogota, CO"
locations["216.218.142.50"]="Sydney, NSW, AU"
locations["216.66.90.30"]="Dubai, AE"

# 默认参数
ping_count=10
display_count=5
output_file="tunnel_server_test_$(date +%Y%m%d_%H%M%S).txt"

# 显示帮助信息
show_help() {
    echo -e "${CYAN}用法: $0 [选项]${NC}"
    echo -e "${CYAN}选项:${NC}"
    echo -e "  ${GREEN}-c, --count NUM${NC}     每个IP测试的次数 (默认: $ping_count)"
    echo -e "  ${GREEN}-d, --display NUM${NC}   每个排序类别显示的数量 (默认: $display_count)"
    echo -e "  ${GREEN}-o, --output FILE${NC}   输出文件名 (默认: $output_file)"
    echo -e "  ${GREEN}-h, --help${NC}          显示此帮助信息"
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--count)
                ping_count="$2"
                shift 2
                ;;
            -d|--display)
                display_count="$2"
                shift 2
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}未知选项: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# 主测试函数
test_servers() {
    local total_ips=${#ip_list[@]}
    local results_file=$(mktemp)
    
    echo -e "${CYAN}开始测试 $total_ips 个服务器，每个服务器测试 $ping_count 次...${NC}"
    echo -e "${YELLOW}请耐心等待，测试过程中请勿中断...${NC}\n"
    
    # 显示进度条
    local progress=0
    
    for ip in "${ip_list[@]}"; do
        # 更新进度
        progress=$((progress + 1))
        percent=$((progress * 100 / total_ips))
        
        # 显示进度条
        printf "${YELLOW}[%-50s] %d%% 测试: %s${NC}\r" \
               "$(printf '#%.0s' $(seq 1 $((percent / 2))))" \
               "$percent" \
               "$ip"
        
        # 使用ping测试
        if ping_result=$(ping -c "$ping_count" -W 2 "$ip" 2>/dev/null); then
            # 提取统计信息
            avg_latency=$(echo "$ping_result" | grep -oP 'avg=\K[0-9\.]+' || echo "0")
            packet_loss=$(echo "$ping_result" | grep -oP '[0-9\.]+(?=% packet loss)' || echo "100")
            
            # 计算综合得分 (低延迟、低丢包率得高分)
            # 公式: 100 - (normalized_latency * 0.6 + packet_loss * 0.4)
            if (( $(echo "$avg_latency > 0" | bc -l) )); then
                # 延迟正常化: 假设300ms为最大值
                normalized_latency=$(echo "scale=2; ($avg_latency / 300) * 100" | bc -l)
                # 确保不超过100
                normalized_latency=$(echo "if ($normalized_latency > 100) 100 else $normalized_latency" | bc -l)
                
                # 计算得分
                score=$(echo "scale=2; 100 - ($normalized_latency * 0.6 + $packet_loss * 0.4)" | bc -l)
                
                # 确保得分在0-100之间
                score=$(echo "if ($score < 0) 0 else $score" | bc -l)
                score=$(echo "if ($score > 100) 100 else $score" | bc -l)
            else
                score="0"
            fi
            
            # 写入临时文件
            echo "$ip|${locations[$ip]}|$avg_latency|$packet_loss|$score" >> "$results_file"
        else
            # 写入临时文件，标记为不可达
            echo "$ip|${locations[$ip]}|999|100|0" >> "$results_file"
        fi
    done
    
    echo -e "\n${GREEN}测试完成!${NC}\n"
    
    # 保存原始结果
    echo "# 服务器网络质量测试结果" > "$output_file"
    echo "# 测试时间: $(date)" >> "$output_file"
    echo "# 每个服务器测试 $ping_count 次" >> "$output_file"
    echo "" >> "$output_file"
    
    # 按延迟排序
    echo -e "${PURPLE}====== 按延迟排序 (ms) ======${NC}"
    echo "====== 按延迟排序 (ms) ======" >> "$output_file"
    echo -e "${CYAN}排名\tIP地址\t\t位置\t\t\t延迟(ms)\t丢包率(%)\t综合得分${NC}"
    echo "排名 IP地址            位置                    延迟(ms)  丢包率(%)  综合得分" >> "$output_file"
    
    sort -t'|' -k3,3n "$results_file" | head -n "$display_count" | 
    awk -F'|' '{printf "'"${GREEN}"'%2d\t'"${NC}"'%s\t'"${YELLOW}"'%-20s\t'"${NC}"''"${CYAN}"'%7.2f\t'"${NC}"''"${RED}"'%7.2f\t\t'"${NC}"''"${PURPLE}"'%7.2f'"${NC}"'\n", NR, $1, $2, $3, $4, $5}'
    
    sort -t'|' -k3,3n "$results_file" | 
    awk -F'|' '{printf "%2d %-15s %-25s %7.2f     %7.2f     %7.2f\n", NR, $1, $2, $3, $4, $5}' >> "$output_file"
    
    echo "" >> "$output_file"
    
    # 按丢包率排序
    echo -e "\n${PURPLE}====== 按丢包率排序 (%) ======${NC}"
    echo "====== 按丢包率排序 (%) ======" >> "$output_file"
    echo -e "${CYAN}排名\tIP地址\t\t位置\t\t\t延迟(ms)\t丢包率(%)\t综合得分${NC}"
    echo "排名 IP地址            位置                    延迟(ms)  丢包率(%)  综合得分" >> "$output_file"
    
    sort -t'|' -k4,4n "$results_file" | head -n "$display_count" | 
    awk -F'|' '{printf "'"${GREEN}"'%2d\t'"${NC}"'%s\t'"${YELLOW}"'%-20s\t'"${NC}"''"${CYAN}"'%7.2f\t'"${NC}"''"${RED}"'%7.2f\t\t'"${NC}"''"${PURPLE}"'%7.2f'"${NC}"'\n", NR, $1, $2, $3, $4, $5}'
    
    sort -t'|' -k4,4n "$results_file" | 
    awk -F'|' '{printf "%2d %-15s %-25s %7.2f     %7.2f     %7.2f\n", NR, $1, $2, $3, $4, $5}' >> "$output_file"
    
    echo "" >> "$output_file"
    
    # 按综合得分排序
    echo -e "\n${PURPLE}====== 按综合得分排序 (0-100) ======${NC}"
    echo "====== 按综合得分排序 (0-100) ======" >> "$output_file"
    echo -e "${CYAN}排名\tIP地址\t\t位置\t\t\t延迟(ms)\t丢包率(%)\t综合得分${NC}"
    echo "排名 IP地址            位置                    延迟(ms)  丢包率(%)  综合得分" >> "$output_file"
    
    sort -t'|' -k5,5nr "$results_file" | head -n "$display_count" | 
    awk -F'|' '{printf "'"${GREEN}"'%2d\t'"${NC}"'%s\t'"${YELLOW}"'%-20s\t'"${NC}"''"${CYAN}"'%7.2f\t'"${NC}"''"${RED}"'%7.2f\t\t'"${NC}"''"${PURPLE}"'%7.2f'"${NC}"'\n", NR, $1, $2, $3, $4, $5}'
    
    sort -t'|' -k5,5nr "$results_file" | 
    awk -F'|' '{printf "%2d %-15s %-25s %7.2f     %7.2f     %7.2f\n", NR, $1, $2, $3, $4, $5}' >> "$output_file"
    
    echo -e "\n${GREEN}详细结果已保存到: ${YELLOW}$output_file${NC}"
    
    # 清理临时文件
    rm -f "$results_file"
}

# 主函数
main() {
    check_root
    check_dependencies
    parse_args "$@"
    test_servers
}

# 执行主函数
main "$@"
