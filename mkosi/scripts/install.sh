#!/usr/bin/env bash
# Install DGX-OS-Lite. Dispatch: install.sh <target>
# Target default: nvme
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HERE/install"

LOG=/var/log/dgx-os-lite-install.log
PAYLOAD=/opt/dgx-os-lite/rootfs.img
ESP_STAGING=/opt/dgx-os-lite/esp
MARKER=/var/lib/dgx-os-lite/installed
DRY_RUN="${DGX_LITE_DRY_RUN:-0}"
ALLOW_NONSPARK="${DGX_LITE_ALLOW_NONSPARK:-0}"
FORCE="${DGX_LITE_FORCE:-0}"
REBOOT_AFTER="${DGX_LITE_REBOOT:-1}"

usage() {
  cat <<'USAGE'
Usage:
  install.sh [<target>]

Description:
  Install DGX-OS-Lite onto a Spark. Targets are scripts under install/.

Targets:
  nvme    Replace the largest Linux partition on internal NVMe (default).
          Keep ESP. Add EFI boot entry. BootNext. Reboot.

Environment:
  DGX_LITE_DRY_RUN=1          Plan only, no writes
  DGX_LITE_FORCE=1            Re-run even if already installed
  DGX_LITE_REBOOT=0           Skip reboot
  DGX_LITE_ALLOW_NONSPARK=1   Skip DMI gate (tests)
  DGX_LITE_DISK=/dev/loopN    Override target disk (tests)
USAGE
}

mkdir -p "$(dirname "$LOG")" /var/lib/dgx-os-lite
exec > >(tee -a "$LOG") 2>&1

# shellcheck source=install/(lib)/common
source "$INSTALL_DIR/(lib)/common"

target="${1:-nvme}"
case "$target" in
  -h|--help|help)
    usage
    exit 0
    ;;
  nvme)
    shift || true
    # shellcheck source=install/nvme
    source "$INSTALL_DIR/nvme"
    run_nvme "$@"
    ;;
  *)
    die "unknown target: $target (try: install.sh --help)"
    ;;
esac
