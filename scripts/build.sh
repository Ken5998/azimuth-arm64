#!/usr/bin/env bash
# Builds the patched Turnip for aarch64 the way ArmadaOS builds its own
# variants, and packages it as OUTDIR/azimuth-turnip-VERSION.tar.gz holding the
# folder azimuth/ (the driver and its label) and the azimuth-hosttest tool.
#
# Usage: scripts/build.sh WORKDIR OUTDIR   (run scripts/prepare.sh WORKDIR first)
set -euo pipefail

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
  cat "$root/upstream.json" "$work"/armada-patches/*.patch "$root"/patches/*.patch
} | sha256sum | cut -c1-40)"

rm -rf "$src/build"
CFLAGS="-O2 $march" CXXFLAGS="-O2 $march" \
  meson setup "$src/build" "$src" "${meson_args[@]}" -Dtu-build-id="$build_id"
ninja -C "$src/build" src/freedreno/vulkan/libvulkan_freedreno.so

pkg="$work/pkg/azimuth"
rm -rf "$work/pkg"
mkdir -p "$pkg"
strip -o "$pkg/libvulkan_freedreno.so" "$src/build/src/freedreno/vulkan/libvulkan_freedreno.so"
printf '{"name": "Azimuth (Devel + host memory) %s"}\n' "$version" > "$pkg/meta.json"
gcc -O2 -I"$src/include" -o "$work/pkg/azimuth-hosttest" "$root/tools/hosttest.c" -ldl

tar -czf "$out/azimuth-turnip-$version.tar.gz" -C "$work/pkg" azimuth azimuth-hosttest
echo "build id $build_id"
sha256sum "$out/azimuth-turnip-$version.tar.gz"
