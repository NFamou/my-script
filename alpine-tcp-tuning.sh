#!/bin/sh
# alpine-tcp-tuning.sh
# For: Alpine Linux + LXC + 128MB + Proxy Service

CONF_FILE="/etc/sysctl.d/99-tcp-tuning.conf"

echo "[*] Writing TCP tuning config to $CONF_FILE"

cat > "$CONF_FILE" << 'EOF'
# ===============================
# Alpine TCP tuning for LXC proxy
# Memory limit: ~128MB
# ===============================

# ---- TCP socket buffer (safe for low memory) ----
net.ipv4.tcp_rmem = 4096 87380 8388608
net.ipv4.tcp_wmem = 4096 65536 8388608

# ---- Connection lifecycle optimization ----
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1

# ---- TCP Fast Open (client side, safe) ----
net.ipv4.tcp_fastopen = 1
EOF

echo "[*] Ensuring sysctl service is enabled"

# Start sysctl if not running
rc-service sysctl start >/dev/null 2>&1

# Enable sysctl at boot if not already
rc-update add sysctl boot >/dev/null 2>&1

echo "[*] Applying sysctl settings"
sysctl --system 2>/tmp/sysctl-error.log

echo "[*] Checking applied values:"
sysctl net.ipv4.tcp_rmem
sysctl net.ipv4.tcp_wmem
sysctl net.ipv4.tcp_fin_timeout
sysctl net.ipv4.tcp_tw_reuse
sysctl net.ipv4.tcp_fastopen

echo
echo "[*] Done."
echo "[*] Note: net.core.* is intentionally NOT set (blocked in LXC)."
