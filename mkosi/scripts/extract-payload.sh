#!/bin/bash
# Host-side (not chroot): after mkosi produces the OS disk image, copy
# its ESP tree and raw root *filesystem* into the installer extra tree so
# the USB installer never dd's a nested GPT onto the Spark NVMe.
set -euo pipefail

IMG="${1:?usage: extract-payload.sh <os-disk.raw> <dest-dir>}"
DEST="${2:?usage: extract-payload.sh <os-disk.raw> <dest-dir>}"

LOOP=$(losetup --find --show --partscan "$IMG")
cleanup() {
  umount "$DEST/.esp-mnt" 2>/dev/null || true
  losetup -d "$LOOP" 2>/dev/null || true
}
trap cleanup EXIT

sleep 0.2
ESP=""
ROOT=""
for p in "${LOOP}p1" "${LOOP}p2"; do
  [[ -b "$p" ]] || continue
  ptype=$(blkid -o value -s PART_ENTRY_TYPE "$p" || true)
  fstype=$(blkid -o value -s TYPE "$p" || true)
  if [[ "$ptype" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]]; then
    ESP="$p"
  elif [[ "$fstype" == xfs || "$fstype" == ext4 ]]; then
    ROOT="$p"
  fi
done
[[ -n "$ESP" && -n "$ROOT" ]] || { echo "could not find ESP+root on $IMG"; exit 1; }

mkdir -p "$DEST/esp" "$DEST/.esp-mnt"
mount -o ro "$ESP" "$DEST/.esp-mnt"
cp -a "$DEST/.esp-mnt/." "$DEST/esp/"
umount "$DEST/.esp-mnt"
rmdir "$DEST/.esp-mnt"

# Raw filesystem image (not a GPT). Sparse copy.
cp --sparse=always "$ROOT" "$DEST/rootfs.img"
sync
echo "payload: ESP tree $(du -sh "$DEST/esp" | cut -f1)  rootfs $(du -sh "$DEST/rootfs.img" | cut -f1)"
