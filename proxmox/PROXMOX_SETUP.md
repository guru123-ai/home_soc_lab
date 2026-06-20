# Proxmox VE Setup Guide — HomeSOClab (Layer 1)

Proxmox VE is the Type-1 hypervisor foundation for the lab. This guide covers a
production-quality install, VLAN-aware networking, and storage layout.

> Tested against **Proxmox VE 8.x**. Commands run as `root` on the node shell.

---

## 1. Hardware baseline

| Resource | Minimum | Recommended | Why |
|----------|---------|-------------|-----|
| CPU | 4 cores w/ VT-x/AMD-V | 8+ cores | Nested virt + several guests |
| RAM | 16 GB | 32–64 GB | pfSense + Kali + 2 victims + SIEM |
| Disk | 256 GB SSD | 1 TB NVMe + HDD | VM disks need fast IO; HDD for backups |
| NIC | 1 × 1GbE | 2 × 1GbE | Separate mgmt uplink from lab trunk (optional) |

Enable **virtualization extensions** in BIOS (VT-x/VT-d or AMD-V/IOMMU). Nested
virtualization is helpful if guests themselves run containers/VMs.

---

## 2. Install & first-boot hardening

1. Install Proxmox VE from ISO; set the management IP to **`10.10.10.2/24`**,
   gateway `10.10.10.1`, DNS `10.10.10.1`.
2. Remove the enterprise repo, add the no-subscription repo, and update:
   ```sh
   sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list
   echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
     > /etc/apt/sources.list.d/pve-no-sub.list
   apt update && apt -y dist-upgrade
   ```
3. Create a non-root admin user + API token (see `../scripts/lib/common.sh` and
   "API token" below). Avoid using `root@pam` for automation in production.
4. Restrict the web UI: keep it on the **Management VLAN only** (it binds to the
   node IP `10.10.10.2:8006`). Do not expose 8006 to WAN/home LAN.

### Create an API token for automation (least privilege)
```sh
# Role with just what the provisioning scripts need
pveum role add ProvisionVMs -privs \
  "VM.Allocate VM.Clone VM.Config.Disk VM.Config.CPU VM.Config.Memory \
   VM.Config.Network VM.Config.Options VM.PowerMgmt Datastore.AllocateSpace \
   Datastore.Audit Sys.Audit VM.Audit SDN.Use"
pveum user add svc-provision@pve
pveum aclmod / -user svc-provision@pve -role ProvisionVMs
pveum user token add svc-provision@pve automation --privsep 0
# -> copy the token secret into config/secrets.env (PVE_TOKEN_ID / PVE_TOKEN_SECRET)
```

---

## 3. VLAN-aware bridge networking

The lab uses a **single VLAN-aware Linux bridge (`vmbr1`)** that carries all lab
VLANs as 802.1Q tags over one physical NIC. pfSense terminates the VLANs; VMs
just get assigned a VLAN tag on their vNIC. This is the cleanest, most scalable
pattern (no per-VLAN bridge sprawl).

- `vmbr0` → management bridge (optional, ties Proxmox mgmt to VLAN 10 / home).
- `vmbr1` → **VLAN-aware** trunk bridge for all lab VLANs (10/20/30/99).

See `network-interfaces.conf` in this directory for the full
`/etc/network/interfaces` definition. Apply it with:
```sh
cp network-interfaces.conf /etc/network/interfaces   # review first!
ifreload -a                                           # ifupdown2 (PVE default)
```

Verify:
```sh
ip -d link show vmbr1 | grep vlan_filtering    # vlan_filtering 1
bridge vlan show                               # shows tagged VLANs per port
```

### Assigning VLANs to a VM NIC
With a VLAN-aware bridge, set the **VLAN tag** field on the guest's network
device. CLI example (Kali on the Attacker VLAN):
```sh
qm set <vmid> -net0 virtio,bridge=vmbr1,tag=20
```
The provisioning scripts do this automatically from `config/lab.env`.

---

## 4. Storage configuration

| Storage ID | Type | Backing | Use |
|------------|------|---------|-----|
| `local` | dir | `/var/lib/vz` | ISOs, templates, snippets (cloud-init) |
| `local-lvm` | lvmthin | NVMe | **VM disks** (thin-provisioned, fast) |
| `backup` | dir | HDD/NAS | `vzdump` backups + retention |

Recommendations and rationale:
- **Thin LVM or ZFS for VM disks.** Thin provisioning lets you over-commit lab
  disks (most are mostly-empty). ZFS adds snapshots+compression+checksums at a
  RAM cost (~1 GB/TB). On a single SSD, `local-lvm` (thin) is simplest.
- **Separate backup target** (HDD or NAS via NFS). Never back up onto the same
  device as the VM disks. Configure scheduled `vzdump` (Datacenter → Backup).
- **Enable discard/TRIM** on VM disks (`discard=on`, SSD emptying) to reclaim
  thin space when guests delete files.
- **Snapshots before exercises.** Snapshot victim/attacker VMs before detonating
  malware so you can revert to a clean baseline in seconds:
  ```sh
  qm snapshot <vmid> clean-baseline --description "pre-exercise clean state"
  qm rollback <vmid> clean-baseline
  ```
- **Enable the `snippets` content type** on `local` so cloud-init user-data can
  be stored there (used by the provisioning scripts):
  ```sh
  pvesm set local --content iso,vztmpl,backup,snippets
  ```

---

## 5. ISO / template management

Place install media in `local` (`/var/lib/vz/template/iso/`):
```sh
cd /var/lib/vz/template/iso/
# pfSense / OPNsense / Kali ISOs (download from official mirrors)
# Example (verify checksums!):
# wget https://cdimage.kali.org/.../kali-linux-2024.x-installer-amd64.iso
```
For cloud-init Linux templates (recommended for endpoints), see
`../scripts/provision-endpoint.sh`, which builds a reusable template from a
cloud image.

---

## 6. Post-setup validation checklist

- [ ] Web UI reachable only from VLAN 10 (`https://10.10.10.2:8006`).
- [ ] `vmbr1` shows `vlan_filtering 1`.
- [ ] `bridge vlan show` lists VLANs 10/20/30/99 on the trunk.
- [ ] API token works: `curl` test in `../scripts/lib/common.sh`.
- [ ] `local-lvm` has free space; `backup` storage mounted.
- [ ] pfSense VM boots and hands out DHCP on each VLAN.
