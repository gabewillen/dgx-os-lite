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
- sshd out of the box: `ssh dgx@dgx-spark.local` (mDNS discovery — no IP hunt)
- DHCP on ethernet, WiFi (iwlwifi/rtw/mt79), and ConnectX (`mlx5_core`) for multinode
- Serial console on ttyAMA0 (debug)
- Volatile journald (8 MiB RAM cap), swappiness off, heavy services masked
- Headless: no desktop stack, no X11/GL

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

## Flash and boot

```bash
xz -d dgx-spark-lite.raw.xz
sudo dd if=dgx-spark-lite.raw of=/dev/sdX bs=4M oflag=direct status=progress
```

Boot the DGX Spark from USB (UEFI). First boot takes ~1 min (ssh key
generation, rootfs expansion). Then:

```bash
ssh root@dgx-spark.local
```

## Access (out of the box)

- Root password: `dgx-spark` (build-time hash in `mkosi/mkosi.conf` —
  **change it** before deploying: `mkosi --root-password=...` or edit the config).
- SSH keys: root login is key-based; drop your public key at
  `mkosi/mkosi.extra/root/.ssh/authorized_keys` before building (that path is
  gitignored, so keys never hit the repo).
- Discovery: `ssh root@dgx-spark.local` (mDNS via avahi) or check DHCP leases.
- Serial fallback: 115200 8N1 on the debug port, root + password above.

## RAM philosophy

Every service is on trial. Default state:

| running | why |
|---|---|
| systemd (PID 1) | Debian semantics, unit management |
| systemd-networkd + wpa_supplicant | connectivity |
| sshd + avahi-daemon | remote access + discovery |
| udevd | device management |

Masked/absent: resolved (DNS via networkd), journald to disk, userdbd,
homed, portabled, daily apt timers, e2scrub, fstrim, ModemManager, polkit,
udisks2, cups, NetworkManager. Result target: **well under 512 MiB RSS**
before any inference engine is loaded (see `docs/memory-accounting.md`).

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
