# ─── Congestion control: foundation of everything ───────────────────────
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# ─── Socket buffers (important for both TCP and QUIC/UDP) ───────
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 2097152
net.ipv4.tcp_rmem = 4096 131072 67108864
net.ipv4.tcp_wmem = 4096 131072 67108864
net.ipv4.tcp_mem = 25600 51200 102400
net.ipv4.udp_mem = 25600 51200 102400

# ─── Queues and backlogs ──────────────────────────────────────
net.core.netdev_max_backlog = 10240
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 10240

# ─── TCP behavior for long-lived tunnels ────────────────
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

# ─── File limits (needed for nginx + panel + self-host) ──
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
