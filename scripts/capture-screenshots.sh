#!/usr/bin/env bash
# shellcheck disable=SC2054  # QEMU arguments intentionally contain commas
# capture-screenshots.sh — capture the README screenshots from a built ISO.
#
# Boots the ISO headless under QEMU/KVM, drives the live session through QMP,
# and writes splash/greeter/desktop/menu/terminal/installer PNGs.
#
# Usage:
#   ./scripts/capture-screenshots.sh [ISO] [--out DIR] [--keep]
#
# Requirements: qemu-system-x86_64 (7.1+ for PNG screendumps), bsdtar, and
# python3 with Pillow.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ISO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
QMP="${SCRIPT_DIR}/qmp.py"
OUT="${ISO_DIR}/docs/screenshots"
ISO=""
KEEP=0
MEM=4096
CPUS=2

info() { printf '\033[36m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33m ! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[31mERR\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: ./scripts/capture-screenshots.sh [ISO] [OPTIONS]

Boots a Zone ISO headless and captures the screenshots used in the README.
With no ISO, the newest zone-out/zone-*.iso is used.

Options:
  --out DIR     Output directory (default: docs/screenshots)
  --keep        Keep the raw burst frames and print their location
  --mem MB      Guest RAM (default: 4096)
  --cpus N      vCPU count (default: 2)
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)  OUT="${2:?--out needs a directory}"; shift ;;
        --keep) KEEP=1 ;;
        --mem)  MEM="${2:?--mem needs a number}"; shift ;;
        --cpus) CPUS="${2:?--cpus needs a number}"; shift ;;
        -h|--help) usage; exit 0 ;;
        -*) die "unknown option: $1 (see --help)" ;;
        *)  [[ -z "$ISO" ]] || die "unexpected argument: $1"; ISO="$1" ;;
    esac
    shift
done

if [[ -z "$ISO" ]]; then
    ISO="$(find "${ISO_DIR}/zone-out" -maxdepth 1 -name 'zone-*.iso' -type f 2>/dev/null \
        | sort -V | tail -1)"
fi
[[ -n "$ISO" && -f "$ISO" ]] || die "no ISO found; build one with ./build.sh first"
ISO="$(cd "$(dirname "$ISO")" && pwd)/$(basename "$ISO")"

if [[ -f "${ISO}.sha256" ]]; then
    info "verifying $(basename "$ISO")"
    ( cd "$(dirname "$ISO")" && sha256sum -c "$(basename "$ISO").sha256" ) \
        || die "ISO checksum mismatch"
fi

for tool in qemu-system-x86_64 qemu-img bsdtar python3; do
    command -v "$tool" >/dev/null || die "missing tool: $tool"
done
python3 -c 'import PIL' 2>/dev/null || die "python-pillow is required"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/zone-shots.XXXXXX")"
qemu_pid=""
cleanup() {
    if [[ -n "$qemu_pid" ]] && kill -0 "$qemu_pid" 2>/dev/null; then
        python3 "$QMP" --socket "$tmp/qmp.sock" quit >/dev/null 2>&1 || true
        wait "$qemu_pid" 2>/dev/null || true
    fi
    if [[ "$KEEP" -eq 1 ]]; then
        info "raw frames kept in $tmp"
    else
        rm -rf "$tmp"
    fi
}
trap cleanup EXIT

mkdir -p "$tmp/splash" "$tmp/out" "$OUT"

info "extracting the kernel and initramfs"
bsdtar -xf "$ISO" -C "$tmp" \
    arch/boot/x86_64/vmlinuz-linux \
    arch/boot/x86_64/initramfs-linux.img \
    loader/entries/01-archiso-linux.conf

entry="$tmp/loader/entries/01-archiso-linux.conf"
uuid="$(sed -n 's/.*archisosearchuuid=\([^ ]*\).*/\1/p' "$entry" | head -1)"
basedir="$(sed -n 's/.*archisobasedir=\([^ ]*\).*/\1/p' "$entry" | head -1)"
[[ -n "$uuid" ]] || die "could not parse archisosearchuuid from $entry"

accel=(-machine q35,accel=tcg -cpu max)
if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    accel=(-machine q35,accel=kvm -cpu host)
fi

append="archisobasedir=${basedir:-arch} archisosearchuuid=${uuid} cow_spacesize=5G"
append+=" console=ttyS0,115200 quiet splash vt.global_cursor_default=0"
append+=" plymouth.ignore-serial-consoles zone.splash=zone-mark video=1280x800"
append+=" systemd.log_level=info systemd.show_status=1"

info "booting $(basename "$ISO")"
qemu-img create -q -f qcow2 "$tmp/disk.qcow2" 24G
qemu-system-x86_64 "${accel[@]}" -smp "$CPUS" -m "$MEM" \
    -kernel "$tmp/arch/boot/x86_64/vmlinuz-linux" \
    -initrd "$tmp/arch/boot/x86_64/initramfs-linux.img" \
    -append "$append" \
    -cdrom "$ISO" \
    -drive "file=$tmp/disk.qcow2,if=virtio,format=qcow2" \
    -display none -vga std \
    -nic user,model=virtio-net-pci \
    -device qemu-xhci -device usb-tablet \
    -serial "file:$tmp/serial.log" \
    -qmp "unix:$tmp/qmp.sock,server=on,wait=off" \
    -snapshot >"$tmp/qemu.log" 2>&1 &
qemu_pid=$!

for _ in {1..100}; do [[ -S "$tmp/qmp.sock" ]] && break; sleep 0.1; done
[[ -S "$tmp/qmp.sock" ]] || die "QMP socket did not appear"
sleep 1

qmp() { python3 "$QMP" --socket "$tmp/qmp.sock" "$@"; }

wait_for() {
    local pattern="$1" timeout="${2:-120}" i
    for ((i = 0; i < timeout * 2; i++)); do
        grep -qaE "$pattern" "$tmp/serial.log" && return 0
        sleep 0.5
    done
    return 1
}

info "capturing the boot splash"
for i in $(seq -w 1 16); do
    sleep 1
    qmp screendump "$tmp/splash/${i}.png" || true
done

last="$(find "$tmp/splash" -name '*.png' | sort | tail -1)"
[[ -n "$last" ]] || die "no splash frames were captured"
read -r width height < <(qmp size "$last")
info "guest display: ${width}x${height}"

info "waiting for the graphical session"
wait_for 'lightdm|Reached target Graphical' 60 \
    || warn "timed out waiting for the display manager"
sleep 30

open_terminal() {
    qmp key meta_l ret
    sleep 4
}

# The live session autologins, so keep the screen from blanking during capture.
open_terminal
qmp type "xset s off -dpms; pkill -x xfce4-screensaver"
qmp key ret
sleep 1
qmp type exit
qmp key ret
sleep 2

info "capturing the desktop"
qmp screendump "$tmp/out/desktop.png"

info "capturing a terminal with neofetch"
open_terminal
qmp move "$((width - 20))" "$((height - 20))" "$width" "$height"
sleep 1
qmp screendump "$tmp/out/terminal.png"

info "capturing the installer"
qmp type "setsid sudo calamares >/dev/null 2>&1 &"
qmp key ret
sleep 1
qmp type exit
qmp key ret
sleep 25
qmp screendump "$tmp/out/installer.png"

info "capturing the application finder"
open_terminal
qmp type "sudo pkill -f calamares"
qmp key ret
sleep 2
qmp type xfce4-appfinder
qmp key ret
sleep 6
qmp move "$((width - 20))" "$((height - 20))" "$width" "$height"
sleep 1
qmp screendump "$tmp/out/menu.png"

info "capturing the greeter (logout)"
qmp key ctrl alt delete
sleep 2
qmp click "$((width * 421 / 1000))" "$((height * 475 / 1000))" "$width" "$height"
mkdir -p "$tmp/greeter-logout"
for i in $(seq -w 1 40); do
    qmp screendump "$tmp/greeter-logout/${i}.png" || true
    sleep 0.3
done

qmp quit || true
wait "$qemu_pid" 2>/dev/null || true
qemu_pid=""

python3 "$QMP" --socket "$tmp/qmp.sock" pick splash "$tmp/splash" "$tmp/out/splash.png"
python3 "$QMP" --socket "$tmp/qmp.sock" pick greeter "$tmp/greeter-logout" "$tmp/out/greeter.png"

install -m644 "$tmp/out/"*.png "$OUT/"
info "screenshots written to $OUT"
