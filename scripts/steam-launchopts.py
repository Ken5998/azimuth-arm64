#!/usr/bin/env python3
"""Reads or sets the launch options of a non-Steam game (shortcut) in Steam.

    python3 steam-launchopts.py list
    python3 steam-launchopts.py get NAME
    python3 steam-launchopts.py set NAME OPTIONS...
    python3 steam-launchopts.py set NAME --stdin <<'EOF'
    VAR=value ... %command%
    EOF
    python3 steam-launchopts.py clear NAME

NAME matches the shortcut's name without regard to case. The change goes to
every Steam account on this machine that has that shortcut; the old
shortcuts.vdf is kept next to it as shortcuts.vdf.launchopts-backup.

Steam keeps the library in memory and writes it back when it closes, so a
running Steam is closed first and started again afterwards. Needs only
Python's standard library.
"""
import os
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

# shortcuts.vdf is Steam's binary KeyValues format.
MAP, STRING, INT32, END = 0x00, 0x01, 0x02, 0x08


def read_string(data: bytes, at: int) -> tuple[str, int]:
    end = data.index(b"\0", at)
    return data[at:end].decode("utf-8", errors="surrogateescape"), end + 1


def parse_vdf(data: bytes, at: int = 0) -> tuple[dict, int]:
    result: dict = {}
    while at < len(data):
        kind = data[at]
        at += 1
        if kind == END:
            return result, at
        key, at = read_string(data, at)
        if kind == MAP:
            result[key], at = parse_vdf(data, at)
        elif kind == STRING:
            result[key], at = read_string(data, at)
        elif kind == INT32:
            result[key] = struct.unpack_from("<i", data, at)[0]
            at += 4
        else:
            raise ValueError(f"unknown field type {kind} in shortcuts.vdf")
    return result, at


def dump_vdf(value: dict) -> bytes:
    out = bytearray()
    for key, item in value.items():
        name = key.encode("utf-8", errors="surrogateescape") + b"\0"
        if isinstance(item, dict):
            out += bytes([MAP]) + name + dump_vdf(item)
        elif isinstance(item, int):
            out += bytes([INT32]) + name + struct.pack("<i", item)
        else:
            out += bytes([STRING]) + name + str(item).encode("utf-8", errors="surrogateescape") + b"\0"
    return bytes(out) + bytes([END])


def steam_roots(home: Path) -> list[Path]:
    roots: list[Path] = []
    for candidate in (home / ".local/share/Steam", home / ".steam/steam",
                      home / ".var/app/com.valvesoftware.Steam/.local/share/Steam"):
        if (candidate / "userdata").is_dir() and all(candidate.resolve() != r.resolve() for r in roots):
            roots.append(candidate)
    return roots


def steam_running() -> bool:
    """Whether a Steam client process of this user runs: ArmadaOS's ARM64
    client (steamrtarm64/steam), the x86 one under FEX (ubuntu12_32/steam) or
    its helpers. Told by the executable rather than the command line, which
    can be relative (./steam) after Steam restarts itself: a Steam that was
    missed keeps its own copy of the library and writes it back later,
    without the game."""
    names = {"steam", "steamwebhelper", "steamservice"}
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            exe = os.readlink(proc / "exe").removesuffix(" (deleted)")
            command = (proc / "cmdline").read_bytes().split(b"\0")[:2]
        except OSError:
            continue
        if Path(exe).name in names:
            return True
        # FEX runs the x86 client: the executable is FEX, the client is in argv.
        if any(part.endswith((b"/steamrtarm64/steam", b"/ubuntu12_32/steam")) for part in command):
            return True
    return False


def close_steam() -> bool:
    """Closes a running Steam; True when it was running."""
    if not steam_running():
        return False
    if not shutil.which("steam"):
        sys.exit("error: Steam is running: close it and run this again")
    print("Closing Steam, so it keeps the change (it starts again afterwards)")
    subprocess.run(["steam", "-shutdown"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.monotonic() + 90
    while steam_running():
        if time.monotonic() > deadline:
            sys.exit("error: Steam did not close: close it and run this again")
        time.sleep(1)
    return True


def field(entry: dict, key: str):
    """A field of a shortcut, whatever case Steam wrote its key in."""
    for k, v in entry.items():
        if k.lower() == key.lower():
            return v
    return None


def accounts_configs(home: Path) -> list[Path]:
    """The config folders of the accounts that signed in (not the anonymous 0)."""
    return [user / "config" for root in steam_roots(home) for user in sorted((root / "userdata").iterdir())
            if user.is_dir() and user.name.isdigit() and user.name != "0"]


def shortcut_files(home: Path) -> list[Path]:
    return [c / "shortcuts.vdf" for c in accounts_configs(home)
            if (c / "shortcuts.vdf").is_file() and (c / "shortcuts.vdf").stat().st_size]


def load(path: Path) -> dict:
    return parse_vdf(path.read_bytes())[0].get("shortcuts", {})


def matching(shortcuts: dict, name: str) -> list[dict]:
    return [e for e in shortcuts.values() if str(field(e, "AppName") or "").lower() == name.lower()]


def show(home: Path, name: str | None) -> int:
    found = 0
    for path in shortcut_files(home):
        for entry in load(path).values():
            app = str(field(entry, "AppName") or "")
            if name is None or app.lower() == name.lower():
                appid = (field(entry, "appid") or 0) & 0xFFFFFFFF
                print(f"{app} (App ID {appid}): {field(entry, 'LaunchOptions') or ''}")
                found += 1
    if name is not None and not found:
        sys.exit(f"error: no shortcut named {name!r} (see: list)")
    return 0


def write(home: Path, name: str, options: str) -> int:
    files = [p for p in shortcut_files(home) if matching(load(p), name)]
    if not files:
        sys.exit(f"error: no shortcut named {name!r} (see: list)")
    restart = close_steam()
    try:
        for path in files:
            shortcuts = load(path)
            for entry in matching(shortcuts, name):
                key = next((k for k in entry if k.lower() == "launchoptions"), "LaunchOptions")
                entry[key] = options
            backup = path.with_name("shortcuts.vdf.launchopts-backup")
            shutil.copyfile(path, backup)
            temporary = path.with_name("shortcuts.vdf.tmp")
            temporary.write_bytes(dump_vdf({"shortcuts": shortcuts}))
            temporary.replace(path)
    finally:
        if restart:
            subprocess.Popen(["steam"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
    print(f"{name}: {options or '(no launch options)'}")
    return 0


def main(argv: list[str]) -> int:
    home = Path.home()
    if not steam_roots(home):
        sys.exit("error: Steam is not set up for this user")
    if argv[1:2] == ["list"] and len(argv) == 2:
        return show(home, None)
    if argv[1:2] == ["get"] and len(argv) == 3:
        return show(home, argv[2])
    if argv[1:2] == ["clear"] and len(argv) == 3:
        return write(home, argv[2], "")
    if argv[1:2] == ["set"] and len(argv) >= 4:
        if argv[3:] == ["--stdin"]:
            options = " ".join(line.strip() for line in sys.stdin.read().splitlines() if line.strip())
        else:
            options = " ".join(argv[3:]).strip()
        return write(home, argv[2], options)
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
