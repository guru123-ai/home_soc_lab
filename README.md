# HomeSOClab — Phase 1: Core Infrastructure Foundation

A production-grade, **infrastructure-as-code** home Security Operations Center
(SOC) lab. Phase 1 builds the bottom of a 6-layer architecture: a Proxmox
hypervisor, a segmented 3-VLAN network enforced by pfSense/OPNsense, traffic
mirroring to a SIEM sensor, and automated VM provisioning.

> **Why this exists:** a safe, isolated environment to detonate malware, run
> red-vs-blue exercises, and develop detections — built with the same patterns
> (segmentation, least privilege, default-deny, telemetry tap points) used in
> enterprise SOCs.

---

## 1. Architecture at a glance

```
Layer 6  Analyst / Reporting        (future phase)
Layer 5  SIEM / Detection           (future phase — sensor sink defined now)
Layer 4  Telemetry Collection       << traffic mirroring delivered in Phase 1 >>
Layer 3  Endpoints (victims/attacker)   << Kali + endpoint templates >>
Layer 2  Network Segmentation       << pfSense + 3 VLANs >>   ◄── PHASE 1
Layer 1  Physical / Hypervisor      << Proxmox VE >>          ◄── PHASE 1
```

**Zones (VLANs):**

| VLAN | Zone | Subnet | Internet | Role |
|-----:|------|--------|:--------:|------|
| 10 | Management | `10.10.10.0/24` | controlled | Proxmox, pfSense, SIEM UI, analyst |
| 20 | Attacker | `10.10.20.0/24` | enabled | Kali / red team |
| 30 | Victim | `10.10.30.0/24` | disabled | vulnerable endpoints |
| 99 | Monitoring | `10.10.99.0/24` | disabled | SIEM sensor SPAN sink |

Full design + diagram: **[`network/NETWORK_ARCHITECTURE.md`](network/NETWORK_ARCHITECTURE.md)**.

---

## 2. Repository layout

```
HomeSOClab/
├── README.md                       # this file
├── config/
│   ├── lab.env                     # single source of truth (topology/IPs)
│   └── secrets.env.example         # API token template (copy -> secrets.env)
├── network/
│   └── NETWORK_ARCHITECTURE.md     # topology, ASCII diagram, IP plan, flow matrix
├── pfsense/
│   ├── README.md                   # how to deploy the firewall config
│   ├── config.xml                  # importable pfSense config (VLANs/DHCP/NAT/rules)
│   ├── dhcp.md  nat.md  port-mirror.md
│   └── rules/                      # per-interface firewall rulesets (mgmt/attacker/victim/monitoring)
├── proxmox/
│   ├── PROXMOX_SETUP.md            # install + hardening + storage guide
│   ├── network-interfaces.conf     # VLAN-aware bridge /etc/network/interfaces
│   └── bridge-mirror.md            # hypervisor-level SPAN to the SIEM sensor
└── scripts/
    ├── deploy-all.sh               # orchestrator
    ├── provision-pfsense.sh        # firewall VM
    ├── provision-kali.sh           # attacker VM
    ├── provision-endpoint.sh       # victim/endpoint template (clone or ISO)
    ├── setup-mirror.sh             # install tc traffic mirror + systemd unit
    ├── lib/common.sh               # shared functions (CLI + REST API modes)
    └── templates/vm-resources.env  # CPU/RAM/disk sizing per role
```

---

## 3. Prerequisites & dependencies

**Hardware:** a host with VT-x/AMD-V, ≥16 GB RAM (32 GB+ recommended), ≥256 GB
SSD, and at least one NIC (two preferred). See `proxmox/PROXMOX_SETUP.md §1`.

**Software / media:**
- Proxmox VE 8.x installed (Layer 1).
- ISOs uploaded to Proxmox `local` storage: pfSense **or** OPNsense, Kali Linux,
  and any endpoint installers (Debian cloud image / Windows ISO).
- For **remote (API) provisioning**: a workstation with `bash`, `curl`, `jq`,
  and a Proxmox API token. For **on-node (CLI) provisioning**: just run the
  scripts on the Proxmox node (uses `qm`/`pvesh`).

**Network:** an upstream home router providing DHCP on the WAN side. The lab
treats the home LAN (`192.168.1.0/24` by default) as untrusted — adjust the
`HomeLAN` alias if yours differs.

---

## 4. Step-by-step deployment

> Warning: Several steps (OS installs, pfSense interface assignment) require console
> interaction and cannot be fully automated. The scripts handle VM creation,
> networking, and the traffic mirror.

### Step 0 — Clone & configure
```sh
git clone <your-fork> HomeSOClab && cd HomeSOClab
# Review/edit the single source of truth:
$EDITOR config/lab.env          # IP plan, node name, storage, bridge
# For API mode only:
cp config/secrets.env.example config/secrets.env && $EDITOR config/secrets.env
```

### Step 1 — Proxmox networking (Layer 1)
```sh
# On the Proxmox node — review first, then apply:
cp proxmox/network-interfaces.conf /etc/network/interfaces
ifreload -a
ip -d link show vmbr1 | grep vlan_filtering    # expect: vlan_filtering 1
```
Storage + hardening details: `proxmox/PROXMOX_SETUP.md`.

### Step 2 — Firewall VM (Layer 2)
```sh
SOCLAB_MODE=cli ./scripts/provision-pfsense.sh pfSense.iso
# Console: install pfSense; assign WAN=vtnet0, LAN/trunk=vtnet1; create VLANs.
# Then import pfsense/config.xml via the pfSense GUI (Backup & Restore).
```
Verify each VLAN gateway answers and DHCP pools hand out leases.

### Step 3 — Attacker & endpoints (Layer 3)
```sh
SOCLAB_MODE=cli ./scripts/provision-kali.sh kali-linux-installer-amd64.iso
# Endpoints (placeholder for future): clone from a cloud-init template…
./scripts/provision-endpoint.sh --build-template debian-12-generic-amd64.qcow2
./scripts/provision-endpoint.sh --clone victim-linux-01
# …or ISO-install (e.g. Windows):
./scripts/provision-endpoint.sh --iso victim-win10-01 windows10.iso win
```
Or run the whole sequence: `DRY_RUN=1 ./scripts/deploy-all.sh` (preview), then
without `DRY_RUN` to execute.

### Step 4 — Traffic mirroring (Layer 4 feed)
Once the SIEM sensor VM exists (dual NIC: mgmt on VLAN 10, monitor on VLAN 99):
```sh
# On the Proxmox node: copy lab traffic to the sensor's monitor tap.
./scripts/setup-mirror.sh install enp2s0 tap<sensorvmid>i1
# Verify on the sensor:  tcpdump -ni <mon> -c 20
```
Background + alternatives: `proxmox/bridge-mirror.md`, `pfsense/port-mirror.md`.

### Step 5 — Validate the security model
Run these from hosts in each zone (expected results in parentheses):

| Test | From | To | Expect |
|------|------|----|--------|
| Internet | Kali (VLAN20) | `1.1.1.1` |  reachable |
| Attack path | Kali | victim `10.10.30.x` |  reachable |
| No pivot | Kali | mgmt `10.10.10.2` |  blocked |
| No home pivot | Kali | `192.168.1.1` |  blocked |
| Victim isolation | Victim (VLAN30) | `1.1.1.1` |  blocked |
| Victim isolation | Victim | mgmt/home |  blocked |
| Admin reach | Mgmt (VLAN10) | all zones |  reachable |
| Mirror feed | sensor `mon` NIC | — | sees mixed src/dst traffic |

If every row matches, Phase 1 is correctly deployed.

---

## 5. Operating notes
- **Snapshot before exercises:** `qm snapshot <vmid> clean-baseline` and
  `qm rollback` to revert detonated victims instantly.
- **Single source of truth:** change IPs/sizing in `config/lab.env` and
  `scripts/templates/vm-resources.env`; keep docs in sync.
- **CLI vs API:** set `SOCLAB_MODE=cli` (on node) or `api` (remote). Use
  `DRY_RUN=1` to preview any script without making changes.
- **VM lifecycle:** services running in lab VMs are not publicly exposed and stop
  when the host is off — by design (isolation).

---

## 6. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| VM gets no DHCP | VLAN tag missing/wrong on vNIC, or DHCP scope off | Check `qm config <id>` `tag=`; verify scope in pfSense (`pfsense/dhcp.md`) |
| All VLANs can talk to each other | `config.xml` not imported / rules in wrong order | Re-import; confirm block-before-allow ordering (`pfsense/rules/*.md`) |
| Kali can reach the home LAN | `HomeLAN` alias wrong, or block rule below allow | Set alias to your real LAN; ensure block rules precede the internet allow |
| Victim still reaches internet | Outbound NAT entry exists for VLAN30 | Remove it — only MGMT/ATTACKER are NATed (`pfsense/nat.md`) |
| `vlan_filtering` not set | Bridge not VLAN-aware | Re-apply `network-interfaces.conf`; `ifreload -a` |
| Sensor sees only broadcasts | Mirror not active / NIC not promiscuous | `./setup-mirror.sh status`; `ip link set <mon> promisc on up` |
| Mirror lost after VM restart | Tap name changed | Bind mirror to a stable uplink (e.g. `enp2s0`) or re-run setup |
| API scripts: 401/403 | Token wrong or under-privileged | Recheck `secrets.env`; grant the `ProvisionVMs` role (`PROXMOX_SETUP.md §2`) |
| `qm: command not found` | Running CLI mode off-node | Use `SOCLAB_MODE=api` from a workstation, or run on the node |

---

## 7. Security design principles applied
- **Default-deny everywhere**, explicit allow-lists per zone.
- **Least privilege:** dedicated API token role, not `root@pam`, for automation.
- **Blast-radius containment:** lab cannot reach the home LAN; victims have no
  egress; attacker cannot touch the admin/monitoring planes.
- **Defense in depth:** firewall rules *and* the absence of NAT both prevent
  victim/monitoring egress.
- **Observability by design:** all DNS funnels through one resolver; denied
  flows are logged; full-packet SPAN feeds the SIEM.
- **Reproducibility:** topology/sizing live in version-controlled config;
  provisioning is scripted and idempotent (skips existing VMs).

## 8. Roadmap (next phases)
- **Phase 2:** SIEM/IDS (Security Onion / Wazuh + Zeek/Suricata) consuming the
  SPAN feed; endpoint agents (Sysmon, auditd) shipping logs.
- **Phase 3:** detection engineering, dashboards, and analyst playbooks (Layers
  5–6).
