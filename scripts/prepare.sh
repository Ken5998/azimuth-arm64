#!/usr/bin/env bash
# Downloads Mesa at the commit in upstream.json, applies ArmadaOS's base
# patches for its Turnip "Devel" driver, then this repository's patches.
#
# Usage: scripts/prepare.sh WORKDIR   (the source ends up in WORKDIR/mesa)
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"
pin() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval("d" + sys.argv[2]))' "$root/upstream.json" "$1"; }

url="$(pin '["mesa"]["url"]')"
sha256="$(pin '["mesa"]["sha256"]')"
archive="$work/mesa.tar.gz"
if ! echo "$sha256  $archive" | sha256sum --check --status 2>/dev/null; then
  curl --fail --location --retry 3 -o "$archive" "$url"
  echo "$sha256  $archive" | sha256sum --check --strict
fi

rm -rf "$work/mesa"
mkdir "$work/mesa"
tar -xzf "$archive" -C "$work/mesa" --strip-components=1

armada="$(pin '["armada"]["repository"]')"
armada_commit="$(pin '["armada"]["commit"]')"
mkdir -p "$work/armada-patches"
python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["armada"]["patches"]))' "$root/upstream.json" |
while read -r path; do
  out="$work/armada-patches/${path##*/}"
  curl --fail --location --retry 3 -o "$out" \
    "${armada/github.com/raw.githubusercontent.com}/$armada_commit/$path"
  echo "Armada: ${path##*/}"
  patch -d "$work/mesa" -p1 --forward --batch --quiet < "$out"
done

for p in "$root"/patches/*.patch; do
  echo "Patch: ${p##*/}"
  patch -d "$work/mesa" -p1 --forward --batch --quiet < "$p"
done
