#!/usr/bin/env bash
# =============================================================================
# provision-kali.sh — create the Kali Linux attacker VM on the Attacker VLAN
# =============================================================================
# Single NIC on vmbr1 tagged to the Attacker VLAN (20). Boots from the Kali
# installer ISO. Internet + Victim access is governed by the pfSense rules
# (see pfsense/rules/attacker.rules.md): Kali can reach the internet and the
# Victim zone, but NOT the Management/Monitoring planes or the home LAN.
#
# Usage:
#   SOCLAB_MODE=cli ./provision-kali.sh [kali.iso]
#   DRY_RUN=1 ./provision-kali.sh
# =============================================================================
. "$(dirname "$0")/lib/common.sh"
load_config
# shellcheck disable=SC1090
. "$(dirname "$0")/templates/vm-resources.env"
check_prereqs

NAME="kali-attacker"
ISO="${1:-kali-linux-installer-amd64.iso}"

main() {
  if vm_exists "$NAME"; then warn "$NAME already exists — skipping."; exit 0; fi
  local vmid; vmid="$(next_vmid)"
  log "Provisioning ${NAME} as VMID ${vmid} on VLAN ${KALI_VLAN} (mode=${SOCLAB_MODE})"

  if [ "${SOCLAB_MODE}" = "cli" ]; then
    run qm create "$vmid" \
      --name "$NAME" \
      --ostype l26 \
      --cores "$KALI_CORES" --memory "$KALI_MEM" \
      --cpu host \
      --scsihw virtio-scsi-single \
      --scsi0 "${PVE_STORAGE_VM}:${KALI_DISK},discard=on,ssd=1" \
      --net0 "virtio,bridge=${PVE_BRIDGE},tag=${KALI_VLAN}" \
      --ide2 "${PVE_STORAGE_ISO}:iso/${ISO},media=cdrom" \
      --boot order='ide2;scsi0' \
      --vga std \
      --onboot 0 \
      --description "HomeSOClab Kali attacker. VLAN ${KALI_VLAN}. Internet+Victim only (see firewall rules)."
    ok "Created ${NAME} (VMID ${vmid}) on Attacker VLAN ${KALI_VLAN}."
  else
    run pve_api POST "/nodes/${PVE_NODE}/qemu" \
      --data-urlencode "vmid=${vmid}" \
      --data-urlencode "name=${NAME}" \
      --data-urlencode "ostype=l26" \
      --data-urlencode "cores=${KALI_CORES}" \
      --data-urlencode "memory=${KALI_MEM}" \
      --data-urlencode "cpu=host" \
      --data-urlencode "scsihw=virtio-scsi-single" \
      --data-urlencode "scsi0=${PVE_STORAGE_VM}:${KALI_DISK},discard=on,ssd=1" \
      --data-urlencode "net0=virtio,bridge=${PVE_BRIDGE},tag=${KALI_VLAN}" \
      --data-urlencode "ide2=${PVE_STORAGE_ISO}:iso/${ISO},media=cdrom" \
      --data-urlencode "boot=order=ide2;scsi0" \
      --data-urlencode "onboot=0"
    ok "Created ${NAME} (VMID ${vmid}) via API."
  fi

  cat <<EOF

Next steps:
  1) qm start ${vmid}  &&  open the console to run the Kali installer.
  2) After install, detach ISO:  qm set ${vmid} -ide2 none,media=cdrom
  3) Confirm DHCP lease in 10.10.20.100-199 and verify policy:
       - can reach internet              (curl https://example.com)
       - can reach victim 10.10.30.x     (ping)
       - CANNOT reach 10.10.10.x / 192.168.1.x  (should time out)
  4) Optionally set a static DHCP reservation (pfsense/dhcp.md) at 10.10.20.50.
EOF
}
main "$@"
