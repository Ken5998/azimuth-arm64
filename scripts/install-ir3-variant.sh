#!/usr/bin/env bash
# Install a local artifact from the IR3 square A/B workflow beside other drivers.
# Usage: scripts/install-ir3-variant.sh baseline|squares ARCHIVE.tar.gz
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 baseline|squares ARCHIVE.tar.gz" >&2
  exit 2
fi
variant="$1"
case "$variant" in
  baseline|squares) ;;
  *) echo "Variant must be baseline or squares" >&2; exit 2 ;;
esac
archive="$(realpath -- "$2")"
dest="$HOME/.local/share/armada/turnip/azimuth-ir3-$variant"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

tar -xzf "$archive" -C "$tmp" \
  azimuth/libvulkan_freedreno.so azimuth/meta.json azimuth/comparison.json azimuth-hosttest

# Check identity before installing so the two sides cannot be swapped silently.
python3 - "$tmp/azimuth" "$variant" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
metadata = json.loads((source / 'comparison.json').read_text())
if metadata['variant'] != sys.argv[2]:
    raise SystemExit('The archive variant does not match the requested variant.')
digest = hashlib.sha256((source / 'libvulkan_freedreno.so').read_bytes()).hexdigest()
if digest != metadata['driver_sha256']:
    raise SystemExit('The driver does not match its recorded SHA-256.')
PY

mkdir -p "$dest"
install -m 0755 "$tmp/azimuth/libvulkan_freedreno.so" "$dest/libvulkan_freedreno.so"
install -m 0755 "$tmp/azimuth-hosttest" "$dest/azimuth-hosttest"
install -m 0644 "$tmp/azimuth/meta.json" "$dest/meta.json"
install -m 0644 "$tmp/azimuth/comparison.json" "$dest/comparison.json"
python3 - "$dest" <<'PY'
import json
import sys
from pathlib import Path

dest = Path(sys.argv[1])
manifest = {
    'file_format_version': '1.0.1',
    'ICD': {'library_path': str(dest / 'libvulkan_freedreno.so'), 'api_version': '1.4.0'},
}
(dest / 'icd.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Installed {dest}')
print(f'Vulkan manifest: {dest / "icd.json"}')
PY
