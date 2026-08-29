# Debian on DGX Spark (GB10) — platform research findings

Researched 2026-08-28. TL;DR: **this project is feasible and well-trodden** —
Fedora 43, NixOS, Ubuntu Server, and Talos all boot and run CUDA on GB10
outside DGX OS; NVIDIA publishes native Debian 13 arm64 CUDA/driver packages.

## Proof it works

- **Fedora 43 Server headless** boots out of the box (6.17 kernel), GPU shows
  as "NVIDIA GB10", driver 580.95.05, CUDA 13.0 via `nvidia-smi`.
  [Forum thread 349124](https://forums.developer.nvidia.com/t/has-anyone-tried-an-alternative-linux-distro/349124)
- **NixOS** full config: [graham33/nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark).
- **Ubuntu 26.04 + driver 610 + CUDA 13.3** on ASUS GX10 (same GB10 SoC):
  llama.cpp at DGX-OS speed; author calls DGX OS "bloatware" and skips the
  DGX software stack entirely. [Thread 373655](https://forums.developer.nvidia.com/t/ubuntu-26-04-drivers-610-cuda-toolkit-13-3-zfs-on-gx10/373655)
- No Debian-specific success report found yet (closest proxy); one unverified
  report of a Debian installer keyboard issue (thread 349124 post 48).

## Boot chain

- Standard **AMI UEFI**, boot menu Esc/Del; NVMe = plain GPT with ESP + root.
  ([UEFI settings doc](https://docs.nvidia.com/dgx/dgx-spark/uefi-settings.html))
- **Secure Boot is enabled by default — disable it** (NVIDIA's own doc says
  custom bootloaders require it off).
- **Critical firmware constraint:** factory firmware only boots DGX OS.
  **Update firmware from within DGX OS (fwupd) before replacing it**;
  after that, boot is generic. (nixos-dgx-spark README)
- Recovery is a tar.gz + `CreateUSBKey.sh` USB image (not ISO) — our escape
  hatch. [System recovery doc](https://docs.nvidia.com/dgx/dgx-spark/system-recovery.html)
- UEFI+ACPI; no device tree needed in the OS boot path.

## Driver / CUDA on Debian

- NVIDIA's CUDA repo ships **`debian13/sbsa/`** arm64 packages:
  `cuda-toolkit-13.3.1`, open-kernel-module drivers 595.x/610.x
  (`nvidia-open`, `nvidia-kernel-open-dkms`, `libcuda1`, `nvidia-smi`,
  `nvidia-persistenced`, `firmware-nvidia-gsp`, `cuda-drivers`),
  `nvidia-container-toolkit`.
  [Package index](https://developer.download.nvidia.com/compute/cuda/repos/debian13/sbsa/)
- GB10 = PCIe device, compute capability **12.1 (sm_121)**; needs CUDA 13.
- Headless-minimal driver set: kernel modules + `libcuda1` + `libnvidia-ml1`
  + `nvidia-persistenced` + `nvidia-modprobe`. All X/EGL/Vulkan/GL optional.
- DGX OS userspace stack entirely optional — working installs skip it.

## Kernel

- Vanilla kernels boot, but NVIDIA's kernel branch (`NV-Kernels`,
  `24.04_linux-nvidia-6.17-next`, ~80 Spark patches) matters for:
  1. **Ethernet**: 10 GbE is Realtek RTL8127; the `r8169` driver claims it
     and breaks warm reboots. Need `CONFIG_R8127=m` / r8127 driver and
     `module_blacklist=r8169`.
  2. **Performance**: model-load times measurably better on NVIDIA's kernel;
  3. config from NVIDIA's **Debian annotations**
     (`debian.nvidia-6.17/config/annotations`); unset
     `CONFIG_SYSTEM_TRUSTED_KEYS`/`CONFIG_SYSTEM_REVOCATION_KEYS`.
- Uncertain (verify on hardware): whether NVIDIA's `linux-nvidia` apt packages
  install on pure Debian, or the kernel must be self-built. Plan for
  self-build (~30–60 min on the Spark's 20 cores).

## Minimal inference stack

- **llama.cpp** (official NVIDIA playbook): `git clang cmake libcurl4-openssl-dev
  libssl-dev`, build with `-DGGML_CUDA=ON -DCMAKE_CUDA_ARCHITECTURES=121a-real`.
  Runtime needs only the CUDA runtime + libcurl/libssl.
  [Playbook](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/llama-cpp/README.md)
- **ollama** works (self-contained); **vLLM** works via NGC docker container
  (pip wheels for aarch64 are CUDA-12 and fail on GB10).

## Build strategy (adopted)

**Build natively on the Spark**, not qemu-cross (kernel/driver/boot must be
tested on hardware; qemu is fine only for pre-seeding a rootfs tarball):

1. On DGX OS: update all firmware (fwupd). Verify with `tools/measure-memory.sh` baseline.
2. Back up ESP (`dd if=/dev/nvme0n1p1`) and rsync `/` — recovery escape hatch.
3. Boot Debian trixie arm64 netinst USB, **secure boot off**, install to NVMe
   (ESP + root, GRUB, headless).
4. Add CUDA debian13/sbsa repo → driver + toolkit.
5. Kernel: first try Debian's 6.17 + out-of-tree r8127; if perf/ethernet
   suffers, self-build NV-Kernels 6.17 from Debian annotations.
6. `blacklist r8169`, enable `nvidia-persistenced`, disable UEFI watchdog.
7. Build llama.cpp for sm_121; run `tools/measure-memory.sh` → `results/`.

## Open risks (verify empirically)

1. Debian kernel vs NVIDIA kernel performance/ethernet parity.
2. NVIDIA `linux-nvidia` packages on pure Debian (likely self-build needed).
3. Debian installer input quirk (single report) — mitigate via preseed/SSH.

## Sources

- [Forum 349124 — alternative distros on Spark](https://forums.developer.nvidia.com/t/has-anyone-tried-an-alternative-linux-distro/349124)
- [graham33/nixos-dgx-spark](https://github.com/graham33/nixos-dgx-spark)
- [Forum 350517 — Ubuntu 26.04 on Spark](https://forums.developer.nvidia.com/t/ubuntu-26-04-lts-kernel-6-17-0-arm64-on-dgx-spark-anyone/350517)
- [Forum 373655 — minimal Ubuntu + CUDA on GX10](https://forums.developer.nvidia.com/t/ubuntu-26-04-drivers-610-cuda-toolkit-13-3-zfs-on-gx10/373655)
- [UEFI settings](https://docs.nvidia.com/dgx/dgx-spark/uefi-settings.html) ·
  [System recovery](https://docs.nvidia.com/dgx/dgx-spark/system-recovery.html) ·
  [Custom install](https://docs.nvidia.com/dgx/dgx-spark/enterprise-custom-install.html) ·
  [Release notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html) ·
  [Known issues](https://docs.nvidia.com/dgx/dgx-spark/known-issues.html)
- [CUDA debian13/sbsa repo](https://developer.download.nvidia.com/compute/cuda/repos/debian13/sbsa/)
- [llama.cpp playbook](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/llama-cpp/README.md) ·
  [vLLM playbook](https://github.com/NVIDIA/dgx-spark-playbooks/blob/main/nvidia/vllm/README.md)
- [NVIDIA/NV-Kernels](https://github.com/NVIDIA/NV-Kernels)
