#!/bin/bash
set -euo pipefail

PROFILE="$(pwd)/archiso"
OUT="$(pwd)/zone-out"
mkdir -p "$OUT"

docker build -t zone-builder -f docker/Dockerfile .
docker run --rm --privileged \
    -v "$PROFILE":/build/archiso:ro \
    -v "$OUT":/build/out \
    zone-builder \
    mkarchiso -v -w /tmp/zone-work -o /build/out /build/archiso
