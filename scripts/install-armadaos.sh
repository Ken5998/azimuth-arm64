#!/usr/bin/env bash
# Installs the Azimuth Turnip driver on ArmadaOS: the latest release (or the
# version given) into ~/.local/share/armada/turnip/azimuth, with the Vulkan
# manifest that points Azimuth at it, then prints the Steam launch options.
#
# Usage: install-armadaos.sh [VERSION] [--test]
set -euo pipefail

repo=Ken5998/azimuth-arm64
version="" test=0
for arg in "$@"; do
  case "$arg" in
    --test) test=1 ;;
    *) version="${arg#v}" ;;
  esac
done
if [ -z "$version" ]; then
  version="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))')"
fi

turnip="$HOME/.local/share/armada/turnip"
dest="$turnip/azimuth"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading azimuth-turnip $version"
curl -fL --retry 3 -o "$tmp/driver.tar.gz" \
  "https://github.com/$repo/releases/download/v$version/azimuth-turnip-$version.tar.gz"
tar -xzf "$tmp/driver.tar.gz" -C "$tmp"

mkdir -p "$dest"
install -m 0755 "$tmp/azimuth/libvulkan_freedreno.so" "$dest/libvulkan_freedreno.so"
install -m 0644 "$tmp/azimuth/meta.json" "$dest/meta.json"
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
echo "Installed in $dest"

if [ "$test" = 1 ]; then
  echo "Testing host memory import:"
  VK_DRIVER_FILES="$dest/icd.json" VK_ICD_FILENAMES="$dest/icd.json" "$dest/azimuth-hosttest"
fi

cat <<TEXT

In Steam, Azimuth > Properties:
  Compatibility: Proton Experimental (arm64)
  Launch options:
    VK_DRIVER_FILES=$dest/icd.json VK_ICD_FILENAMES=$dest/icd.json %command%

In Azimuth's launcher, set Frame pacing to Real-time.
TEXT
