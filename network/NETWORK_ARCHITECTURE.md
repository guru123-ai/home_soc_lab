# HomeSOClab — Network Architecture (Phase 1, Layer 2)

This document describes the segmented network design for the HomeSOClab. The
design follows a **zero-trust-inspired segmentation model**: every zone is its
own VLAN/L2 domain, and the firewall is the single inter-VLAN router enforcing
an explicit allow-list policy (default deny).

---

## 1. Design Goals & Security Rationale

| Goal | How it is achieved |
|------|--------------------|
| Contain malware/exploits to the lab | Lab VLANs cannot reach the home LAN (`192.168.1.0/24`) |
| Realistic attack path | Attacker VLAN → Victim VLAN allowed; Victim cannot initiate back |
| Prevent victim exfiltration / botnet C2 | Victim VLAN has **no internet** (default-deny WAN) |
| Full packet visibility for detection | Port mirroring (SPAN) copies inter-VLAN traffic to the SIEM sensor |
| Safe administration | Management VLAN is the only plane allowed to reach Proxmox/pfSense/SIEM admin UIs |
| Blast-radius reduction | Default-deny between every pair of zones; only documented flows are permitted |

---

## 2. VLAN / IP Addressing Scheme

| VLAN ID | Zone | Subnet (CIDR) | Gateway (pfSense) | DHCP Pool | Internet | Purpose |
|--------:|------|---------------|-------------------|-----------|:--------:|---------|
| 10 | **Management** | `10.10.10.0/24` | `10.10.10.1` | `.100–.199` | Controlled | Proxmox, pfSense, SIEM UI, analyst WS |
| 20 | **Attacker**   | `10.10.20.0/24` | `10.10.20.1` | `.100–.199` |  Yes | Kali / red-team tooling |
| 30 | **Victim**     | `10.10.30.0/24` | `10.10.30.1` | `.100–.199` |  No  | Vulnerable endpoints / targets |
| 99 | **Monitoring** | `10.10.99.0/24` | `10.10.99.1` | static only |  No  | SPAN sink + SIEM sensor sniff NIC |

### Reserved static addresses (outside DHCP pools)

| Host | IP | VLAN |
|------|----|------|
| pfSense/OPNsense (router) | `10.10.X.1` per VLAN | all |
| Proxmox `pve01` mgmt | `10.10.10.2` | 10 |
| SIEM management UI | `10.10.10.10` | 10 |
| Analyst workstation | `10.10.10.20` | 10 |
| SIEM sensor (mirror sink NIC) | `10.10.99.10` | 99 |

> **Why a separate Monitoring VLAN (99)?** The SIEM sensor's *sniffing* interface
> receives mirrored traffic and must never source traffic onto production zones.
> Its *management* interface lives on VLAN 10 so analysts can reach the dashboard.
> This dual-NIC pattern mirrors how Security Onion / Wazuh are deployed in
> production (a management NIC + a promiscuous monitor NIC).

---

## 3. Topology Diagram

```
                              INTERNET
                                 │
                       ┌─────────┴─────────┐
                       │   Home Router      │   192.168.1.0/24  (UNTRUSTED to lab)
                       │  (existing LAN)    │
                       └─────────┬─────────┘
                                 │ WAN (DHCP)
                                 ▼
            ╔════════════════════════════════════════════════╗
            ║         pfSense / OPNsense  (Firewall)          ║
            ║   - Inter-VLAN router (router-on-a-stick)       ║
            ║   - Default-deny + explicit allow rules         ║
            ║   - DHCP + Unbound DNS per VLAN                 ║
            ║   - NAT (outbound) for MGMT & ATTACKER only     ║
            ╚══╤═════════╤═══════════╤════════════╤═══════════╝
       VLAN10 │  VLAN20 │   VLAN30  │   VLAN99   │   (802.1Q trunk)
        MGMT  │ ATTACKER│   VICTIM  │ MONITORING │
              │         │           │            │
              ▼         ▼           ▼            ▼
        ┌───────────────────────────────────────────────────┐
        │      Proxmox VE host  —  vmbr1 (VLAN-aware)         │
        │   physical trunk NIC enp1s0  ◄──► pfSense vNIC      │
        └──┬──────────┬───────────┬──────────────┬───────────┘
           │          │           │              │
   ┌───────▼──┐  ┌────▼─────┐ ┌───▼──────┐  ┌────▼───────────┐
   │ Proxmox  │  │  Kali    │ │ Victim   │  │ SIEM Sensor    │
   │ mgmt UI  │  │ Attacker │ │ Endpoints│  │ (mon NIC=vlan99│
   │ SIEM UI  │  │ 10.10.20 │ │ 10.10.30 │  │  mgmt NIC=v10) │
   │ Analyst  │  │   .x     │ │   .x     │  │ 10.10.99.10    │
   │ 10.10.10 │  └──────────┘ └──────────┘  └────────────────┘
   │   .x     │       ▲             ▲              ▲
   └──────────┘       │             │              │
                      └── attack ──►│              │
                                    │              │
        Mirrored copies of inter-VLAN traffic ─────┘
        (pfSense pflog/SPAN OR Proxmox bridge mirror → VLAN99)
```

---

## 4. Traffic Flow Matrix (Firewall Policy Summary)


| From   \  To  | MGMT | ATTACKER | VICTIM | MONITORING | Home LAN | Internet |
|-----------------|:----:|:--------:|:------:|:----------:|:--------:|:--------:|
| **MGMT**        |  —   |allowed   |  allowed    |     restricted     |    blocked     |    allowed    |
| **ATTACKER**    |  blocked   |    —     |   allowed   |     blocked      |   blocked     |    allowed    |
| **VICTIM**      |  blocked   |    blocked     |   —    |     blocked      |    blocked     |    blocked     |
| **MONITORING**  |  blocked   |    blocked     |   blocked    |     —      |    blocked     |    blocked     |

Key policy decisions:
- **Management → everything**: admins/SIEM must reach all zones for triage.
- **Attacker → Victim only**: realistic kill-chain; attacker cannot touch the
  admin plane or the home LAN (prevents the lab from becoming a pivot point).
- **Victim → nothing outbound**: blocks C2/exfil; only responds to attacker.
- **Monitoring isolated**: sensor only *receives* mirrored frames; it never
  routes. Its mgmt UI is reached from VLAN10, not from VLAN99.

See `pfsense/rules/` for the concrete rule definitions per interface.

---

## 5. Traffic Mirroring (Network Telemetry Feed)

Phase 1 supports **two complementary mirroring approaches** (see
`pfsense/port-mirror.md` and `proxmox/bridge-mirror.md`):

1. **Proxmox bridge mirroring (recommended, hypervisor-level):** a `tc`-based
   SPAN that copies all frames traversing `vmbr1` to a dedicated mirror port
   connected to the SIEM sensor's monitor NIC (VLAN 99). Captures *all* VM
   traffic including intra-VLAN east-west traffic.

2. **pfSense span/packet capture (firewall-level):** mirrors traffic crossing
   the firewall to a monitor interface. Simpler but only sees inter-VLAN/WAN
   traffic, not intra-VLAN.

Both deliver line-rate copies to `10.10.99.10` where the SIEM sensor runs in
promiscuous mode (Zeek/Suricata) in later phases.
