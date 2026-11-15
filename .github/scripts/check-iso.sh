#!/usr/bin/env bash
# Verify that a built Zone ISO carries the full boot-splash payload.
#
# Runs inside the zone-builder container, which provides bsdtar and
# lsinitcpio. Usage: check-iso.sh [OUT_DIR]

set -Eeuo pipefail

out_dir="${1:-zone-out}"
iso="$(find "$out_dir" -maxdepth 1 -name '*.iso' -type f | sort | tail -1)"
[[ -n "$iso" ]] || { echo "no ISO found in $out_dir" >&2; exit 1; }

for tool in bsdtar lsinitcpio; do
    command -v "$tool" >/dev/null \
        || { echo "missing tool: $tool" >&2; exit 1; }
done

work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

echo "checking $(basename "$iso")"

# Boot entries: every Linux entry must request the graphical splash.
bsdtar -xf "$iso" -C "$work" loader/entries boot/syslinux
shopt -s nullglob
entries=("$work"/loader/entries/*-linux.conf)
[[ ${#entries[@]} -gt 0 ]] || { echo "no systemd-boot Linux entries" >&2; exit 1; }
for entry in "${entries[@]}"; do
    grep -q '^options.*splash' "$entry" \
        || { echo "$(basename "$entry"): missing splash parameter" >&2; exit 1; }
done
grep -q '^APPEND.*splash' "$work/boot/syslinux/archiso_sys-linux.cfg" \
    || { echo "syslinux entry: missing splash parameter" >&2; exit 1; }
shopt -u nullglob

# Initramfs: the splash hook, plymouth and all four themes.
bsdtar -xf "$iso" -C "$work" arch/boot/x86_64/initramfs-linux.img
mkdir -p "$work/root"
( cd "$work/root" && lsinitcpio -x "$work/arch/boot/x86_64/initramfs-linux.img" >/dev/null )

for hook in zone-splash plymouth; do
    [[ -f "$work/root/hooks/$hook" ]] \
        || { echo "missing initramfs hook: $hook" >&2; exit 1; }
done
grep -q 'random/uuid' "$work/root/hooks/zone-splash" \
    || { echo "zone-splash hook lacks UUID randomisation" >&2; exit 1; }

for theme in zone-mark zone-anomaly zone-pda zone-sector; do
    dir="$work/root/usr/share/plymouth/themes/$theme"
    [[ -f "$dir/$theme.plymouth" && -f "$dir/$theme.script" ]] \
        || { echo "incomplete Plymouth theme: $theme" >&2; exit 1; }
done

for file in usr/lib/plymouth/script.so etc/plymouth/plymouthd.conf; do
    [[ -f "$work/root/$file" ]] \
        || { echo "missing from the initramfs: $file" >&2; exit 1; }
done

echo "boot splash payload ok"
