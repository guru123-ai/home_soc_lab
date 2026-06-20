# Firewall Rules — Attacker Interface (VLAN 20, `10.10.20.0/24`)

The Attacker zone (Kali) needs internet (tool updates, payload hosting, OSINT)
and must be able to attack the Victim zone — but must be **isolated from the
home LAN and the admin/management plane** so a compromised tool cannot pivot.

**Aliases:** `HomeLAN`, `RFC1918`, `LabAdmin` = `10.10.10.0/24, 10.10.99.0/24`.

| # | Action | Proto | Source | Dest | Port | Description |
|---|--------|-------|--------|------|------|-------------|
| 1 | Pass | TCP/UDP | ATTACKER net | ATTACKER address | 53 | DNS resolver |
| 2 | Pass | UDP | ATTACKER net | This firewall | 123 | NTP |
| 3 | **Block** | any | ATTACKER net | `LabAdmin` | any | **No access to MGMT/Monitoring** |
| 4 | **Block** | any | ATTACKER net | `HomeLAN` | any | **No access to home LAN** |
| 5 | Pass | any | ATTACKER net | `10.10.30.0/24` | any | Attacker → Victim (the kill chain) |
| 6 | Pass | any | ATTACKER net | !`RFC1918` | any | Internet egress (tooling) |
| 7 | Block (log) | any | any | any | any | Default deny + log |

> **Security note:** rules 3–4 (blocks) are placed *above* the internet-allow
> (rule 6) so that private/admin destinations are denied before the broad
> internet permit. This guarantees the Kali box can never reach `10.10.10.0/24`,
> `10.10.99.0/24`, or `192.168.1.0/24`, regardless of egress permissions.
>
> The Attacker→Victim allow (rule 5) is intentionally `any/any` to support the
> full range of offensive techniques during exercises.
