#!/usr/bin/env bash
# =============================================================================
# provision-endpoint.sh — provision a victim/endpoint VM (placeholder template)
# =============================================================================
# This is the reusable template for FUTURE endpoint VMs (Layer 3). It supports
# two paths:
#
#   (A) cloud-init clone  — fast, repeatable Linux endpoints from a template.
#       Build the template once with --build-template using a cloud image.
#   (B) ISO install       — for Windows or custom victims, boots from an ISO.
#
# All endpoints land on the Victim VLAN (30) by default: NO internet, no lateral
# movement (enforced by pfSense rules/victim.rules.md).
#
# Usage:
#   # one-time: build a Debian cloud-init template (VMID 9000)
#   ./provision-endpoint.sh --build-template debian-12-generic-amd64.qcow2
#
#   # clone an endpoint from the template
#   ./provision-endpoint.sh --clone victim-linux-01
#
#   # ISO-based endpoint (e.g. Windows)
#   ./provision-endpoint.sh --iso victim-win10-01 windows10.iso win
#
#   DRY_RUN=1 ./provision-endpoint.sh --clone victim-linux-02
# =============================================================================
. "$(dirname "$0")/lib/common.sh"
load_config
# shellcheck disable=SC1090
. "$(dirname "$0")/templates/vm-resources.env"
check_prereqs

TEMPLATE_ID=9000
TEMPLATE_NAME="tmpl-debian12-cloudinit"

usage() {
  grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//' | head -40
  exit "${1:-0}"
}

# --- (A1) Build a reusable cloud-init Linux template -------------------------
build_template() {
  local image="$1"
  [ -n "$image" ] || die "Provide the cloud image filename (in $PVE_STORAGE_ISO or a path)."
  if vm_exists "$TEMPLATE_NAME"; then warn "Template already exists — skipping."; return 0; fi
  [ "${SOCLAB_MODE}" = "cli" ] || die "--build-template requires CLI mode (run on the node)."
  log "Building cloud-init template ${TEMPLATE_NAME} (VMID ${TEMPLATE_ID})"
  run qm create "$TEMPLATE_ID" --name "$TEMPLATE_NAME" --ostype l26 \
      --cores "$ENDPOINT_LINUX_CORES" --memory "$ENDPOINT_LINUX_MEM" \
      --cpu host --scsihw virtio-scsi-single \
      --net0 "virtio,bridge=${PVE_BRIDGE},tag=${ENDPOINT_LINUX_VLAN}"
  run qm importdisk "$TEMPLATE_ID" "$image" "$PVE_STORAGE_VM"
  run qm set "$TEMPLATE_ID" --scsi0 "${PVE_STORAGE_VM}:vm-${TEMPLATE_ID}-disk-0,discard=on,ssd=1"
  run qm set "$TEMPLATE_ID" --ide2 "${PVE_STORAGE_VM}:cloudinit"
  run qm set "$TEMPLATE_ID" --boot 'order=scsi0' --serial0 socket --vga serial0
  run qm set "$TEMPLATE_ID" --ciuser socadmin --sshkeys "${HOME}/.ssh/authorized_keys" 2>/dev/null || true
  run qm template "$TEMPLATE_ID"
  ok "Template ${TEMPLATE_NAME} ready. Clone with: $0 --clone <name>"
}

# --- (A2) Clone an endpoint from the template --------------------------------
clone_endpoint() {
  local name="$1" vlan="${2:-$ENDPOINT_LINUX_VLAN}"
  [ -n "$name" ] || die "Provide a VM name."
  if vm_exists "$name"; then warn "$name already exists — skipping."; exit 0; fi
  local vmid; vmid="$(next_vmid)"
  log "Cloning ${name} (VMID ${vmid}) from ${TEMPLATE_NAME} on VLAN ${vlan}"
  run qm clone "$TEMPLATE_ID" "$vmid" --name "$name" --full 1
  run qm set "$vmid" --net0 "virtio,bridge=${PVE_BRIDGE},tag=${vlan}"
  run qm set "$vmid" --ipconfig0 "ip=dhcp"
  run qm set "$vmid" --description "HomeSOClab endpoint (victim). VLAN ${vlan}. No internet."
  run qm resize "$vmid" scsi0 "${ENDPOINT_LINUX_DISK}G" 2>/dev/null || true
  ok "Cloned ${name} (VMID ${vmid}). Start: qm start ${vmid}"
}

# --- (B) ISO-based endpoint (Windows or custom) ------------------------------
iso_endpoint() {
  local name="$1" iso="$2" kind="${3:-linux}"
  [ -n "$name" ] && [ -n "$iso" ] || die "Usage: --iso <name> <iso> [win|linux]"
  if vm_exists "$name"; then warn "$name already exists — skipping."; exit 0; fi
  local vmid cores mem disk ostype
  vmid="$(next_vmid)"
  if [ "$kind" = "win" ]; then
    cores=$ENDPOINT_WIN_CORES; mem=$ENDPOINT_WIN_MEM; disk=$ENDPOINT_WIN_DISK; ostype=win10
  else
    cores=$ENDPOINT_LINUX_CORES; mem=$ENDPOINT_LINUX_MEM; disk=$ENDPOINT_LINUX_DISK; ostype=l26
  fi
  log "Provisioning ISO endpoint ${name} (VMID ${vmid}, ${kind}) on VLAN ${ENDPOINT_WIN_VLAN}"
  run qm create "$vmid" --name "$name" --ostype "$ostype" \
      --cores "$cores" --memory "$mem" --cpu host \
      --scsihw virtio-scsi-single \
      --scsi0 "${PVE_STORAGE_VM}:${disk},discard=on,ssd=1" \
      --net0 "virtio,bridge=${PVE_BRIDGE},tag=${ENDPOINT_WIN_VLAN}" \
      --ide2 "${PVE_STORAGE_ISO}:iso/${iso},media=cdrom" \
      --boot 'order=ide2;scsi0' --vga std --onboot 0 \
      --description "HomeSOClab endpoint (victim). VLAN ${ENDPOINT_WIN_VLAN}. No internet."
  ok "Created ${name} (VMID ${vmid}). Start and install via console."
}

case "${1:-}" in
  --build-template) shift; build_template "${1:-}";;
  --clone)          shift; clone_endpoint "${1:-}" "${2:-}";;
  --iso)            shift; iso_endpoint "${1:-}" "${2:-}" "${3:-}";;
  -h|--help|"")     usage 0;;
  *)                err "Unknown option: $1"; usage 1;;
esac
