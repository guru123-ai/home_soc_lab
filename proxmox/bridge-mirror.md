# Traffic Mirroring (SPAN) — Hypervisor-Level (primary method)

This is the **recommended** mirroring approach. It copies frames at the Proxmox
bridge using Linux `tc` (traffic control) mirroring (`mirred`), delivering a
copy of all VM traffic to the SIEM sensor's monitor NIC — including east-west
(intra-VLAN) traffic the firewall never sees.

## Concept

```
   VM vNICs (tapXi)  ──► vmbr1 (VLAN-aware) ──► normal forwarding
        │
        └── tc ingress/egress filter with action mirred ──► sensor tap (mon NIC)
```

We attach a `tc` filter to each VM tap interface (or to the bridge uplink) that
**mirrors** every packet to the tap interface of the SIEM sensor's monitor NIC
(on VLAN 99 / `vmbr9`).

## Setup

Install the helper and run it on the Proxmox node. The script
`../scripts/setup-mirror.sh` automates the steps below; manual reference:

```sh
# Identify interfaces:
#   SRC  = the bridge or VM tap to mirror (e.g. the pfSense trunk tap, or vmbr1)
#   DST  = the tap of the SIEM sensor's monitor NIC (e.g. tap<vmid>i1)
SRC=fwln1            # example source (firewall LAN-side veth) or a tapXi
DST=tap200i1         # SIEM sensor monitor NIC tap

# 1) Clear any existing qdisc on the source
tc qdisc del dev "$SRC" ingress 2>/dev/null || true
tc qdisc del dev "$SRC" root    2>/dev/null || true

# 2) Add ingress qdisc and mirror inbound packets to DST
tc qdisc add dev "$SRC" handle ffff: ingress
tc filter add dev "$SRC" parent ffff: protocol all u32 match u8 0 0 \
    action mirred egress mirror dev "$DST"

# 3) Mirror outbound packets too (egress) via a prio qdisc
tc qdisc add dev "$SRC" handle 1: root prio
tc filter add dev "$SRC" parent 1: protocol all u32 match u8 0 0 \
    action mirred egress mirror dev "$DST"
```

> `match u8 0 0` matches every packet (mask 0). `mirror` copies (vs. `redirect`
> which would steal) the frame, so normal forwarding is unaffected.

## Make it persistent

`tc` rules are runtime-only. Persist via a systemd unit (the setup script
installs `soclab-mirror.service`):

```ini
# /etc/systemd/system/soclab-mirror.service
[Unit]
Description=HomeSOClab tc traffic mirror to SIEM sensor
After=network-online.target pve-guests.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/soclab-mirror.sh start
ExecStop=/usr/local/sbin/soclab-mirror.sh stop
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
```

## Caveats & tips

- **Tap names change** when VMs restart. Bind the mirror to a stable source such
  as the bridge uplink (`enp2s0`) or re-run the setup via a hookscript on VM
  start. The setup script supports resolving taps from a VMID.
- **Promiscuous mode**: ensure the sensor's monitor NIC is up and promiscuous:
  `ip link set mon0 promisc on up`.
- **Performance**: mirroring doubles traffic on the destination path. Fine for a
  home lab; for heavy loads pin the sensor to its own cores.
- **Verify**: on the sensor, `tcpdump -ni mon0` should show varied src/dst pairs
  (not just broadcasts).
