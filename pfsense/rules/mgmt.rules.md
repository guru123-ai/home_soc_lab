# Firewall Rules — Management Interface (VLAN 10, `10.10.10.0/24`)

The Management zone is the trusted admin/SIEM plane. It may reach all lab zones
for administration and incident triage, but is still blocked from the home LAN.

**Aliases used** (Firewall → Aliases):
- `HomeLAN` = `192.168.1.0/24`
- `RFC1918` = `10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16`
- `LabNets` = `10.10.10.0/24, 10.10.20.0/24, 10.10.30.0/24, 10.10.99.0/24`

Rules are evaluated **top-down, first match wins**. Default policy = deny.

| # | Action | Proto | Source | Dest | Port | Description |
|---|--------|-------|--------|------|------|-------------|
| 1 | Pass | TCP | MGMT net | This firewall | 443, 22 | Admin access to pfSense GUI/SSH |
| 2 | Pass | TCP/UDP | MGMT net | MGMT address | 53 | DNS (Unbound resolver) |
| 3 | Pass | UDP | MGMT net | This firewall | 123 | NTP |
| 4 | Pass | any | MGMT net | `10.10.20.0/24` | any | Admin → Attacker zone |
| 5 | Pass | any | MGMT net | `10.10.30.0/24` | any | Admin/SIEM → Victim zone (triage) |
| 6 | Pass | TCP | MGMT net | `10.10.99.10` | 443, 22 | Reach SIEM sensor mgmt (if dual-homed) |
| 7 | **Block** | any | MGMT net | `HomeLAN` | any | **No pivot into home LAN** |
| 8 | Pass | any | MGMT net | !`RFC1918` | any | Internet access (controlled) |
| 9 | Block (log) | any | any | any | any | Default deny + log |

> **Security note (rule 7 before rule 8):** the explicit block to `HomeLAN`
> must precede the "allow internet" rule, otherwise `192.168.1.0/24` (being part
> of the broader internet allow when WAN is the home router) could leak. We deny
> the home LAN first, then permit everything that is *not* RFC1918.
