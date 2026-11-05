#!/usr/bin/env python3
"""Lighter Forza Horizon 2 render settings for the Retroid Pocket 6.

FH2 reads its quality settings from small XML files in media/RenderScenarios
(Global.xml plus one file per situation). This copies them from your own game
folder, lowers the car, crowd, mirror and reflection settings and writes the
result as an Extra Options mod (github.com/RokkuDayo/ForzaHorizon2_ExtraOptions),
which loads it instead of the originals. The game files stay untouched.

    python3 fh2-lowspec.py AZIMUTH_DIR [GAME_DIR]     install or update the mod
    python3 fh2-lowspec.py AZIMUTH_DIR --remove       delete it again

AZIMUTH_DIR holds azimuth.exe and Extra Options' winmm.dll. GAME_DIR holds
forza_durango_release_final.exe; without it the script looks for it below
AZIMUTH_DIR and ~/Games.
"""
import re
import shutil
import sys
import zipfile
from pathlib import Path

MOD = "rp6-lowspec"
GAME_EXE = "forza_durango_release_final.exe"

# file -> tag -> attribute -> value
CHANGES = {
    "Global.xml": {
        "ShadowMapResolution": {"value": "256"},
        "MaxHiDefShadows": {"value": "0"},
        "CollidableShadows": {"value": "0"},
        "MotionBlur": {"value": "0"},
        "CarLODTransDist": {"near": "8.0", "far": "12.0", "veryfar": "25.0", "farthest": "40.0"},
        "CarMinWheelLOD": {"value": "1"},
        "CarDigitalGaugeFrequency": {"value": "6"},
        "CarAICubemap": {"value": "0"},
        "CarMaxDropParts": {"value": "0"},
        "CollidablesInMirror": {"value": "0"},
        "CrowdDraw": {"value": "0"},
        "CrowdDrawMirror": {"value": "0"},
        "CrowdDrawShadows": {"value": "0"},
        "ParticleRateScale": {"value": "0.25"},
        "EnvMapFrequencyScale": {"value": "0"},
        "MaxCarsInMirror": {"value": "4"},
        "HalfRateMirror": {"value": "1"},
        "HalfRateBloom": {"value": "1"},
        "SoftParticles": {"value": "0"},
        "EnableWindshieldReflections": {"value": "0"},
    },
    # These two raise the reflection refresh again on top of Global.xml.
    "TrackContent.xml": {"EnvMapFrequencyScale": {"value": "0"}},
    "CarMeet.xml": {"EnvMapFrequencyScale": {"value": "0"}},
}
# Tried and dropped: CrowdLoad 0 (menus crawl, no throttle), AI car LOD,
# car shader LOD bias, track particles - no gain over the above.


def find_game(azimuth: Path) -> Path:
    for root in (azimuth, Path.home() / "Games"):
        for depth in range(4):
            for exe in root.glob("/".join(["*"] * depth + [GAME_EXE])):
                return exe.parent
    sys.exit(f"error: {GAME_EXE} not found below {azimuth} or ~/Games, pass GAME_DIR")


def child(folder: Path, name: str) -> Path | None:
    for entry in folder.iterdir() if folder.is_dir() else ():
        if entry.name.lower() == name.lower():
            return entry
    return None


def read_originals(game: Path) -> dict[str, bytes]:
    media = child(game, "media")
    if media is None:
        sys.exit(f"error: no media folder in {game}")
    folder = child(media, "RenderScenarios")
    if folder is not None and folder.is_dir():
        files = {p.name.lower(): p.read_bytes() for p in folder.iterdir() if p.is_file()}
    else:
        archive = child(media, "RenderScenarios.zip")
        if archive is None:
            sys.exit(f"error: no RenderScenarios folder or zip in {media}")
        with zipfile.ZipFile(archive) as z:
            files = {Path(n).name.lower(): z.read(n) for n in z.namelist() if not n.endswith("/")}
    return files


def apply(name: str, text: str, changes: dict[str, dict[str, str]]) -> str:
    newline = "\r\n" if "\r\n" in text else "\n"
    for tag, attrs in changes.items():
        if re.search(rf"<{tag}\b", text):
            for attr, value in attrs.items():
                text, n = re.subn(rf'(<{tag}\b[^>]*\b{attr}=")[^"]*(")', rf"\g<1>{value}\2", text)
                if n != 1:
                    sys.exit(f"error: {name}: {tag} has no single {attr}, not writing the mod")
        else:
            line = f"<{tag} " + " ".join(f'{a}="{v}"' for a, v in attrs.items()) + "/>"
            text = text.replace("</DynamicRenderSettings>", f"  {line}{newline}</DynamicRenderSettings>")
    return text


def main(argv: list[str]) -> int:
    if len(argv) not in (2, 3):
        print(__doc__, file=sys.stderr)
        return 2
    azimuth = Path(argv[1]).expanduser()
    target = azimuth / "mods" / MOD
    if len(argv) == 3 and argv[2] == "--remove":
        shutil.rmtree(target, ignore_errors=True)
        print(f"Removed {target}")
        return 0
    if not (azimuth / "azimuth.exe").is_file():
        sys.exit(f"error: no azimuth.exe in {azimuth}")
    if not (azimuth / "winmm.dll").is_file():
        print("warning: winmm.dll is missing, install Extra Options or the mod won't load", file=sys.stderr)
    game = Path(argv[2]).expanduser() if len(argv) == 3 else find_game(azimuth)
    originals = read_originals(game)
    out = target / "media" / "RenderScenarios"
    shutil.rmtree(target, ignore_errors=True)
    out.mkdir(parents=True)
    for name, changes in CHANGES.items():
        data = originals.get(name.lower())
        if data is None:
            sys.exit(f"error: {name} is missing from the game's RenderScenarios")
        text = apply(name, data.decode("utf-8"), changes)
        (out / name).write_bytes(text.encode("utf-8"))
    print(f"Wrote {target} from {game}. Extra Options picks it up on the next start.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
