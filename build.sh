#!/usr/bin/env bash
# zone-iso/build.sh — build the Zone Linux ISO.
#
# Examples:
#   ./build.sh                     # Docker build (recommended)
#   ./build.sh --native            # native mkarchiso (needs root)
#   ./build.sh --local-repos       # use the workspace repos instead of GitHub Pages
#   ./build.sh --clean             # remove the work directory first
#
# Run ./build.sh --help for every option.

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZONE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PROFILE="${SCRIPT_DIR}/archiso"
OUT_DIR="${SCRIPT_DIR}/zone-out"
WORK_DIR="${SCRIPT_DIR}/zone-work"
MODE="docker"
LOCAL_REPOS=0
CLEAN=0
NO_CACHE=0
SKIP_IMAGE=0

if [[ -t 2 ]]; then
    CYN=$'\e[36m'; YEL=$'\e[33m'; RED=$'\e[31m'; GRN=$'\e[32m'
    DIM=$'\e[2m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
    CYN='' YEL='' RED='' GRN='' DIM='' BLD='' RST=''
fi
info()  { printf '%s==> %s%s\n' "$CYN$BLD" "$*" "$RST" >&2; }
ok()    { printf '%s ok %s%s\n' "$GRN" "$*" "$RST" >&2; }
warn()  { printf '%s !  %s%s\n' "$YEL" "$*" "$RST" >&2; }
die()   { printf '%sERR %s%s\n' "$RED" "$*" "$RST" >&2; exit 1; }
note()  { printf '%s    %s%s\n' "$DIM" "$*" "$RST" >&2; }

usage() {
    cat <<'EOF'
Usage: ./build.sh [OPTIONS]

Options:
  --docker          Build inside Docker (default)
  --native          Build with the host's mkarchiso (requires root)
  --local-repos     Use the workspace zone-*-repo checkouts as package sources
  --remote-repos    Use the repositories configured in archiso/pacman.conf
  --profile DIR     archiso profile directory (default: ./archiso)
  --output DIR      ISO output directory (default: ./zone-out)
  --work DIR        Temporary work directory (default: ./zone-work)
  --clean           Remove the work directory before building
  --no-cache        Rebuild the Docker image without cache
  --skip-image      Reuse an existing zone-builder image
  -h, --help        Show this help
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --docker)       MODE="docker" ;;
        --native)       MODE="native" ;;
        --local-repos)  LOCAL_REPOS=1 ;;
        --remote-repos) LOCAL_REPOS=0 ;;
        --profile)      PROFILE="${2:?--profile needs a directory}"; shift ;;
        --output)       OUT_DIR="${2:?--output needs a directory}"; shift ;;
        --work)         WORK_DIR="${2:?--work needs a directory}"; shift ;;
        --clean)        CLEAN=1 ;;
        --no-cache)     NO_CACHE=1 ;;
        --skip-image)   SKIP_IMAGE=1 ;;
        -h|--help)      usage; exit 0 ;;
        *)              die "unknown option: $1 (see --help)" ;;
    esac
    shift
done

[[ -d "$PROFILE" ]] || die "profile not found: $PROFILE"
[[ -f "$PROFILE/profiledef.sh" ]] || die "not an archiso profile: $PROFILE"

mkdir -p "$OUT_DIR" "$WORK_DIR"
if [[ $CLEAN -eq 1 ]]; then
    info "cleaning $WORK_DIR"
    if [[ "$MODE" == "docker" ]]; then
        # Build artefacts are root-owned; remove them from inside a container.
        docker run --rm -v "${WORK_DIR}:/work" archlinux:latest \
            sh -c 'rm -rf /work/* /work/.[!.]* /work/..?* 2>/dev/null || true'
    else
        rm -rf "${WORK_DIR:?}"/*
    fi
fi

# Build a pacman.conf that points the Zone repositories at local checkouts.
make_local_pacman_conf() {
    local prefix="$1" out="$2"
    local -A repos=(
        [zone-core-repo]="${ZONE_ROOT}/zone-core-repo"
        [zone-repo]="${ZONE_ROOT}/zone-repo"
        [zone-3party-repo]="${ZONE_ROOT}/zone-3party-repo"
    )
    cp "${PROFILE}/pacman.conf" "$out"
    local name
    for name in "${!repos[@]}"; do
        [[ -d "${repos[$name]}/x86_64" ]] || warn "local repo missing: ${repos[$name]}/x86_64"
        python3 - "$out" "$name" "$prefix/$name" <<'PY'
import sys, pathlib, re
path, name, server = sys.argv[1:4]
p = pathlib.Path(path)
s = p.read_text()
pat = re.compile(r'^\[%s\](.*?)(?=^\[|\Z)' % re.escape(name), re.M | re.S)
def rewrite(m):
    body = re.sub(r'(?:^Server\s*=.*\n?)+',
                  'Server = %s/$arch\n' % server, m.group(1), flags=re.M)
    return '[%s]%s' % (name, body)
s, n = pat.subn(rewrite, s)
if n == 0:
    raise SystemExit(f'could not rewrite repository: {name}')
p.write_text(s)
PY
    done
    [[ -f "$out" ]] || die "failed to create local pacman.conf"
}

TMP_CONF=""
cleanup() { if [[ -n "$TMP_CONF" ]]; then rm -f "$TMP_CONF"; fi; }
trap cleanup EXIT

if [[ "$MODE" == "native" ]]; then
    [[ $EUID -eq 0 ]] || die "--native requires root (mkarchiso mounts loop devices)"
    command -v mkarchiso >/dev/null || die "mkarchiso not installed"
    local_conf_args=()
    if [[ $LOCAL_REPOS -eq 1 ]]; then
        TMP_CONF="$(mktemp)"
        make_local_pacman_conf "file://${ZONE_ROOT}" "$TMP_CONF"
        local_conf_args=(-C "$TMP_CONF")
        info "using local repositories from $ZONE_ROOT"
    fi
    info "building ISO with native mkarchiso"
    mkarchiso -v -w "$WORK_DIR" -o "$OUT_DIR" "${local_conf_args[@]}" "$PROFILE"
else
    command -v docker >/dev/null || die "docker not found"
    docker info >/dev/null 2>&1 || die "docker daemon is not reachable"

    if [[ $SKIP_IMAGE -eq 0 ]]; then
        info "building zone-builder image"
        build_args=()
        [[ $NO_CACHE -eq 1 ]] && build_args+=(--no-cache)
        docker build "${build_args[@]}" -t zone-builder -f "${SCRIPT_DIR}/docker/Dockerfile" "$SCRIPT_DIR"
    fi

    mounts=(
        -v "${PROFILE}:/build/archiso:ro"
        -v "${OUT_DIR}:/build/out"
        -v "${WORK_DIR}:/build/work"
    )
    conf_args=()
    if [[ $LOCAL_REPOS -eq 1 ]]; then
        TMP_CONF="$(mktemp)"
        make_local_pacman_conf "file:///repo" "$TMP_CONF"
        mounts+=(-v "${TMP_CONF}:/build/pacman-local.conf:ro")
        mounts+=(-v "${ZONE_ROOT}:/repo:ro")
        conf_args=(-C /build/pacman-local.conf)
        info "using local repositories from $ZONE_ROOT"
    fi

    info "building ISO in Docker (work: $WORK_DIR)"
    docker run --rm --privileged \
        "${mounts[@]}" \
        zone-builder \
        mkarchiso -v -w /build/work -o /build/out "${conf_args[@]}" /build/archiso

    # mkarchiso runs as root inside the container; hand the output back.
    info "restoring ownership of $OUT_DIR"
    docker run --rm -v "${OUT_DIR}:/build/out" zone-builder \
        chown -R "$(id -u):$(id -g)" /build/out >/dev/null
fi

# Checksums + summary.
mapfile -t isos < <(find "$OUT_DIR" -maxdepth 1 -name '*.iso' -type f -printf '%T@ %p\n' | sort -n | cut -d' ' -f2-)
[[ ${#isos[@]} -gt 0 ]] || die "no ISO produced in $OUT_DIR"

for iso in "${isos[@]}"; do
    ( cd "$(dirname "$iso")" && sha256sum "$(basename "$iso")" > "$(basename "$iso").sha256" )
done

info "build complete"
for iso in "${isos[@]}"; do
    note "$iso"
    note "sha256: $(cut -d' ' -f1 "${iso}.sha256")"
done
