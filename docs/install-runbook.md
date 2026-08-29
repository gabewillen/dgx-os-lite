# dgx-os-lite install runbook

Step-by-step conversion of a DGX Spark from DGX OS to minimal Debian trixie,
keeping a recovery path at every stage. **Do this on one unit first**; only
repeat on the second after the first is proven.

Per docs/platform.md and docs/memory-accounting.md — read those first.

## Stage 0 — baseline (on stock DGX OS)

```bash
sudo bash /shared/dgx-os-lite/tools/measure-memory.sh \
  | tee /shared/dgx-os-lite/results/baseline-$(hostname)-dgxos.txt
```

Also record: `fwupdmgr get-devices`, `uname -a`, `nvidia-smi`.

## Stage 1 — firmware + backup (on DGX OS; the point of no return is later)

```bash
sudo fwupdmgr refresh && sudo fwupdmgr update
# reboot if any firmware updated, re-run update until clean
```

Firmware must be current **before** DGX OS is gone — factory firmware only
boots DGX OS; fwupd is the update path. Then back up:

```bash
sudo dd if=/dev/nvme0n1p1 of=/shared/esp-backup-$(hostname).img bs=1M status=progress
sudo rsync -aAXH --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found} / /shared/dgxos-root-backup-$(hostname)/
```

(Back up to an external disk if `/shared` is on the same NVMe — do not keep
the only backup on the disk being repartitioned.)

## Stage 2 — install Debian trixie arm64

1. Download Debian trixie arm64 netinst ISO; write to USB
   (`dd` or your preferred tool).
2. Boot the Spark from USB: **Esc/Del at power-on → Boot Menu**. In UEFI
   setup: **disable Secure Boot** (setup → Security) and **disable the
   watchdog** (Advanced) — the watchdog causes spurious reboots on
   non-DGX installs.
3. Install to NVMe: GPT, ESP (~1 GiB) + root (rest). No desktop selection —
   uncheck everything in tasksel; we add packages manually.
4. If the installer keyboard is unresponsive (one unverified report from
   thread 349124): use a newer firmware first, or install via serial/SSH
   with a preseed file (tbd: `build/preseed.cfg`).

## Stage 3 — driver + CUDA (in Debian)

```bash
# as root; CUDA repo for debian13 sbsa
apt-get install -y ca-certificates curl gnupg
curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian13/sbsa/cuda-keyring_1.1-1_all.deb -o /tmp/cuda-keyring.deb
apt-get install -y /tmp/cuda-keyring.deb
apt-get update
# minimal headless driver set (build/nvidia-packages.txt)
apt-get install -y nvidia-open nvidia-kernel-common firmware-nvidia-gsp \
  libcuda1 libnvidia-ml1 nvidia-smi nvidia-persistenced nvidia-modprobe
systemctl enable --now nvidia-persistenced
nvidia-smi   # must show "NVIDIA GB10"
```

10 GbE fix (r8169 breaks warm reboots on RTL8127):
`echo "blacklist r8169" > /etc/modprobe.d/blacklist-r8169.conf` and build the
out-of-tree r8127 driver (or use the NV-Kernels kernel, stage 4).

## Stage 4 — kernel (only if needed)

Try Debian's kernel first. If ethernet is unstable or model-load perf is
below DGX OS baseline, self-build NVIDIA's kernel:

```bash
git clone -b 24.04_linux-nvidia-6.17-next https://github.com/NVIDIA/NV-Kernels
# config via debian.nvidia-6.17/config/annotations; unset
# CONFIG_SYSTEM_TRUSTED_KEYS / CONFIG_SYSTEM_REVOCATION_KEYS; CONFIG_R8127=m
# build: ~30-60 min on the Spark's 20 cores
```

## Stage 5 — inference proof + measurement

```bash
apt-get install -y git clang cmake libcurl4-openssl-dev libssl-dev
git clone https://github.com/ggml-org/llama.cpp
cmake -B llama.cpp/build -S llama.cpp -DGGML_CUDA=ON -DGGML_CURL=ON \
  -DCMAKE_CUDA_ARCHITECTURES=121a-real
cmake --build llama.cpp/build --target llama-server -j
```

Load a GGUF (ggml-org/unsloth), confirm tokens/s, then measure:

```bash
sudo bash /shared/dgx-os-lite/tools/measure-memory.sh \
  | tee /shared/dgx-os-lite/results/lite-$(hostname).txt
```

Compare against Stage 0 baseline; record numbers in `results/` and the
before/after summary in `docs/memory-accounting.md`.

## Rollback

Recovery USB: official DGX OS recovery tar.gz + `CreateUSBKey.sh`
(see docs/platform.md sources) re-images the unit; the Stage 1 backups
restore data.
