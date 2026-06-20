#!/usr/bin/env bash
# =============================================================================
# HomeSOClab - shared shell library for provisioning scripts
# Source this from each script:  . "$(dirname "$0")/lib/common.sh"
# =============================================================================
# Provides: config loading, logging, prerequisite checks, and thin wrappers over
# both the Proxmox CLI (`qm`/`pvesh`, when run ON the node) and the Proxmox REST
# API (via curl, when run remotely). Set SOCLAB_MODE=cli|api (default: cli).
# =============================================================================

set -euo pipefail

# ---- Resolve repo paths -----------------------------------------------------
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LIB_DIR}/../.." && pwd)"
CONFIG_DIR="${REPO_ROOT}/config"

# ---- Logging ----------------------------------------------------------------
_c_reset='\033[0m'; _c_red='\033[31m'; _c_grn='\033[32m'; _c_yel='\033[33m'; _c_blu='\033[34m'
log()   { printf "${_c_blu}[*]${_c_reset} %s\n" "$*"; }
ok()    { printf "${_c_grn}[+]${_c_reset} %s\n" "$*"; }
warn()  { printf "${_c_yel}[!]${_c_reset} %s\n" "$*" >&2; }
err()   { printf "${_c_red}[x]${_c_reset} %s\n" "$*" >&2; }
die()   { err "$*"; exit 1; }

# ---- Config loading ---------------------------------------------------------
load_config() {
  [ -f "${CONFIG_DIR}/lab.env" ] || die "Missing ${CONFIG_DIR}/lab.env"
  # shellcheck disable=SC1090
  . "${CONFIG_DIR}/lab.env"
  # Secrets are optional for --dry-run but required for real API calls.
  if [ -f "${CONFIG_DIR}/secrets.env" ]; then
    # shellcheck disable=SC1090
    . "${CONFIG_DIR}/secrets.env"
  fi
  : "${SOCLAB_MODE:=cli}"
}

# ---- Prerequisite checks ----------------------------------------------------
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"; }

check_prereqs() {
  if [ "${SOCLAB_MODE}" = "cli" ]; then
    need_cmd qm; need_cmd pvesh
  else
    need_cmd curl; need_cmd jq
    [ -n "${PVE_TOKEN_ID:-}" ] && [ -n "${PVE_TOKEN_SECRET:-}" ] \
      || die "API mode needs PVE_TOKEN_ID/PVE_TOKEN_SECRET in config/secrets.env"
  fi
}

# ---- Proxmox API helper (remote mode) --------------------------------------
# Usage: pve_api GET /nodes/<node>/qemu
pve_api() {
  local method="$1" path="$2"; shift 2
  curl -fsSk -X "${method}" \
    -H "Authorization: PVEAPIToken=${PVE_TOKEN_ID}=${PVE_TOKEN_SECRET}" \
    "${PVE_API_URL}${path}" "$@"
}

# ---- Find next free VMID ----------------------------------------------------
next_vmid() {
  if [ "${SOCLAB_MODE}" = "cli" ]; then
    pvesh get /cluster/nextid
  else
    pve_api GET /cluster/nextid | jq -r '.data'
  fi
}

# ---- Existence check by name ------------------------------------------------
vm_exists() {  # $1 = name
  if [ "${SOCLAB_MODE}" = "cli" ]; then
    qm list | awk 'NR>1{print $2}' | grep -qx "$1"
  else
    pve_api GET "/nodes/${PVE_NODE}/qemu" | jq -e --arg n "$1" \
      '.data[]|select(.name==$n)' >/dev/null 2>&1
  fi
}

# ---- Dry-run aware command runner ------------------------------------------
# Set DRY_RUN=1 to print commands instead of executing them.
run() {
  if [ "${DRY_RUN:-0}" = "1" ]; then
    printf '   would run: %s\n' "$*"
  else
    "$@"
  fi
}
