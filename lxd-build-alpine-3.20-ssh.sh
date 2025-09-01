#!/usr/bin/env bash
set -euo pipefail

# ===== 你可以改的参数 =====
RELEASE="${RELEASE:-3.20}"                           # 目标 Alpine 版本
ROOT_PASSWORD="${ROOT_PASSWORD:-ChangeMe_123!}"      # <<< 改成你的强密码
SSH_PORT="${SSH_PORT:-22}"                           # 需要改端口就改这里

# ===== 路径与仓库 =====
WORKDIR="$(pwd)"
ROOTFS="${WORKDIR}/rootfs"
MIRROR_BASE="${MIRROR_BASE:-http://dl-cdn.alpinelinux.org/alpine}"
REPO_MAIN="${REPO_MAIN:-${MIRROR_BASE}/v${RELEASE}/main}"
REPO_COMM="${REPO_COMM:-${MIRROR_BASE}/v${RELEASE}/community}"

# ===== 架构处理 =====
ARCH_OPT="${1:-}"                # 可用: --arch x86_64|x86|aarch64|armhf
HOST_ARCH="$(uname -m)"
APK_ARCH="${APK_ARCH:-$HOST_ARCH}"
if [[ "$ARCH_OPT" == "--arch" ]]; then shift || true; APK_ARCH="${1:-$APK_ARCH}"; shift || true; fi
case "$APK_ARCH" in
  x86_64|aarch64|x86|armhf) ;;
  i[3-6]86) APK_ARCH="x86" ;;
  arm*)     APK_ARCH="armhf" ;;
  *) echo "不支持的架构: $APK_ARCH"; exit 1;;
esac

# ===== 准备 apk.static（从 v${RELEASE}/main 拉 alpine-keys 与 apk-tools-static）=====
APK="${WORKDIR}/apk.static"
need_apk=0; [[ -x "$APK" ]] || need_apk=1
if [[ $need_apk -eq 1 ]]; then
  echo ">> 获取 apk-tools-static & alpine-keys （$REPO_MAIN/$APK_ARCH）"
  TMPD="$(mktemp -d)"; trap 'rm -rf "$TMPD"' EXIT
  wget -qO- "$REPO_MAIN/$APK_ARCH/APKINDEX.tar.gz" \
    | tar -Oxz APKINDEX \
    | awk -F: '
      $0!=""{f[$1]=$2}
      $0==""{ if(f["P"]=="alpine-keys") print f["P"]"-"f["V"]".apk";
               if(f["P"]=="apk-tools-static") print f["P"]"-"f["V"]".apk"; }' \
    > "$TMPD/pkgs.list"
  mkdir -p "$TMPD/pkgs"
  while read -r pkg; do
    echo ".. 下载 $pkg"
    wget -qO- "$REPO_MAIN/$APK_ARCH/$pkg" | tar -xz -C "$TMPD/pkgs"
  done < "$TMPD/pkgs.list"
  cp "$TMPD/pkgs/sbin/apk.static" "$APK"; chmod +x "$APK"
  KEYS_DIR="$TMPD/pkgs/etc/apk/keys"
else
  KEYS_DIR=""
fi

# ===== 构建 rootfs =====
echo ">> 构建 rootfs 到 $ROOTFS"
rm -rf "$ROOTFS"; mkdir -p "$ROOTFS/etc/apk"

# 写 repositories（main + community）
cat > "$ROOTFS/etc/apk/repositories" <<EOF
$REPO_MAIN
$REPO_COMM
EOF

# 拷贝 keys（若已下载）
if [[ -n "${KEYS_DIR}" && -d "${KEYS_DIR}" ]]; then
  mkdir -p "$ROOTFS/etc/apk/keys"; cp -a "${KEYS_DIR}/"*.pub "$ROOTFS/etc/apk/keys/"
fi

# 安装最小系统 + openssh
echo ">> 安装 alpine-base + openssh ..."
"$APK" add -U --initdb --root "$ROOTFS" --arch "$APK_ARCH" alpine-base openssh

# ===== 基础配置：inittab、网络、服务 =====
echo ">> 写入基础系统配置"
cat >"$ROOTFS/etc/inittab"<<'EOF'
::sysinit:/sbin/rc sysinit
::sysinit:/sbin/rc boot
::wait:/sbin/rc default
::ctrlaltdel:/sbin/reboot
::shutdown:/sbin/rc shutdown
EOF

mkdir -p "$ROOTFS/etc/network"
cat > "$ROOTFS/etc/network/interfaces" <<'EOF'
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# 开机服务：networking/syslog/bootmisc + sshd
mkdir -p "$ROOTFS/etc/runlevels/boot" "$ROOTFS/etc/runlevels/default"
ln -sf /etc/init.d/bootmisc   "$ROOTFS/etc/runlevels/boot/bootmisc"
ln -sf /etc/init.d/networking "$ROOTFS/etc/runlevels/boot/networking"
ln -sf /etc/init.d/syslog     "$ROOTFS/etc/runlevels/boot/syslog"
ln -sf /etc/init.d/sshd       "$ROOTFS/etc/runlevels/default/sshd"

# ===== SSH 配置：允许 root 密码登录、可选改端口 =====
mkdir -p "$ROOTFS/etc/ssh"
if [[ -f "$ROOTFS/etc/ssh/sshd_config" ]]; then
  sed -i \
    -e 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' \
    -e 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' \
    "$ROOTFS/etc/ssh/sshd_config"
else
  cat > "$ROOTFS/etc/ssh/sshd_config" <<EOF
Port $SSH_PORT
Protocol 2
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
PermitRootLogin yes
PasswordAuthentication yes
UsePAM no
ChallengeResponseAuthentication no
Subsystem sftp /usr/lib/ssh/sftp-server
EOF
fi
# 修改端口（如果不是 22）
if [[ "$SSH_PORT" != "22" ]]; then
  sed -i "s/^Port .*/Port $SSH_PORT/" "$ROOTFS/etc/ssh/sshd_config"
fi

# ===== 设定 root 密码（写入 /etc/shadow，使用 SHA-512 哈希）=====
echo ">> 设置 root 密码（/etc/shadow）"
HASH=""
if command -v openssl >/dev/null 2>&1; then
  # 生成 SHA-512 哈希
  HASH="$(openssl passwd -6 "$ROOT_PASSWORD")"
else
  echo "WARN: 宿主机没有 openssl，root 密码将保持默认（不可远程密码登录）；请开机后手动 passwd"
fi

if [[ -n "$HASH" ]]; then
  # 如果 shadow 存在，替换 root 行；否则创建一个最简 shadow
  if [[ -f "$ROOTFS/etc/shadow" ]]; then
    awk -F: -v h="$HASH" 'BEGIN{OFS=FS} $1=="root"{$2=h} {print}' \
      "$ROOTFS/etc/shadow" > "$ROOTFS/etc/shadow.new"
    mv -f "$ROOTFS/etc/shadow.new" "$ROOTFS/etc/shadow"
    chmod 600 "$ROOTFS/etc/shadow"
  else
    echo "root:$HASH:0:0:99999:7:::" > "$ROOTFS/etc/shadow"
    chmod 600 "$ROOTFS/etc/shadow"
  fi
fi

# 清理缓存、移除 apk.static
rm -rf "$ROOTFS/var/cache/apk"/*
rm -f "$ROOTFS/sbin/apk.static"*

# ===== 生成 LXD metadata =====
echo ">> 生成 metadata.yaml 与 templates"
CREATION_EPOCH="$(date +%s)"
CREATION_HUMAN="$(date +%Y%m%d_%H:%M)"
case "$APK_ARCH" in
  x86_64) LXD_ARCH="x86_64";;
  x86)    LXD_ARCH="i686";;
  aarch64)LXD_ARCH="aarch64";;
  armhf)  LXD_ARCH="armv7l";;
  *)      LXD_ARCH="$APK_ARCH";;
esac

cat > "$WORKDIR/metadata.yaml" <<EOF
{
  "architecture": "${LXD_ARCH}",
  "creation_date": ${CREATION_EPOCH},
  "properties": {
    "architecture": "${LXD_ARCH}",
    "description": "Alpine Linux ${RELEASE} (with OpenSSH, ${CREATION_HUMAN})",
    "name": "alpine-${RELEASE}-${CREATION_HUMAN}",
    "os": "alpine",
    "release": "${RELEASE}",
    "variant": "default"
  },
  "templates": {
    "/etc/hostname": { "template": "hostname.tpl", "when": ["create"] },
    "/etc/hosts":    { "template": "hosts.tpl",    "when": ["create"] }
  }
}
EOF

mkdir -p "$WORKDIR/templates"
cat > "$WORKDIR/templates/hostname.tpl" <<'EOF'
{{ container.name }}
EOF
cat > "$WORKDIR/templates/hosts.tpl" <<'EOF'
127.0.0.1   localhost
127.0.1.1   {{ container.name }}

::1         ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# ===== 打包为 LXD 两段式镜像 =====
STAMP="$(date +%Y%m%d_%H%M)"
META_TAR="metadata-${RELEASE}-${APK_ARCH}-${STAMP}.tar.xz"
ROOT_TAR="rootfs-${RELEASE}-${APK_ARCH}-${STAMP}.tar.xz"

echo ">> 打包镜像：$META_TAR + $ROOT_TAR"
tar -C "$WORKDIR" -cJf "$META_TAR" --numeric-owner metadata.yaml templates
tar -C "$ROOTFS"  -cJf "$ROOT_TAR"  --numeric-owner .

# 收尾清理
rm -f "$WORKDIR/metadata.yaml"
rm -rf "$WORKDIR/templates"
rm -rf "$ROOTFS"

echo
echo "完成 ✅ 生成："
echo "  $META_TAR"
echo "  $ROOT_TAR"
echo
echo "导入到 LXD："
echo "  lxc image import $META_TAR $ROOT_TAR --alias alpine-${RELEASE}-ssh"
echo "启动测试："
echo "  lxc launch alpine-${RELEASE}-ssh a${RELEASE//./}"
echo "  lxc exec a${RELEASE//./} -- /bin/sh"
echo
echo "SSH 登录提示："
echo "  1) 查看容器 IP: lxc list"
echo "  2) 从宿主机：ssh -p ${SSH_PORT} root@<容器IP>   (密码：你在脚本里设定的 ROOT_PASSWORD)"
