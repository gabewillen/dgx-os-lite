#!/bin/bash
# Build the USB installer: OS image → extract ESP+rootfs payload → installer disk.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
OUT="${1:-$HERE/dgx-os-lite-installer.raw}"

echo "[usb] building OS payload image"
mkosi build -f --output dgx-spark-lite.raw

PAYLOAD="$HERE/.payload"
rm -rf "$PAYLOAD"
mkdir -p "$PAYLOAD"
echo "[usb] extracting ESP + root filesystem from OS image"
"$HERE/scripts/extract-payload.sh" "$HERE/dgx-spark-lite.raw" "$PAYLOAD"

EXTRA="$HERE/.installer-extra"
rm -rf "$EXTRA"
mkdir -p "$EXTRA/opt/dgx-os-lite" "$EXTRA/usr/local/sbin"
cp -a "$PAYLOAD/esp" "$EXTRA/opt/dgx-os-lite/esp"
cp --sparse=always "$PAYLOAD/rootfs.img" "$EXTRA/opt/dgx-os-lite/rootfs.img"
cp "$HERE/scripts/install.sh" "$EXTRA/usr/local/sbin/install.sh"
cp -a "$HERE/scripts/install" "$EXTRA/usr/local/sbin/install"
chmod 755 "$EXTRA/usr/local/sbin/install.sh"

echo "[usb] building installer disk"
mkosi -C "$HERE/installer" --extra-tree "$EXTRA" build -f --output "$(basename "$OUT")"
# mkosi 25.3 often writes next to the config dir regardless of --output-dir
if [[ -f "$HERE/installer/dgx-os-lite-installer.raw" ]]; then
  cp --sparse=always "$HERE/installer/dgx-os-lite-installer.raw" "$OUT"
elif [[ -f "$HERE/installer/image.raw" ]]; then
  cp --sparse=always "$HERE/installer/image.raw" "$OUT"
fi
echo "[usb] installer image: $OUT"
echo "Flash: sudo dd if=$OUT of=/dev/sdX bs=4M oflag=direct status=progress"
