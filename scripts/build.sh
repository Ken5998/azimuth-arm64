#!/usr/bin/env bash
# Builds the patched Turnip for aarch64 the way ArmadaOS builds its own
# variants, and packages it as OUTDIR/azimuth-turnip-VERSION.tar.gz holding the
# folder azimuth/ (the driver and its label) and the azimuth-hosttest tool.
#
# Usage: scripts/build.sh WORKDIR OUTDIR   (run scripts/prepare.sh WORKDIR first)
#
# With MESA_COMMIT set (see prepare.sh) the driver is a test build: it goes in
# the folder azimuth-next/ of azimuth-turnip-next-VERSION.tar.gz with its own
# label, so it can sit next to the release driver for an A/B comparison.
set -euo pipefail
shopt -s nullglob

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(cd "$1" && pwd)"
out="$(mkdir -p "$2" && cd "$2" && pwd)"
version="$(cat "$root/VERSION")"
src="$work/mesa"

# ArmadaOS's Turnip flags (packages/mesa/build.sh in armada-os/armada).
march='-march=armv8.2-a+fp16+dotprod+i8mm -mtune=cortex-a78'
meson_args=(--buildtype release --prefix /usr
  -Dgallium-drivers= -Dvulkan-drivers=freedreno -Dfreedreno-kmds=msm
  -Dplatforms=x11,wayland -Dglx=disabled -Degl=disabled -Dgbm=disabled
  -Dopengl=false -Dllvm=disabled)

# Turnip keys its shader caches on the build id: derive it from the inputs, so
# the same release keeps users' caches and any change invalidates them.
build_id="$({
  echo "azimuth-arm64" "$march" "${meson_args[*]}"
  echo "${MESA_COMMIT:-}"
  cat "$root/upstream.json" "$work"/armada-patches/*.patch "$root"/patches/*.patch
} | sha256sum | cut -c1-40)"

rm -rf "$src/build"
CFLAGS="-O2 $march" CXXFLAGS="-O2 $march" \
  meson setup "$src/build" "$src" "${meson_args[@]}" -Dtu-build-id="$build_id"
ninja -C "$src/build" src/freedreno/vulkan/libvulkan_freedreno.so

if [ -n "${MESA_COMMIT:-}" ]; then
  folder=azimuth-next
  label="Azimuth (Mesa main ${MESA_COMMIT:0:10} + host memory) $version"
  tarball="azimuth-turnip-next-$version.tar.gz"
else
  folder=azimuth
  label="Azimuth (Devel + host memory) $version"
  tarball="azimuth-turnip-$version.tar.gz"
fi

pkg="$work/pkg/$folder"
rm -rf "$work/pkg"
mkdir -p "$pkg"
strip -o "$pkg/libvulkan_freedreno.so" "$src/build/src/freedreno/vulkan/libvulkan_freedreno.so"
printf '{"name": "%s"}\n' "$label" > "$pkg/meta.json"
gcc -O2 -I"$src/include" -o "$work/pkg/azimuth-hosttest" "$root/tools/hosttest.c" -ldl

tar -czf "$out/$tarball" -C "$work/pkg" "$folder" azimuth-hosttest
echo "build id $build_id"
sha256sum "$out/$tarball"
