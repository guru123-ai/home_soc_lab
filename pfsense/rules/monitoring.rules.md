# Firewall Rules — Monitoring Interface (VLAN 99, `10.10.99.0/24`)

The Monitoring zone exists to receive **mirrored (SPAN) traffic** for the SIEM
sensor. The sensor's monitor NIC sits here in promiscuous mode and should
**never source routed traffic**. This is the most locked-down zone in the lab.

**Aliases:** `RFC1918`.

| # | Action | Proto | Source | Dest | Port | Description |
|---|--------|-------|--------|------|------|-------------|
| 1 | **Block** (log) | any | MONITOR net | any | any | **Sensor monitor NIC is receive-only** |

> **Security note:** the monitor NIC does not even need an IP for raw packet
> capture, but VLAN 99 has a gateway so the interface can be administered if
> needed. We deny *all* traffic sourced from this zone — the sensor must be
> managed via its **second NIC on VLAN 10** (`10.10.10.x`), not from here.
> This enforces the production "management plane vs. capture plane" separation
> and prevents a compromised sensor from using the capture interface to pivot.
>
> Mirrored frames arrive at L2 (they are not routed by pfSense), so no "pass"
> rule is required for the SPAN feed itself — see `../port-mirror.md` and
> `../../proxmox/bridge-mirror.md`.
