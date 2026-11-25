#!/usr/bin/env python3
"""Minimal QMP client and frame helpers for capture-screenshots.sh.

Subcommands:
  screendump PATH            write a PNG of the guest display
  key KEY [KEY...]           send keys (e.g. key meta ret)
  type TEXT                  type a string one key at a time
  click X Y WIDTH HEIGHT     click at guest coordinates
  size PATH                  print "WIDTH HEIGHT" of a PNG
  pick MODE DIR OUT          choose the best frame from a burst directory
  quit                       shut the VM down
"""

from __future__ import annotations

import argparse
import json
import shutil
import socket
import time
from pathlib import Path

ABS_MAX = 0x7FFF

try:
    from PIL import Image
except ImportError:  # pragma: no cover - fallback for hosts without Pillow
    Image = None

CHAR_KEYS = {
    " ": "spc",
    "-": "minus",
    "=": "equal",
    ".": "dot",
    ",": "comma",
    "/": "slash",
    ";": "semicolon",
    "'": "apostrophe",
    "`": "grave_accent",
    "[": "bracket_left",
    "]": "bracket_right",
    "\\": "backslash",
    "_": "shift+minus",
    "+": "shift+equal",
    ":": "shift+semicolon",
    "\"": "shift+apostrophe",
    "~": "shift+grave_accent",
    "{": "shift+bracket_left",
    "}": "shift+bracket_right",
    "|": "shift+backslash",
    "<": "shift+comma",
    ">": "shift+dot",
    "?": "shift+slash",
    "!": "shift+1",
    "@": "shift+2",
    "#": "shift+3",
    "$": "shift+4",
    "%": "shift+5",
    "^": "shift+6",
    "&": "shift+7",
    "*": "shift+8",
    "(": "shift+9",
    ")": "shift+0",
}


class QMP:
    def __init__(self, path: str, timeout: float = 30.0) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout)
        self.sock.connect(path)
        self.file = self.sock.makefile("rwb")
        self._read()
        self.execute("qmp_capabilities")

    def _read(self) -> dict:
        while True:
            line = self.file.readline()
            if not line:
                raise RuntimeError("QMP connection closed")
            message = json.loads(line)
            if "event" in message:
                continue
            return message

    def execute(self, command: str, **arguments: object) -> object:
        payload: dict[str, object] = {"execute": command}
        if arguments:
            payload["arguments"] = arguments
        self.file.write((json.dumps(payload) + "\n").encode())
        self.file.flush()
        message = self._read()
        if "error" in message:
            raise RuntimeError(message["error"].get("desc", "QMP error"))
        return message.get("return")

    def close(self) -> None:
        self.file.close()
        self.sock.close()


def key_events(values: list[str]) -> list[dict]:
    events = []
    for value in values:
        for part in value.split("+"):
            events.append({"type": "qcode", "data": CHAR_KEYS.get(part, part)})
    return events


def text_events(text: str) -> list[list[dict]]:
    chunks = []
    for char in text:
        if char.isalpha() and char.isupper():
            chunks.append([{"type": "qcode", "data": "shift"},
                           {"type": "qcode", "data": char.lower()}])
        elif char in CHAR_KEYS:
            mapped = CHAR_KEYS[char]
            if mapped.startswith("shift+"):
                chunks.append([{"type": "qcode", "data": "shift"},
                               {"type": "qcode", "data": mapped.split("+", 1)[1]}])
            else:
                chunks.append([{"type": "qcode", "data": mapped}])
        elif char.isalnum():
            chunks.append([{"type": "qcode", "data": char.lower()}])
        else:
            raise SystemExit(f"unsupported character: {char!r}")
    return chunks


def image_score(path: Path, mode: str) -> float:
    with Image.open(path) as handle:
        raw = handle.convert("RGB").resize((160, 90)).tobytes()
    pixels = [(raw[i], raw[i + 1], raw[i + 2]) for i in range(0, len(raw), 3)]
    if mode == "splash":
        orange = sum(1 for r, g, b in pixels if r > 140 and 50 < g < 180 and b < 100)
        lit = sum(1 for r, g, b in pixels if r + g + b > 90)
        return orange * 3.0 + lit
    return float(sum(1 for r, g, b in pixels if r + g + b > 60))


def pick(mode: str, directory: Path, out: Path) -> None:
    frames = sorted(directory.glob("*.png"))
    if not frames:
        raise SystemExit(f"no frames in {directory}")

    if Image is None:
        best = max(frames, key=lambda path: path.stat().st_size)
    elif mode == "splash":
        best = max(frames, key=lambda path: image_score(path, "splash"))
    else:
        scores = [(image_score(path, "greeter"), path) for path in frames]
        lit = [item for item in scores if item[0] > 0.35 * 160 * 90]
        best = lit[-1][1] if lit else max(scores)[1]

    out.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(best, out)
    print(f"{mode}: {best.name} -> {out}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True, help="QMP unix socket path")
    sub = parser.add_subparsers(dest="command", required=True)

    dump = sub.add_parser("screendump")
    dump.add_argument("path")

    key = sub.add_parser("key")
    key.add_argument("keys", nargs="+")

    typed = sub.add_parser("type")
    typed.add_argument("text")

    click = sub.add_parser("click")
    click.add_argument("x", type=int)
    click.add_argument("y", type=int)
    click.add_argument("width", type=int)
    click.add_argument("height", type=int)
    click.add_argument("--button", default="left",
                       choices=("left", "middle", "right"))
    click.add_argument("--count", type=int, default=1)

    size = sub.add_parser("size")
    size.add_argument("path")

    move = sub.add_parser("move")
    move.add_argument("x", type=int)
    move.add_argument("y", type=int)
    move.add_argument("width", type=int)
    move.add_argument("height", type=int)

    choose = sub.add_parser("pick")
    choose.add_argument("mode", choices=("splash", "greeter"))
    choose.add_argument("directory")
    choose.add_argument("out")

    sub.add_parser("quit")

    args = parser.parse_args()

    if args.command == "pick":
        pick(args.mode, Path(args.directory), Path(args.out))
        return

    if args.command == "size":
        if Image is None:
            raise SystemExit("Pillow is required for the size command")
        with Image.open(args.path) as handle:
            print(handle.width, handle.height)
        return

    client = QMP(args.socket)
    try:
        if args.command == "screendump":
            client.execute("screendump", filename=args.path, format="png")
        elif args.command == "key":
            client.execute("send-key", keys=key_events(args.keys))
        elif args.command == "type":
            for chunk in text_events(args.text):
                client.execute("send-key", keys=chunk)
                time.sleep(0.04)
        elif args.command == "click":
            move = [
                {"type": "abs", "data": {"axis": "x",
                                         "value": args.x * ABS_MAX // max(args.width - 1, 1)}},
                {"type": "abs", "data": {"axis": "y",
                                         "value": args.y * ABS_MAX // max(args.height - 1, 1)}},
            ]
            client.execute("input-send-event", events=move)
            time.sleep(0.1)
            for _ in range(args.count):
                client.execute("input-send-event",
                               events=[{"type": "btn", "data": {"down": True,
                                                                "button": args.button}}])
                time.sleep(0.05)
                client.execute("input-send-event",
                               events=[{"type": "btn", "data": {"down": False,
                                                                "button": args.button}}])
                time.sleep(0.05)
        elif args.command == "move":
            client.execute("input-send-event", events=[
                {"type": "abs", "data": {"axis": "x",
                                         "value": args.x * ABS_MAX // max(args.width - 1, 1)}},
                {"type": "abs", "data": {"axis": "y",
                                         "value": args.y * ABS_MAX // max(args.height - 1, 1)}},
            ])
        elif args.command == "quit":
            client.execute("quit")
    finally:
        client.close()


if __name__ == "__main__":
    main()
