#!/usr/bin/env bash
# Builds Mesa's fdperf (Adreno hardware counters) for aarch64 with a log mode
# that writes chosen counters as CSV, and packages it with its libconfig as
# OUTDIR/fdperf-aarch64.tar.gz. fdperf doesn't depend on the driver, so it is
# built from the Mesa release ArmadaOS ships.
#
# Usage: tools/fdperf/build.sh WORKDIR OUTDIR
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="$(mkdir -p "$1" && cd "$1" && pwd)"
out="$(mkdir -p "$2" && cd "$2" && pwd)"

# packages/mesa/BASE.env in armada-os/armada
url=https://archive.mesa3d.org/mesa-26.2.5.tar.xz
sha256=794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5

archive="$work/mesa-release.tar.xz"
if ! echo "$sha256  $archive" | sha256sum --check --status 2>/dev/null; then
  curl --fail --location --retry 3 -o "$archive" "$url"
  echo "$sha256  $archive" | sha256sum --check --strict
fi
src="$work/mesa-release"
rm -rf "$src"
mkdir "$src"
tar -xJf "$archive" -C "$src" --strip-components=1
for p in "$here"/*.patch; do
  echo "Patch: ${p##*/}"
  patch -d "$src" -p1 --forward --batch < "$p"
done

meson setup "$src/build" "$src" --buildtype release \
  -Dgallium-drivers= -Dvulkan-drivers= -Dtools=freedreno -Dfreedreno-kmds=msm \
  -Dplatforms= -Dglx=disabled -Degl=disabled -Dgbm=disabled -Dopengl=false \
  -Dllvm=disabled
ninja -C "$src/build" src/freedreno/perfcntrs/fdperf

pkg="$work/fdperf-pkg/fdperf"
rm -rf "$work/fdperf-pkg"
mkdir -p "$pkg"
strip -o "$pkg/fdperf" "$src/build/src/freedreno/perfcntrs/fdperf"
# ArmadaOS has ncurses but not libconfig: ship it beside the binary.
cp -L "$(ldconfig -p | awk '/libconfig\.so\.[0-9]+ .*aarch64/ {print $NF; exit}')" "$pkg/"
cp "$here/capture.sh" "$pkg/"
tar -czf "$out/fdperf-aarch64.tar.gz" -C "$work/fdperf-pkg" fdperf
sha256sum "$out/fdperf-aarch64.tar.gz"
