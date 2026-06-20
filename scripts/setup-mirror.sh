#!/usr/bin/env bash
# =============================================================================
# setup-mirror.sh — install hypervisor-level traffic mirror (SPAN) to the SIEM
# =============================================================================
# Installs a tc-based packet mirror on the Proxmox node that copies frames from
# a SOURCE interface (bridge uplink or a VM tap) to the SIEM sensor's monitor
# NIC tap (DEST). Persists via a systemd unit so it survives reboots.
#
# Run ON the Proxmox node as root.
#
# Usage:
#   ./setup-mirror.sh install <SRC_IF> <DST_IF>     # e.g. enp2s0  tap200i1
#   ./setup-mirror.sh start
#   ./setup-mirror.sh stop
#   ./setup-mirror.sh status
#   DRY_RUN=1 ./setup-mirror.sh install enp2s0 tap200i1
# =============================================================================
. "$(dirname "$0")/lib/common.sh"

SBIN="/usr/local/sbin/soclab-mirror.sh"
UNIT="/etc/systemd/system/soclab-mirror.service"
CONF="/etc/soclab-mirror.conf"

require_root() { [ "$(id -u)" -eq 0 ] || die "Run as root on the Proxmox node."; }

install_mirror() {
  require_root
  local src="$1" dst="$2"
  [ -n "$src" ] && [ -n "$dst" ] || die "Usage: $0 install <SRC_IF> <DST_IF>"
  log "Installing mirror: ${src} -> ${dst}"

  run bash -c "cat > '${CONF}' <<EOF
# HomeSOClab mirror config
SRC_IF=${src}
DST_IF=${dst}
EOF"

  # The runtime worker script (start/stop the tc rules).
  run bash -c "cat > '${SBIN}' <<'EOS'
#!/usr/bin/env bash
set -euo pipefail
. /etc/soclab-mirror.conf
start() {
  ip link set \"\$DST_IF\" promisc on up 2>/dev/null || true
  tc qdisc del dev \"\$SRC_IF\" ingress 2>/dev/null || true
  tc qdisc del dev \"\$SRC_IF\" root    2>/dev/null || true
  tc qdisc add dev \"\$SRC_IF\" handle ffff: ingress
  tc filter add dev \"\$SRC_IF\" parent ffff: protocol all u32 match u8 0 0 \
     action mirred egress mirror dev \"\$DST_IF\"
  tc qdisc add dev \"\$SRC_IF\" handle 1: root prio
  tc filter add dev \"\$SRC_IF\" parent 1: protocol all u32 match u8 0 0 \
     action mirred egress mirror dev \"\$DST_IF\"
  echo \"mirror active: \$SRC_IF -> \$DST_IF\"
}
stop() {
  tc qdisc del dev \"\$SRC_IF\" ingress 2>/dev/null || true
  tc qdisc del dev \"\$SRC_IF\" root    2>/dev/null || true
  echo \"mirror removed from \$SRC_IF\"
}
status() {
  echo '--- ingress ---'; tc -s filter show dev \"\$SRC_IF\" parent ffff: 2>/dev/null || true
  echo '--- egress  ---'; tc -s filter show dev \"\$SRC_IF\" parent 1:    2>/dev/null || true
}
case \"\${1:-}\" in start) start;; stop) stop;; status) status;; *) echo 'usage: start|stop|status'; exit 1;; esac
EOS"
  run chmod +x "${SBIN}"

  run bash -c "cat > '${UNIT}' <<EOF
[Unit]
Description=HomeSOClab tc traffic mirror to SIEM sensor
After=network-online.target pve-guests.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${SBIN} start
ExecStop=${SBIN} stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF"

  run systemctl daemon-reload
  run systemctl enable --now soclab-mirror.service
  ok "Mirror installed and enabled. Verify on the sensor: tcpdump -ni <mon> -c 20"
}

case "${1:-}" in
  install) shift; install_mirror "${1:-}" "${2:-}";;
  start)   require_root; "${SBIN}" start;;
  stop)    require_root; "${SBIN}" stop;;
  status)  require_root; "${SBIN}" status;;
  *) echo "usage: $0 {install <SRC_IF> <DST_IF>|start|stop|status}"; exit 1;;
esac
