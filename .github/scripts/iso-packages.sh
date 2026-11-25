#!/usr/bin/env bash
# iso-packages.sh — write the installed package list from a built ISO.
#
# Runs inside the zone-builder container, which provides bsdtar and
# unsquashfs. Usage: iso-packages.sh OUT_DIR

set -Eeuo pipefail

out_dir="${1:-zone-out}"
iso="$(find "$out_dir" -maxdepth 1 -name '*.iso' -type f | sort | tail -1)"
[[ -n "$iso" ]] || { echo "no ISO found in $out_dir" >&2; exit 1; }

for tool in bsdtar unsquashfs; do
    command -v "$tool" >/dev/null \
        || { echo "missing tool: $tool" >&2; exit 1; }
done

work="$(mktemp -d)"
trap 'chmod -R u+rwX "$work" 2>/dev/null || true; rm -rf "$work"' EXIT

echo "reading packages from $(basename "$iso")"
bsdtar -xf "$iso" -C "$work" arch/x86_64/airootfs.sfs
sfs="$work/arch/x86_64/airootfs.sfs"

# squashfs-tools 4.7 takes the extraction filters positionally and repurposes
# -e for a file list, while 4.6 and older use -e.
unsquashfs -q -d "$work/root" "$sfs" var/lib/pacman/local >/dev/null 2>&1 \
    || unsquashfs -q -d "$work/root" -e var/lib/pacman/local "$sfs" >/dev/null

local_db="$work/root/var/lib/pacman/local"
[[ -d "$local_db" ]] \
    || { echo "no package database in $(basename "$sfs")" >&2; exit 1; }

out="$out_dir/packages.txt"
: > "$out"
for desc in "$local_db"/*/desc; do
    [[ -f "$desc" ]] || continue
    name="$(awk '/^%NAME%$/{getline; print; exit}' "$desc")"
    version="$(awk '/^%VERSION%$/{getline; print; exit}' "$desc")"
    [[ -n "$name" && -n "$version" ]] && printf '%s %s\n' "$name" "$version"
done | sort > "$out"

printf 'wrote %s (%s packages)\n' "$out" "$(wc -l < "$out")"
