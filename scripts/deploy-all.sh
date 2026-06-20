#!/usr/bin/env bash
# =============================================================================
# deploy-all.sh — orchestrate Phase 1 VM provisioning
# =============================================================================
# Convenience wrapper that provisions the core Phase 1 VMs in order:
#   1) pfSense firewall   2) Kali attacker   3) a sample Linux victim endpoint
#
# Prerequisites: Proxmox networking applied (proxmox/network-interfaces.conf),
# ISOs uploaded to PVE_STORAGE_ISO, and config/lab.env reviewed.
#
# Usage:
#   SOCLAB_MODE=cli ./deploy-all.sh
#   DRY_RUN=1 ./deploy-all.sh        # preview the whole plan, change nothing
# =============================================================================
. "$(dirname "$0")/lib/common.sh"
load_config
HERE="$(cd "$(dirname "$0")" && pwd)"

log "HomeSOClab Phase 1 deployment (mode=${SOCLAB_MODE}, dry_run=${DRY_RUN:-0})"
echo

log "Step 1/3 — pfSense firewall"
"${HERE}/provision-pfsense.sh" || die "pfSense provisioning failed"
echo
log "Step 2/3 — Kali attacker"
"${HERE}/provision-kali.sh" || die "Kali provisioning failed"
echo
log "Step 3/3 — sample Linux victim endpoint"
"${HERE}/provision-endpoint.sh" --iso victim-linux-01 debian-netinst.iso linux \
  || warn "Endpoint provisioning skipped/failed (provide a valid ISO or use --clone)"
echo
ok "Phase 1 VM provisioning complete."
cat <<EOF

Remember the manual steps that cannot be automated:
  * Install each OS via console, then detach ISOs.
  * Import pfsense/config.xml after the pfSense interface assignment.
  * Install the traffic mirror once the SIEM sensor VM exists:
      ./setup-mirror.sh install <SRC_IF> <SENSOR_MON_TAP>
  * Run the validation checks in README.md (rule matrix + DHCP + mirror feed).
EOF
