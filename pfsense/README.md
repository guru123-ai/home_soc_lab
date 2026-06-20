# pfSense / OPNsense Configuration — HomeSOClab

This directory contains the firewall configuration for the lab. pfSense and
OPNsense share the same FreeBSD/`pf` lineage; the **rule logic and DHCP/NAT
concepts here apply to both**. The `config.xml` provided is pfSense-formatted
(OPNsense uses a similar but not identical schema — see notes at the bottom).

## Files

| File | Purpose |
|------|---------|
| `config.xml` | Importable pfSense config: interfaces, VLANs, DHCP, NAT, firewall rules |
| `rules/mgmt.rules.md` | Human-readable firewall ruleset for the Management interface |
| `rules/attacker.rules.md` | Ruleset for the Attacker interface |
| `rules/victim.rules.md` | Ruleset for the Victim interface |
| `rules/monitoring.rules.md` | Ruleset for the Monitoring interface |
| `dhcp.md` | DHCP server configuration per VLAN |
| `nat.md` | Outbound NAT (and optional port-forward) policy |
| `port-mirror.md` | Firewall-level traffic mirroring to the SIEM sensor |

## Deployment Methods

### Method A — GUI import (fastest)
1. Stand up pfSense (see `../scripts/provision-pfsense.sh`).
2. Assign interfaces: `WAN = vtnet0`, then the VLAN interfaces on the trunk NIC.
3. **Diagnostics → Backup & Restore → Restore** → upload `config.xml`.
   *(Review/replace the WAN block first if your home LAN isn't `192.168.1.0/24`.)*
4. Reboot; verify each VLAN gets DHCP and the rule matrix behaves.

### Method B — Manual configuration
Recreate the objects following `rules/*.md`, `dhcp.md`, and `nat.md`. This is
the recommended path the first time so you understand each control.

## Interface ↔ VLAN mapping

| pfSense IF | VLAN | Subnet | Role |
|-----------|------|--------|------|
| WAN (`vtnet0`) | untagged | DHCP from home router | Uplink |
| LAN/MGMT (`vtnet1.10`) | 10 | 10.10.10.0/24 | Management |
| OPT1/ATTACKER (`vtnet1.20`) | 20 | 10.10.20.0/24 | Attacker |
| OPT2/VICTIM (`vtnet1.30`) | 30 | 10.10.30.0/24 | Victim |
| OPT3/MONITOR (`vtnet1.99`) | 99 | 10.10.99.0/24 | Monitoring |

## OPNsense notes
- Import via **System → Configuration → Backups** is *not* cross-compatible with
  pfSense XML. Instead, recreate objects from `rules/*.md` (1:1 mapping) or use
  the OPNsense API. VLAN/DHCP/NAT/rule semantics are identical.
- OPNsense uses **Firewall → Aliases** and **Firewall → Rules → [Interface]**
  exactly like pfSense; the `RFC1918`/`HomeLAN` aliases below port directly.
