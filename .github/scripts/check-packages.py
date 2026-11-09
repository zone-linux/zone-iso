#!/usr/bin/env python3
"""Validate zone-iso/archiso/packages.x86_64 for CI.

Official packages are checked with pacman, AUR-only packages with the AUR RPC,
and Zone's own packages are allowed by name prefix.
"""

from __future__ import annotations

import concurrent.futures
import json
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGES = ROOT / "archiso" / "packages.x86_64"
AUR_RPC = "https://aur.archlinux.org/rpc/v5/info"
LOCAL_PREFIXES = ("zone-", "stalker-")


def read_packages() -> list[str]:
    packages: list[str] = []
    for line in PACKAGES.read_text(encoding="utf-8").splitlines():
        value = line.split("#", 1)[0].strip()
        if value:
            packages.append(value)
    return packages


def is_official(name: str) -> bool:
    for args in (["pacman", "-Si", name], ["pacman", "-Sg", name]):
        result = subprocess.run(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            return True
    return False


def main() -> int:
    packages = read_packages()
    if not packages:
        print("packages.x86_64 is empty", file=sys.stderr)
        return 1

    duplicates = sorted({name for name in packages if packages.count(name) > 1})
    if duplicates:
        print("duplicate package entries:", file=sys.stderr)
        for name in duplicates:
            print(f"  - {name}", file=sys.stderr)
        return 1

    unresolved: list[str] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = pool.map(is_official, packages)
        for name, official in zip(packages, results):
            if not official and not name.startswith(LOCAL_PREFIXES):
                unresolved.append(name)

    if unresolved:
        query = "&".join(
            urllib.parse.urlencode({"arg[]": name}) for name in unresolved
        )
        try:
            with urllib.request.urlopen(f"{AUR_RPC}?{query}", timeout=30) as response:
                doc = json.load(response)
            found = {entry["Name"] for entry in doc.get("results", [])}
        except Exception as exc:  # noqa: BLE001 - report the network error
            print(f"could not query the AUR: {exc}", file=sys.stderr)
            return 1
        unresolved = [name for name in unresolved if name not in found]

    if unresolved:
        print("packages not found in the Arch repos or the AUR:", file=sys.stderr)
        for name in unresolved:
            print(f"  - {name}", file=sys.stderr)
        return 1

    print(f"Validated {len(packages)} ISO package entries")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
