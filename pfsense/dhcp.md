# DHCP Configuration — HomeSOClab

Each routed VLAN runs its own DHCP scope on pfSense (**Services → DHCP Server →
[Interface]**). The Monitoring VLAN intentionally has **no DHCP** (the sensor
uses static addressing; its capture NIC needs no IP at all).

## Per-VLAN scopes

| Interface | Subnet | Pool | Gateway | DNS | Domain |
|-----------|--------|------|---------|-----|--------|
| MGMT (10) | 10.10.10.0/24 | 10.10.10.100 – .199 | 10.10.10.1 | 10.10.10.1 | mgmt.soclab.local |
| ATTACKER (20) | 10.10.20.0/24 | 10.10.20.100 – .199 | 10.10.20.1 | 10.10.20.1 | atk.soclab.local |
| VICTIM (30) | 10.10.30.0/24 | 10.10.30.100 – .199 | 10.10.30.1 | 10.10.30.1 | vic.soclab.local |
| MONITORING (99) | 10.10.99.0/24 | — (disabled) | — | — | — |

## Settings rationale

- **Pools start at .100**: leaves `.1–.99` for static infra (gateway, SIEM,
  analyst WS, sensor) so reserved services never collide with dynamic leases.
- **DNS = the VLAN gateway**: clients resolve via pfSense Unbound. This funnels
  all DNS through one observable choke point (valuable telemetry) and lets the
  Victim zone resolve names without any internet path.
- **Lease time**: default 7200s (2h). Short enough that lab rebuilds reclaim
  addresses quickly; long enough to avoid churn during exercises.
- **NTP option (042)**: hand out `10.10.X.1` so all hosts share the firewall's
  clock — essential for correlating timestamps across SIEM logs.

## Static DHCP mappings (reservations)

Add MAC reservations for repeatable lab hosts so detections/playbooks can rely
on stable IPs (**DHCP Server → [Interface] → DHCP Static Mappings**):

| Host | VLAN | Reserved IP | Notes |
|------|------|-------------|-------|
| SIEM mgmt UI | 10 | 10.10.10.10 | also set static in guest |
| Analyst WS | 10 | 10.10.10.20 | |
| Kali attacker | 20 | 10.10.20.50 | stable C2 listener IP |
| Victim-Win10 | 30 | 10.10.30.50 | primary detonation target |

> The corresponding values live in `config/lab.env`. Keep them in sync.
