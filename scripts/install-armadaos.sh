#!/usr/bin/env bash
# Installs the Azimuth Turnip driver on ArmadaOS: the latest release (or the
# version given) into ~/.local/share/armada/turnip/azimuth, with the Vulkan
# manifest that points Azimuth at it, then prints the Steam launch options.
# --file installs a package downloaded from a CI run instead (the .zip from
# the run's page or the .tar.gz in it); a Mesa main test build lands in
# ~/.local/share/armada/turnip/azimuth-next, next to the release driver.
#
# Usage: install-armadaos.sh [VERSION] [--test] [--file PACKAGE]
set -euo pipefail

repo=Ken5998/azimuth-arm64
version="" test=0 file=""
while [ $# -gt 0 ]; do
  case "$1" in
    --test) test=1 ;;
    --file) file="$(realpath "$2")"; shift ;;
    *) version="${1#v}" ;;
  esac
  shift
done
if [ -z "$version" ] && [ -z "$file" ]; then
  version="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
fi

turnip="$HOME/.local/share/armada/turnip"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "$file" ]; then
  case "$file" in
    *.zip) python3 -m zipfile -e "$file" "$tmp/zip"; cp "$tmp"/zip/*.tar.gz "$tmp/driver.tar.gz" ;;
    *) cp "$file" "$tmp/driver.tar.gz" ;;
  esac
else
  echo "Downloading azimuth-turnip $version"
  curl -fL --retry 3 -o "$tmp/driver.tar.gz" \
    "https://github.com/$repo/releases/download/v$version/azimuth-turnip-$version.tar.gz"
fi
tar -xzf "$tmp/driver.tar.gz" -C "$tmp"
folder="$(basename "$(dirname "$(ls "$tmp"/azimuth*/libvulkan_freedreno.so)")")"
dest="$turnip/$folder"

mkdir -p "$dest"
install -m 0755 "$tmp/$folder/libvulkan_freedreno.so" "$dest/libvulkan_freedreno.so"
install -m 0644 "$tmp/$folder/meta.json" "$dest/meta.json"
install -m 0755 "$tmp/azimuth-hosttest" "$dest/azimuth-hosttest"
cat > "$dest/icd.json" <<JSON
{
  "file_format_version": "1.0.1",
  "ICD": {
    "library_path": "$dest/libvulkan_freedreno.so",
    "api_version": "1.4.0"
  }
}
JSON
echo "Installed $(cat "$dest/meta.json") in $dest"

if [ "$test" = 1 ]; then
  echo "Testing host memory import:"
  VK_DRIVER_FILES="$dest/icd.json" VK_ICD_FILENAMES="$dest/icd.json" "$dest/azimuth-hosttest"
fi

cat <<TEXT

Azimuth 1.0 needs Microsoft's D3DCompiler_47 in its prefix
(the App ID is the one protontricks -l shows for the shortcut):
  protontricks <APPID> d3dcompiler_47

In Steam, Azimuth > Properties:
  Compatibility: Proton Experimental (arm64)
  Launch options:
    WINEDLLOVERRIDES="d3dcompiler_47=n;vcruntime140,vcruntime140_1,msvcp140,concrt140,msvcp110,msvcr110=n" VK_DRIVER_FILES=$dest/icd.json VK_ICD_FILENAMES=$dest/icd.json %command%

On Azimuth 0.9.x, set Frame pacing to Real-time in its launcher.
TEXT
