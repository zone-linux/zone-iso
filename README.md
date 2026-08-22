<p align="center">
<img width="100" height="auto" src="archiso/airootfs/usr/share/zone.png" />
</p>
<h1 align="center">Welcome To The Zone</h1>

Zone Linux is a custom Arch Linux-based live ISO with an XFCE desktop themed around S.T.A.L.K.E.R.

## Build (Docker — recommended)

Requires Docker on a Linux host. Run once from the repo root:

```bash
chmod +x build.sh
./build.sh
```

The ISO is written to `zone-out/`.

## Build (native archiso)

Requires a current Arch Linux host with `archiso` installed.

```bash
sudo pacman -S archiso
sudo mkarchiso -v -w /tmp/zone-work -o ./zone-out ./archiso
```

## Flash to USB

```bash
sudo dd if=zone-out/zone-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
```

Replace `/dev/sdX` with your target device (check with `lsblk`).

## Adding a Package

1. Add the package name to `archiso/packages.x86_64`
2. If the package has executables in `airootfs/usr/local/bin/`, add a `"0:0:755"` entry in `profiledef.sh`'s `file_permissions` array
3. If it is a custom package, build a PKGBUILD in `zone-pkgbuild/`, add the binary to the appropriate `zone-*-repo`, and ensure `pacman.conf` references that repo

## Repository Layout

| Path | Purpose |
|---|---|
| `archiso/` | archiso profile (packages, hooks, configs, bootloaders) |
| `archiso/airootfs/` | Files overlaid onto the live rootfs |
| `archiso/packages.x86_64` | All packages installed in the live ISO |
| `installation-scripts/` | Legacy manual build helper scripts |
| `docker/` | Dockerfile for containerised builds |
| `build.sh` | Docker build wrapper |

## Notable Changes (2022 → 2026)

- mkinitcpio HOOKS: removed `archiso_shutdown` (dropped upstream) and `archiso_kms` (deprecated); added `kms`; added `MODULES=(loop squashfs overlay)`
- Compression: switched from xz to zstd for faster build and boot
- pacman.conf: removed defunct `[community]` repo (merged into `[extra]` in Aug 2023)
- packages: removed `crda` (defunct since kernel 5.15), `reiserfsprogs` (removed from kernel 6.6), `ueberzug` (project archived), `bind-tools`/`dnsutils` (replaced by `bind`); renamed `nerd-fonts-jetbrains-mono` → `ttf-jetbrains-mono-nerd`
- syslinux: fixed stray `16` that broke the NVIDIA BIOS boot entry
- chrooted_post_install: fixed GPU variable initialisation bug that left stale drivers on installed systems
