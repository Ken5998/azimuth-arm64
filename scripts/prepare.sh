#!/usr/bin/env bash
# Downloads Mesa at the commit in upstream.json, applies ArmadaOS's base
# patches for its Turnip "Devel" driver, then this repository's patches.
#
# Usage: scripts/prepare.sh WORKDIR   (the source ends up in WORKDIR/mesa)
#
# MESA_COMMIT=<sha> builds another Mesa commit instead of the pinned one (for
# test builds on newer Mesa); Armada base patches that no longer apply there
# are then skipped with a warning, since upstream may have taken them over.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"
pin() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(eval("d" + sys.argv[2]))' "$root/upstream.json" "$1"; }

archive="$work/mesa.tar.gz"
if [ -n "${MESA_COMMIT:-}" ]; then
  echo "Mesa: test build on $MESA_COMMIT"
  curl --fail --location --retry 3 -o "$archive" \
    "https://gitlab.freedesktop.org/mesa/mesa/-/archive/$MESA_COMMIT/mesa-$MESA_COMMIT.tar.gz"
  sha256sum "$archive"
else
  url="$(pin '["mesa"]["url"]')"
  sha256="$(pin '["mesa"]["sha256"]')"
  if ! echo "$sha256  $archive" | sha256sum --check --status 2>/dev/null; then
    curl --fail --location --retry 3 -o "$archive" "$url"
    echo "$sha256  $archive" | sha256sum --check --strict
  fi
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
  if [ -n "${MESA_COMMIT:-}" ] &&
     ! patch -d "$work/mesa" -p1 --forward --batch --quiet --dry-run < "$out" >/dev/null; then
    echo "Armada: ${path##*/} does not apply on $MESA_COMMIT, skipped"
    rm "$out"
    continue
  fi
  echo "Armada: ${path##*/}"
  patch -d "$work/mesa" -p1 --forward --batch --quiet < "$out"
done

for p in "$root"/patches/*.patch; do
  echo "Patch: ${p##*/}"
  if ! patch -d "$work/mesa" -p1 --forward --batch < "$p"; then
    find "$work/mesa" -name '*.rej' -exec sh -c 'echo "== $1"; cat "$1"' _ {} \;
    exit 1
  fi
done
