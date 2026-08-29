# dgx-spark-lite

> **Status: WIP / alpha** — VM-verified end-to-end (Debian arm64, XFS root,
> NVIDIA driver chain, ssh+mDNS at first boot). Not yet validated on real
> DGX Spark hardware. Expect breaking changes to the image layout until 1.0.



Minimal, out-of-the-box Debian Linux image for the **NVIDIA DGX Spark** (GB10,
Grace Blackwell, arm64). Designed as a clean base for inference workloads:
all drivers included, OS services and RAM floor minimized to leave maximum
unified memory for the GPU.

## What you get

- Debian 13 (trixie) rootfs, **XFS** root filesystem
- NVIDIA driver stack (nvidia-open for Blackwell, GSP firmware, persistence mode)
- sshd out of the box: `ssh root@gx10-5e36.local` (mDNS; hostname is `{sku}-{4-hex}` from DMI)
- DHCP on ethernet, WiFi (iwlwifi/rtw/mt79), and ConnectX (`mlx5_core` + `rdma-core`/`libibverbs`/`ibverbs-providers` for NCCL/RoCE)
- Serial console on ttyAMA0 (debug)
- Headless: no desktop stack, no X11/GL. PID 1 is finit; initrd is busybox.

## Build it

On any Linux host with Docker-free `mkosi` ≥ 25 and binfmt (native arm64
hosts — including GitHub's `ubuntu-24.04-arm` runners — skip the binfmt bit):

```bash
sudo apt install mkosi qemu-user-static   # Debian/Ubuntu host
cd mkosi
sudo mkosi build -f --output-dir ../output
```

Output: `output/dgx-spark-lite.raw` (~1.5-2 GB GPT disk image, ESP + XFS root).

CI does this on every push to `main` and attaches the image as an artifact;
tagged releases (`v*`) publish it to GitHub Releases.

## Install onto a Spark (preserve ESP)

Do **not** `dd` the OS image over the internal NVMe. Build the USB
installer instead. It does **not** update firmware (do that from DGX OS
with `fwupd` first). Official NVIDIA recovery USB already wipes and
rebuilds the SSD, so this installer does not try to preserve NVIDIA OS
or recovery partitions.

```bash
cd mkosi
sudo bash build-usb-installer.sh ../output/dgx-os-lite-installer.raw
sudo dd if=../output/dgx-os-lite-installer.raw of=/dev/sdX bs=4M oflag=direct status=progress
```

On the Spark (firmware already updated from DGX OS, Secure Boot off):

1. Boot the USB (UEFI Boot Override).
2. `dgx-os-lite-install.service` runs automatically and:
   - verifies DMI is DGX Spark / GB10 (or ASUS GX10)
   - checks UEFI mode + Secure Boot off (no fwupd)
   - **keeps** the EFI System Partition (adds files, does not wipe it)
   - **replaces** the first Linux OS partition with the lite rootfs
   - copies `\EFI\dgx-os-lite\grubaa64.efi` without deleting NVIDIA boot files
   - creates EFI boot entry **DGX-OS-Lite**, sets `BootNext`, reboots

Disable auto-install: kernel cmdline `dgx.lite.install=0`. Dry-run:
`DGX_LITE_DRY_RUN=1`. Force re-run: `DGX_LITE_FORCE=1`.

The raw OS image (`dgx-spark-lite.raw`) remains a VM/dev artifact, not
the Spark install path.



## Access (out of the box)

- Root password: `dgx-spark` (build-time hash in `mkosi/mkosi.conf` —
  **change it** before deploying: `mkosi --root-password=...` or edit the config).
- SSH keys: root login is key-based; drop your public key at
  `mkosi/mkosi.extra/root/.ssh/authorized_keys` before building (that path is
  gitignored, so keys never hit the repo).
- Discovery: `ssh root@gx10-5e36.local` (mdnsd; `{sku}-{4-hex}` from DMI serial) or DHCP leases.
- Serial fallback: 115200 8N1 on the debug port, root + password above.

## RAM philosophy

Every service is on trial. Default state:

| running | why |
|---|---|
| finit (PID 1) | finit-sysv; udev + standalone sysusers/tmpfiles (no systemd daemon) |
| ifupdown + /etc/network/interfaces | DHCP on eth/enp/mlx |
| sshd + mdnsd | remote access + `{sku}-{4hex}.local` |
| systemd-udevd | device management (udev package, not PID 1) |

No systemd as PID 1. No journald, networkd, resolved, userdbd, homed.
Result target: **well under 512 MiB RSS** before inference
(see `docs/memory-accounting.md`).


## Extending (inference engine)

The image is a plain Debian arm64 rootfs: `apt`, `pip`, and
`python3-venv` work normally. CUDA userspace (`cuda-cudart`) is installed;
add `cuda-toolkit-13-x` or pip wheels (`torch`, `llama.cpp` CUDA build) as
needed. The NVIDIA repo is pre-configured in `/etc/apt/sources.list.d/`.

## Layout

```
mkosi/
  mkosi.conf            # distribution, output, base packages
  mkosi.conf.d/10-nvidia.conf   # (reserved) nvidia packages
  mkosi.repart/         # partition layout: ESP + XFS root
  scripts/prepare.chroot    # NVIDIA CUDA repo + driver install (in chroot)
  scripts/postinst.chroot   # service masking, network, ssh, mDNS (in chroot)
.github/workflows/build.yml # CI: native arm64 build, artifacts + releases
docs/                   # research notes (memory accounting, platform, runbook)
```

## Status / verification

- [x] boots to multi-user in aarch64 QEMU VM (Proxmox, UEFI+virtio)
- [ ] first-boot chain on real DGX Spark (staged per `docs/install-runbook.md`)
- [ ] `nvidia-smi` on GB10
- [ ] authoritative unified-memory numbers

## License

MIT — see [LICENSE](LICENSE).
