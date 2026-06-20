# Traffic Mirroring (SPAN) — Firewall-Level

Goal: deliver a **copy of network traffic to the SIEM sensor** (`10.10.99.10`,
monitor NIC on VLAN 99) so Zeek/Suricata can analyze it in later phases.

There are two places to mirror. Use **(A) Proxmox bridge mirroring** as the
primary method (it captures *all* east-west VM traffic). Use **(B) pfSense**
mirroring if you want a firewall-anchored copy of routed/WAN traffic. They can
coexist.

This file documents **(B) pfSense**. See `../proxmox/bridge-mirror.md` for (A).

---

## B1. Live mirror to the sensor with `tcpdump` + `tcpreplay` (simple)

pfSense/FreeBSD has no native GUI SPAN, but you can stream a capture from any
firewall interface to the sensor. Run on the pfSense shell (Diagnostics →
Command Prompt, or SSH):

```sh
# Capture everything crossing the Victim interface (vtnet1.30) and pipe a copy
# to the sensor's monitor NIC over the monitoring VLAN.
# (For a true tap, prefer method A — this is a pragmatic firewall-side option.)
tcpdump -i vtnet1.30 -w - -U not host 10.10.99.10 | \
  ssh sensor@10.10.99.10 "tcpreplay -i mon0 -"
```

> This is best for short, targeted captures during an exercise. For continuous
> monitoring, method A (hypervisor SPAN) is the right tool.

## B2. On-box packet capture for ad-hoc analysis

**Diagnostics → Packet Capture** (GUI) — select interface, set a filter, capture,
then download the `.pcap` for offline analysis in the SIEM/Wireshark. Good for
validating that the firewall policy behaves as designed.

## B3. Firewall log feed (pflog) → SIEM

Enable logging on the **default-deny** rules (already set in `rules/*.md`). Ship
`filterlog` entries to the SIEM:

- **Status → System Logs → Settings → Remote Logging**
- Remote log server: `10.10.10.10:514` (SIEM syslog, on the MGMT plane)
- Select **Firewall events**.

This gives the SIEM allow/deny metadata (the "who tried to talk to whom") that
complements full-packet capture from the SPAN.

---

## Verifying the feed

On the sensor:
```sh
sudo tcpdump -ni mon0 -c 20        # should show mirrored frames, mixed src/dst
```
If you see only broadcast/ARP, the mirror isn't reaching the sensor — re-check
the SPAN target port and that the monitor NIC is in promiscuous mode.
