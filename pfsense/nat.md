# NAT Configuration — HomeSOClab

NAT is configured under **Firewall → NAT** in pfSense/OPNsense.

## 1. Outbound NAT (Source NAT / masquerade)

Switch **Firewall → NAT → Outbound** to **Hybrid Outbound NAT** so we can write
explicit rules while keeping pfSense's automatic ones for the firewall itself.

| # | Interface | Source | Translation | Description |
|---|-----------|--------|-------------|-------------|
| 1 | WAN | `10.10.10.0/24` (MGMT) | WAN address | Management internet egress |
| 2 | WAN | `10.10.20.0/24` (ATTACKER) | WAN address | Attacker tooling egress |

**Deliberately NOT NATed:** the **Victim (30)** and **Monitoring (99)** subnets
have *no* outbound NAT entry. Even if a firewall rule were misconfigured, the
absence of a NAT translation means their traffic cannot be masqueraded onto the
WAN — a defense-in-depth "belt and suspenders" so victims/sensors stay dark.

> **Why hybrid, not manual-only?** Manual mode forces you to recreate every
> system NAT (e.g., for the firewall's own updates). Hybrid keeps those working
> while giving us explicit control over the lab zones.

## 2. Port Forwards (inbound NAT) — optional

Phase 1 needs **no inbound port forwards** (no lab service is exposed to the
home LAN/internet — by design). If, in a later phase, you want to reach the SIEM
dashboard from the home LAN, prefer a controlled jump path instead of a raw port
forward. A documented example (disabled by default) if you must:

| IF | Proto | Ext port | Target | Int port | Note |
|----|-------|----------|--------|----------|------|
| WAN | TCP | 8443 | 10.10.10.10 | 443 | SIEM UI — **disabled**; enable only if required |

> **Security note:** exposing lab management to the home network widens the
> blast radius. Keep inbound NAT empty unless you have a specific, audited need,
> and always pair it with a strict source restriction (your admin host only).

## 3. NAT reflection
Leave **NAT reflection = disabled** (default). The lab has no internal clients
that need to reach internal services via the WAN address.
