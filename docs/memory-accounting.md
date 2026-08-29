# Memory accounting on DGX Spark (GB10) — research findings

Researched 2026-08-28 via NVIDIA forums, official docs, and community
measurements. Every load-bearing claim has a source; unknowns are flagged.

## Where the 128 GB goes

| Stage | Size | Source |
|---|---|---|
| Nominal LPDDR5x pool | 128 GB (decimal, ≈128,000 MB) | [NVIDIA spec](https://www.nvidia.com/en-us/products/workstations/dgx-spark/) |
| Static firmware reservation | ≈5.4 GB (CUDA deviceQuery reports 122,570 MB total) | [Kubesimplify deep-dive](https://blog.kubesimplify.com/day-3-the-dgx-spark-unpacked-gb10-unified-memory-sm-121-and-the-one-reason-this-hardware-exists), [llama.cpp discussion #16578](https://github.com/ggml-org/llama.cpp/discussions/16578) |
| Linux MemTotal (what `free` sees) | ~119–120 GiB | same |
| Available, stock DGX OS + GNOME idle | ~116 GiB (~4.7 GiB used) | [Techno Tim measurements](https://technotim.com/posts/ubuntu-gb10/) |
| Available, minimized Ubuntu Server 24.04 | ~118 GiB (~2.9 GiB used) | [Techno Tim](https://technotim.com/posts/ubuntu-gb10/) |

## The three traps in "the OS eats my memory"

1. **Units.** 128 GB decimal ≈ 119.2 GiB. The "missing" ~9 GB between the
   marketing number and `free -h` is mostly GB-vs-GiB, not reservation.
   (Forum users hit this constantly — see [119GB-in-ComfyUI thread](https://forums.developer.nvidia.com/t/dgx-spark-can-only-use-119gb-of-memory-running-comfyui-so-it-is-killed-isnt-there-128gb-of-memory-why-cant-it-be-used/352962).)
2. **Page cache.** Reports of "15–20 GB in use at idle" were diagnosed as
   filesystem page cache, which is reclaimable on demand — not RSS.
   ("Free memory is wasted memory"; [thread 350359](https://forums.developer.nvidia.com/t/the-dgx-system-itself-takes-up-20gb-memory/350359),
   [thread 359479](https://forums.developer.nvidia.com/t/is-there-a-way-to-reduce-baseline-memory-usage-on-dgx-spark-systems/359479).)
   Early driver/CUDA free-memory calculations ignored cache; fixed by NVIDIA.
   Precaution: `sync; echo 3 > /proc/sys/vm/drop_caches` before model load.
3. **Static firmware floor (~5.4 GB).** Not reachable by any public software
   method. Composition is not publicly itemized (no source decomposes
   hypervisor/TF-A/display/GPU-ring shares). The one documented knob —
   **Display Reserved Memory** BIOS toggle, 2 GB default / 4 GB
   ([release notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html)) —
   is already at its minimum.

## Idle RSS reality

- DGX OS + GNOME idle: **~4.7 GiB** used; desktop with apps open ~5.8 GiB;
  Xorg + gnome-shell + gnome-remote-desktop hold ~340 MB of shared GPU memory.
  ([Techno Tim](https://technotim.com/posts/ubuntu-gb10/))
- Minimized headless Ubuntu Server: **~2.9 GiB** used.
- "In non-graphical mode the OS can take under 1 GB" (eugr, frequent Spark
  forum contributor; [thread 350359](https://forums.developer.nvidia.com/t/the-dgx-system-itself-takes-up-20gb-memory/350359))
- vLLM operator accounting: ~7 GB "baseline before launch (OS + desktop)"
  ([Memory Creep thread](https://forums.developer.nvidia.com/t/memory-creep-on-dgx-spark-where-your-128-gb-actually-goes-and-how-to-stop-it/364886))

## Levers, ranked for dgx-os-lite

1. **No GNOME / graphics stack at all** — build headless from the start, or
   `systemctl set-default multi-user.target` on DGX OS. Real saving ~2–3 GB
   vs desktop (one careful measurement said only ~200 MiB RAM + 140 MiB GPU
   for gdm alone; ~1.8 GiB for full GNOME-vs-server). Frees the ~340 MB
   GPU-shared memory too. Sources: threads 359479, 364886; Techno Tim.
2. **Skip hugepage reservations** — NVIDIA's Aerial tuned profile reserves
   24×1 GiB hugepages; DGX OS default does not. Never enable on this build.
   ([Aerial guide](https://docs.nvidia.com/aerial/cuda-accelerated-ran/latest/install_guide/installing_tools_spark.html))
3. **crashkernel already disabled** on stock cmdline (`crashkernel=1G-:0M`);
   keep it off.
4. **Disable swap** — avoids swapfile disk use and UMA hard-lockups with GPU
   DMA. ([natolambert/dgx-spark-setup](https://github.com/natolambert/dgx-spark-setup))
5. **Pin a non-leaky driver** — 590.48.01 leaks UMA after CUDA exit (93 GB
   pinned post-vLLM); use 580.126.09 or ≥595.45.04.
   ([thread 363178](https://forums.developer.nvidia.com/t/how-to-automatically-free-shared-system-memory/363178))
6. **Purge nvsm / unattended-upgrades / apt timers** — mostly CPU/stability,
   marginal GB. (Techno Tim)

## Bottom line

A minimized headless OS starts at ~2.9 GiB used / ~118 GiB available vs
~4.7 GiB / ~116 GiB under DGX OS + GNOME. **The real software-reclaimable
delta is ~1.5–3 GB, not tens of GB.** The ~5.4 GB firmware floor and the
GB/GiB units gap are unrecoverable. dgx-os-lite's honest target:
**< 1 GiB OS RSS, no graphics stack, no swap, ~117.5+ GiB model-available** —
and measurement on our units (`tools/measure-memory.sh`) is the arbiter.

### Desktop overhead, quantified (the "it runs a full desktop" question)

The GNOME desktop in DGX OS costs ~1.8–3 GB versus a headless base:

- DGX OS + GNOME idle: ~4.7 GiB used; minimized Ubuntu Server: ~2.9 GiB
  ([Techno Tim](https://technotim.com/posts/ubuntu-gb10/)).
- gdm/Xorg alone: ~200 MiB RAM + ~140 MiB GPU-shared (careful measurement,
  thread 364886); the larger 1.8–3 GB figure is full GNOME vs server,
  including shell extensions, trackers, and the GPU graphics buffers.
- dgx-os-lite never installs any of it: no X/Wayland, no gdm, no GL/EGL
  stack — so the target is the sub-1-GiB headless floor, below even the
  2.9 GiB "minimized server" number (which still carries snaps and
  unattended-upgrades we also omit).
- The remaining gap between "feels huge" and ~2–3 GB is the firmware floor
  (~5.4 GB), the GB/GiB units gap (~9 GB), and page cache (reclaimable) —
  none of which a desktop removal touches.

Claim to treat skeptically: the
[Entrpi serving-mode script](https://github.com/Entrpi/dgx-spark-serving-mode)
claims GNOME+snap hold "~10–15 GB" — contradicts direct `free` measurements;
presumably counts page cache as held.

## Sources

- [NVIDIA DGX Spark product page](https://www.nvidia.com/en-us/products/workstations/dgx-spark/)
- [DGX Spark Release Notes](https://docs.nvidia.com/dgx/dgx-spark/release-notes.html)
- [Aerial: Installing Tools on DGX Spark](https://docs.nvidia.com/aerial/cuda-accelerated-ran/latest/install_guide/installing_tools_spark.html)
- [Forum 347814 — 12GB on fresh boot / dashboard bug](https://forums.developer.nvidia.com/t/12gb-of-ram-in-use-on-a-freshly-booted-spark-disabling-desktop-mode/347814)
- [Forum 359479 — reduce baseline memory](https://forums.developer.nvidia.com/t/is-there-a-way-to-reduce-baseline-memory-usage-on-dgx-spark-systems/359479)
- [Forum 350359 — "system takes 20GB" (page cache diagnosis)](https://forums.developer.nvidia.com/t/the-dgx-system-itself-takes-up-20gb-memory/350359)
- [Forum 363178 — driver 590 UMA leak](https://forums.developer.nvidia.com/t/how-to-automatically-free-shared-system-memory/363178)
- [Forum 364886 — Memory Creep accounting](https://forums.developer.nvidia.com/t/memory-creep-on-dgx-spark-where-your-128-gb-actually-goes-and-how-to-stop-it/364886)
- [Forum 352962 — 119GB in ComfyUI (units)](https://forums.developer.nvidia.com/t/dgx-spark-can-only-use-119gb-of-memory-running-comfyui-so-it-is-killed-isnt-there-128gb-of-memory-why-cant-it-be-used/352962)
- [Techno Tim — Ubuntu Server on DGX Spark](https://technotim.com/posts/ubuntu-gb10/)
- [Kubesimplify — GB10 unpacked](https://blog.kubesimplify.com/day-3-the-dgx-spark-unpacked-gb10-unified-memory-sm-121-and-the-one-reason-this-hardware-exists)
- [natolambert/dgx-spark-setup](https://github.com/natolambert/dgx-spark-setup)
- [yzhao062/agent-config — dgx-spark-setup](https://github.com/yzhao062/agent-config/blob/main/docs/dgx-spark-setup.md)
- [Entrpi/dgx-spark-serving-mode](https://github.com/Entrpi/dgx-spark-serving-mode)
- [llama.cpp discussion #16578](https://github.com/ggml-org/llama.cpp/discussions/16578)
- [rageltd/linux-dgx-spark](https://github.com/rageltd/linux-dgx-spark)
