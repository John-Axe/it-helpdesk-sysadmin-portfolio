# SOP — Disk / LVM expansion procedure

> Lab/practice SOP for Ubuntu 22.04 LTS servers using LVM on top of a
> hypervisor-provisioned virtual disk. Not a real employer's procedure.

## Scope

Expanding a filesystem that's running low on space, on a host using LVM
(logical volume on top of a volume group on top of one or more physical
volumes) — covering both the common case (growing the underlying virtual
disk, since it's a VM) and the case where a volume group is genuinely out
of space and a new disk must be added.

## Before starting — confirm this is actually the right fix

Not every "disk full" or "running low" situation should be solved by
growing the volume — check whether the growth is from legitimate,
expected data growth (fine, proceed) or from something that should be
cleaned up instead (a runaway log, an old kernel package backlog, a
forgotten large file) per
`tickets/linux/TICKET-001-var-log-filling-disk.md`'s pattern. Expanding a
volume to accommodate a leak just delays the same problem at a larger
scale.

## Part A — Growing an LV when the VG has free space available

The straightforward case: the volume group already has unallocated
space (common on a VM where the underlying virtual disk has headroom the
VG hasn't fully claimed yet, or a prior LV was intentionally
under-allocated).

### 1. Confirm free space exists in the VG

```bash
sudo vgs
```

```
  VG      #PV #LV #SN Attr   VSize   VFree
  vg_data   1   2   0 wz--n- 100.00g  20.00g
```

`VFree` shows 20GB available to allocate.

### 2. Extend the logical volume

```bash
sudo lvextend -L +15G /dev/vg_data/lv_appdata
```

Or to use *all* remaining free space rather than a specific amount:

```bash
sudo lvextend -l +100%FREE /dev/vg_data/lv_appdata
```

### 3. Grow the filesystem to match the new LV size

`lvextend` resizes the block device, not the filesystem on top of it —
this step is required and easy to forget:

```bash
# ext4:
sudo resize2fs /dev/vg_data/lv_appdata

# xfs (must be mounted; xfs_growfs targets the mount point, not the device):
sudo xfs_growfs /mnt/appdata
```

### 4. Verify

```bash
df -h /mnt/appdata
```

Confirm the new size reflects, and confirm the application/service using
the volume is healthy post-resize (this operation is online/non-disruptive
for both ext4 and xfs when growing, but verify anyway).

## Part B — Growing the VG itself first (VM disk was expanded, but VG doesn't see it yet)

Use when `vgs` shows no free space and the underlying virtual disk has
already been expanded in the hypervisor, but the VG hasn't picked it up.

### 1. Confirm the OS sees the larger disk

```bash
lsblk
```

Compare the reported disk size against what was configured in the
hypervisor. If it doesn't match, rescan the SCSI bus without a reboot:

```bash
echo 1 | sudo tee /sys/class/block/sda/device/rescan
lsblk   # confirm the new size now shows
```

### 2. Grow the partition to use the new space

If the physical volume sits on a partition (e.g. `/dev/sda3`) rather than
directly on the whole disk, grow the partition first using `growpart`
(from `cloud-guest-utils`, commonly pre-installed on cloud/VM images):

```bash
sudo growpart /dev/sda 3
```

### 3. Grow the physical volume to fill the resized partition

```bash
sudo pvresize /dev/sda3
sudo pvs   # confirm PSize now reflects the larger partition
```

### 4. Continue with Part A

The VG now has free space (`vgs` will show it in `VFree`) — proceed with
Part A steps 2-4 to extend the LV and filesystem.

## Part C — Volume group genuinely out of space (no larger disk available)

Use when the underlying disk can't be grown further (physical hardware
at capacity, or a policy against resizing a given disk) and a **new**
disk must be added to the VG instead.

### 1. Attach a new virtual/physical disk

Add the new disk via the hypervisor, then confirm the OS sees it:

```bash
lsblk
```

New disk should appear (e.g. `/dev/sdb`) with no partitions/filesystem.

### 2. Initialize it as a physical volume and add to the VG

```bash
sudo pvcreate /dev/sdb
sudo vgextend vg_data /dev/sdb
sudo vgs   # confirm VSize/VFree grew by the new disk's capacity
```

### 3. Continue with Part A

Extend the LV and filesystem as in Part A steps 2-4 — LVM transparently
spans the LV across both physical volumes; the application/filesystem
layer is unaffected by the underlying disk being non-contiguous across
two devices.

## Rollback / safety notes

- Growing an LV/filesystem is low-risk and effectively always safe if the
  steps above are followed in order (extend LV before resizing
  filesystem, not after).
- **Shrinking** is not covered by this runbook and is meaningfully
  higher-risk (requires shrinking the filesystem *before* the LV, in the
  opposite order, and is not supported at all for XFS) — treat any
  shrink request as a separate, more carefully planned change.
- Always confirm current disk usage and a recent backup exists before any
  LVM operation on a production volume, even though the growth path
  itself is low-risk — mistakes elsewhere in the same maintenance window
  are the more common source of trouble.

## Verification checklist

- [ ] Confirmed the growth request isn't masking a cleanup issue instead
- [ ] `vgs`/`pvs` confirmed available space before extending
- [ ] Filesystem resized (`resize2fs`/`xfs_growfs`) after `lvextend`, not
      skipped
- [ ] `df -h` confirms new size at the mount point
- [ ] Application/service confirmed healthy post-resize
