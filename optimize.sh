#!/bin/bash
# optimize.sh — net tuning (BBR + buffers + self-host limits)
set -e
CONF="/etc/sysctl.d/99-vpn.conf"

# 1. Drop our settings as a separate single source-of-truth file
cat > "$CONF" << 'EOF'
# 99-vpn.conf — custom network tuning (single source of truth)
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 2097152
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.udp_mem = 25600 51200 102400
net.core.netdev_max_backlog = 10240
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 10240
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_notsent_lowat = 131072
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
EOF
# 2. Clean up any of our keys that the installer script may have
#    appended to /etc/sysctl.conf — so it doesn't override our file.
#    We take key names from our own file and strip them from sysctl.conf.
if [ -f /etc/sysctl.conf ]; then
    cp /etc/sysctl.conf /etc/sysctl.conf.bak.$(date +%s)
    grep -oP '^\s*\K[a-z0-9._]+(?=\s*=)' "$CONF" | while read -r key; do
        esc=$(echo "$key" | sed 's/\./\\./g')
        sed -i "/^\s*${esc}\s*=/d" /etc/sysctl.conf
    done
fi
# 3. Reapply everything. Now sysctl.conf is empty for our keys,
#    99-vpn.conf is applied last — our values win.
sysctl --system >/dev/null 2>&1
# 4. Show the result for self-check
echo
echo "  Optimization applied. Verification:"
echo -n "  congestion control: "; sysctl -n net.ipv4.tcp_congestion_control
echo -n "  qdisc:              "; sysctl -n net.core.default_qdisc
echo -n "  rmem_max:           "; sysctl -n net.core.rmem_max
echo
