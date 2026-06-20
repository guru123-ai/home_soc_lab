#!/usr/bin/env bash
# =============================================================================
# provision-pfsense.sh — create the pfSense/OPNsense router-firewall VM
# =============================================================================
# Creates a VM with TWO NICs:
#   net0 -> vmbr0  (WAN, faces the home router; DHCP)
#   net1 -> vmbr1  (LAN trunk; VLAN-aware, carries VLANs 10/20/30/99)
# After boot, assign interfaces in the pfSense console, then import
# pfsense/config.xml (Diagnostics -> Backup & Restore).
#
# Usage:
#   SOCLAB_MODE=cli ./provision-pfsense.sh                 # run ON the node
#   SOCLAB_MODE=api ./provision-pfsense.sh                 # run remotely
#   DRY_RUN=1 ./provision-pfsense.sh                       # preview only
# =============================================================================
. "$(dirname "$0")/lib/common.sh"
load_config
# shellcheck disable=SC1090
. "$(dirname "$0")/templates/vm-resources.env"
check_prereqs

NAME="pfsense-fw01"
ISO="${1:-pfSense.iso}"          # ISO filename present on PVE_STORAGE_ISO
WAN_BRIDGE="vmbr0"

main() {
  if vm_exists "$NAME"; then warn "$NAME already exists — skipping."; exit 0; fi
  local vmid; vmid="$(next_vmid)"
  log "Provisioning ${NAME} as VMID ${vmid} (mode=${SOCLAB_MODE})"

  if [ "${SOCLAB_MODE}" = "cli" ]; then
    run qm create "$vmid" \
      --name "$NAME" \
      --ostype other \
      --cores "$PFSENSE_CORES" --memory "$PFSENSE_MEM" \
      --cpu host \
      --scsihw virtio-scsi-single \
      --scsi0 "${PVE_STORAGE_VM}:${PFSENSE_DISK},discard=on,ssd=1" \
      --net0 "virtio,bridge=${WAN_BRIDGE}" \
      --net1 "virtio,bridge=${PVE_BRIDGE}" \
      --ide2 "${PVE_STORAGE_ISO}:iso/${ISO},media=cdrom" \
      --boot order=ide2 \
      --onboot 1 \
      --description "HomeSOClab firewall. net0=WAN(home), net1=trunk(all VLANs). Import pfsense/config.xml after install."
    # net1 is a VLAN-AWARE trunk: do NOT set a tag here; pfSense tags internally.
    ok "Created ${NAME} (VMID ${vmid}). Start it and run the installer."
  else
    # ---- API mode ----
    run pve_api POST "/nodes/${PVE_NODE}/qemu" \
      --data-urlencode "vmid=${vmid}" \
      --data-urlencode "name=${NAME}" \
      --data-urlencode "ostype=other" \
      --data-urlencode "cores=${PFSENSE_CORES}" \
      --data-urlencode "memory=${PFSENSE_MEM}" \
      --data-urlencode "cpu=host" \
      --data-urlencode "scsihw=virtio-scsi-single" \
      --data-urlencode "scsi0=${PVE_STORAGE_VM}:${PFSENSE_DISK},discard=on,ssd=1" \
      --data-urlencode "net0=virtio,bridge=${WAN_BRIDGE}" \
      --data-urlencode "net1=virtio,bridge=${PVE_BRIDGE}" \
      --data-urlencode "ide2=${PVE_STORAGE_ISO}:iso/${ISO},media=cdrom" \
      --data-urlencode "boot=order=ide2" \
      --data-urlencode "onboot=1"
    ok "Created ${NAME} (VMID ${vmid}) via API."
  fi

  cat <<EOF

Next steps:
  1) Start the VM:        qm start ${vmid}
  2) Open console:        Proxmox UI -> ${NAME} -> Console
  3) Install pfSense to disk, then at the assign-interfaces prompt:
        WAN  = vtnet0   (net0 / ${WAN_BRIDGE})
        LAN  = vtnet1   (net1 / ${PVE_BRIDGE}, trunk)
     Create VLANs 10/20/30/99 on vtnet1 when prompted (or via GUI later).
  4) Detach the ISO:      qm set ${vmid} -ide2 none,media=cdrom
  5) Import config:       upload pfsense/config.xml via the pfSense GUI.
EOF
}
main "$@"
