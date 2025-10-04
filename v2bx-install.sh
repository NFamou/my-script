#!/bin/bash

# install.sh - 为 V2bX 安装脚本（仅对 raw.githubusercontent.com 使用 gh-proxy.com 代理）

# 使用方法: wget -O install.sh "[https://ghproxy.com/https://raw.githubusercontent.com/你/仓库/分支/install.sh](https://ghproxy.com/https://raw.githubusercontent.com/你/仓库/分支/install.sh)" 或直接把此脚本保存后运行

# 注意：脚本中仅对 raw.githubusercontent.com 的资源使用代理，github.com 与 api.github.com 仍使用直连。

set -e

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir="$(pwd)"

# ====== 仅代理 raw.githubusercontent.com 的配置 ======

# 代理地址（gh-proxy.com），仅用于替换 raw.githubusercontent.com 前缀

RAW_PROXY_PREFIX="[https://gh-proxy.com/https://raw.githubusercontent.com/](https://gh-proxy.com/https://raw.githubusercontent.com/)"

# 如果不想代理 raw.githubusercontent.com，设为空： RAW_PROXY_PREFIX=""

# ==================================================

# 将以 [https://raw.githubusercontent.com/](https://raw.githubusercontent.com/) 开头的 URL 替换为代理 URL；否则原样返回

prox_raw() {
local url="$1"
if [[ -n "$RAW_PROXY_PREFIX" && "$url" =~ ^[https://raw.githubusercontent.com/](https://raw.githubusercontent.com/) ]]; then
# 保留原路径部分并拼接到代理前缀后
echo "${RAW_PROXY_PREFIX}${url#[https://raw.githubusercontent.com/}](https://raw.githubusercontent.com/})"
else
echo "$url"
fi
}

# ---- 检查是否以 root 运行 ----

if [[ $EUID -ne 0 ]]; then
echo -e "${red}错误：${plain} 必须以 root 用户运行此脚本！"
exit 1
fi

# ---- 检测系统发行版 ----

release=""
if [[ -f /etc/redhat-release ]]; then
release="centos"
elif grep -Eqi "alpine" /etc/issue 2>/dev/null || grep -Eqi "alpine" /proc/version 2>/dev/null; then
release="alpine"
elif grep -Eqi "debian" /etc/issue 2>/dev/null || grep -Eqi "debian" /proc/version 2>/dev/null; then
release="debian"
elif grep -Eqi "ubuntu" /etc/issue 2>/dev/null || grep -Eqi "ubuntu" /proc/version 2>/dev/null; then
release="ubuntu"
elif grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /etc/issue 2>/dev/null || grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux" /proc/version 2>/dev/null; then
release="centos"
elif grep -Eqi "arch" /proc/version 2>/dev/null; then
release="arch"
fi

if [[ -z "$release" ]]; then
echo -e "${red}未检测到兼容的系统发行版，请手动确认后再运行脚本。${plain}"
exit 1
fi

# ---- 检测 CPU 架构 ----

arch="$(uname -m)"
case "$arch" in
x86_64|x64|amd64) arch="64" ;;
aarch64|arm64) arch="arm64-v8a" ;;
s390x) arch="s390x" ;;
*)
echo -e "${yellow}警告：检测到不常见架构 ${arch}，默认使用 64 位(x86_64) 版本。${plain}"
arch="64"
;;
esac

# ---- 获取 OS 版本号（用于最低版本判断） ----

os_version=""
if [[ -f /etc/os-release ]]; then
os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $2}' /etc/os-release | sed -n '1p' || true)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release | sed -n '1p' || true)
fi

# ---- 安装基础依赖 ----

install_base() {
if [[ "$release" == "centos" ]]; then
yum install -y epel-release wget curl unzip tar crontabs socat ca-certificates >/dev/null 2>&1 || yum install -y wget curl unzip tar crontabs socat ca-certificates
update-ca-trust force-enable >/dev/null 2>&1 || true
elif [[ "$release" == "alpine" ]]; then
apk update >/dev/null 2>&1 || true
apk add --no-cache wget curl unzip tar socat ca-certificates >/dev/null 2>&1
update-ca-certificates >/dev/null 2>&1 || true
elif [[ "$release" == "debian" || "$release" == "ubuntu" ]]; then
apt-get update -y >/dev/null 2>&1 || true
DEBIAN_FRONTEND=noninteractive apt-get install -y wget curl unzip tar cron socat ca-certificates >/dev/null 2>&1
update-ca-certificates >/dev/null 2>&1 || true
elif [[ "$release" == "arch" ]]; then
pacman -Sy --noconfirm >/dev/null 2>&1
pacman -S --noconfirm --needed wget curl unzip tar cronie socat ca-certificates >/dev/null 2>&1
fi
}

# ---- 检查 V2bX 服务状态 helper ----

check_status() {
if [[ ! -f /usr/local/V2bX/V2bX ]]; then
return 2
fi
if [[ "$release" == "alpine" ]]; then
if service V2bX status >/dev/null 2>&1; then
return 0
else
return 1
fi
else
if systemctl is-active --quiet V2bX; then
return 0
else
return 1
fi
fi
}

# ---- 主安装函数 ----

install_V2bX() {
# 清理旧目录并创建新目录
if [[ -d /usr/local/V2bX ]]; then
rm -rf /usr/local/V2bX
fi
mkdir -p /usr/local/V2bX
cd /usr/local/V2bX

```
# 获取最新版本（使用 github releases 页面重定向到 latest）
if [[ $# -eq 0 ]]; then
    # 直接请求 github 的 releases/latest，会被 302 重定向到实际页面；用 curl -sI 获得 Location 也可
    # 这里直接解析 releases/latest 页面获得 tag（容错：若解析失败可手动指定版本号作为参数）
    echo -e "${green}检测 V2bX 最新版本...${plain}"
    # 尝试通过 GitHub API 来获取（注意 API 可能有限制）
    last_version="$(curl -s "https://api.github.com/repos/wyx2685/V2bX/releases/latest" | grep -m1 '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)"
    if [[ -z "$last_version" ]]; then
        # 回退到通过网页重定向获取
        last_version="$(curl -sI -L https://github.com/wyx2685/V2bX/releases/latest | grep -i location | tail -n1 | awk -F'/' '{print $NF}' | tr -d $'\r' || true)"
    fi
    if [[ -z "$last_version" ]]; then
        echo -e "${red}检测 V2bX 版本失败，请手动指定版本安装，例如：bash install.sh v1.2.3${plain}"
        exit 1
    fi
    echo -e "${green}检测到 V2bX 最新版本：${last_version}${plain}"
    zip_url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
else
    last_version="$1"
    zip_url="https://github.com/wyx2685/V2bX/releases/download/${last_version}/V2bX-linux-${arch}.zip"
    echo -e "${green}开始安装指定版本：${last_version}${plain}"
fi

# 下载二进制 zip（github.com 直连）
echo -e "${green}下载 V2bX 二进制包...${plain}"
if ! wget -q -O V2bX-linux.zip "${zip_url}"; then
    echo -e "${red}下载 V2bX 二进制包失败，请检查网络或手动下载后上传到 /usr/local/V2bX/ 并重试。${plain}"
    exit 1
fi

# 解压与设置权限
unzip -o V2bX-linux.zip >/dev/null 2>&1 || true
rm -f V2bX-linux.zip
if [[ -f V2bX ]]; then
    chmod +x V2bX
else
    echo -e "${red}未在压缩包中找到 V2bX 可执行文件，安装失败。${plain}"
    exit 1
fi

# 拷贝数据文件
mkdir -p /etc/V2bX
if [[ -f geoip.dat ]]; then
    cp -f geoip.dat /etc/V2bX/
fi
if [[ -f geosite.dat ]]; then
    cp -f geosite.dat /etc/V2bX/
fi

# 安装 systemd 服务或 OpenRC 脚本
if [[ "$release" == "alpine" ]]; then
    # OpenRC
    cat > /etc/init.d/V2bX <<'EOF'
```

#!/sbin/openrc-run
name="V2bX"
description="V2bX service"
command="/usr/local/V2bX/V2bX"
command_args="server"
command_user="root"
pidfile="/run/V2bX.pid"
command_background="yes"
depend() {
need net
}
EOF
chmod +x /etc/init.d/V2bX
rc-update add V2bX default || true
service V2bX start || true
else
# systemd
cat > /etc/systemd/system/V2bX.service <<'EOF'
[Unit]
Description=V2bX Service
After=network.target nss-lookup.target
Wants=network.target

[Service]
User=root
Group=root
Type=simple
LimitAS=infinity
LimitRSS=infinity
LimitCORE=infinity
LimitNOFILE=999999
WorkingDirectory=/usr/local/V2bX/
ExecStart=/usr/local/V2bX/V2bX server
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload || true
systemctl enable V2bX || true
systemctl restart V2bX || true
fi

```
# 下载并安装管理脚本（仅走 RAW_PROXY_PREFIX 代理）
echo -e "${green}下载 V2bX 管理脚本（V2bX.sh）...（raw.githubusercontent.com 使用代理）${plain}"
v2bx_sh_raw_url="https://raw.githubusercontent.com/wyx2685/V2bX-script/master/V2bX.sh"
v2bx_sh_url="$(prox_raw "${v2bx_sh_raw_url}")"
if ! curl -fsSL -o /usr/bin/V2bX "${v2bx_sh_url}"; then
    # 回退：尝试不使用代理直接拉取（以防代理不可用）
    echo -e "${yellow}通过代理下载 V2bX 管理脚本失败，尝试直连 raw.githubusercontent.com...${plain}"
    if ! curl -fsSL -o /usr/bin/V2bX "${v2bx_sh_raw_url}"; then
        echo -e "${red}下载 V2bX 管理脚本失败，请检查网络或手动获取 V2bX.sh 并放置在 /usr/bin/V2bX。${plain}"
        # 继续但提示用户
    fi
fi
chmod +x /usr/bin/V2bX || true
ln -sf /usr/bin/V2bX /usr/bin/v2bx || true

# 默认配置文件复制（若压缩包内含示例 config.json 等）
if [[ -f config.json && ! -f /etc/V2bX/config.json ]]; then
    cp -f config.json /etc/V2bX/
fi
if [[ -f dns.json && ! -f /etc/V2bX/dns.json ]]; then
    cp -f dns.json /etc/V2bX/
fi
if [[ -f route.json && ! -f /etc/V2bX/route.json ]]; then
    cp -f route.json /etc/V2bX/
fi
if [[ -f custom_outbound.json && ! -f /etc/V2bX/custom_outbound.json ]]; then
    cp -f custom_outbound.json /etc/V2bX/
fi
if [[ -f custom_inbound.json && ! -f /etc/V2bX/custom_inbound.json ]]; then
    cp -f custom_inbound.json /etc/V2bX/
fi

# 清理安装脚本（如果当前目录为原始下载目录）
cd "${cur_dir}" || true
rm -f install.sh || true

echo -e ""
echo -e "${green}V2bX ${last_version} 安装完成（raw.githubusercontent.com 的脚本下载已使用代理处理）。${plain}"
echo -e "可用管理命令：V2bX | V2bX start|stop|restart|status|enable|disable|log|update|install|uninstall|version"
echo -e ""
```

}

# ---- 主流程 ----

echo -e "${green}开始安装前的准备（安装基础依赖）...${plain}"
install_base
install_V2bX "$1" || {
echo -e "${red}安装过程遇到错误，已退出。请检查上方输出并修复问题后重试。${plain}"
exit 1
}
