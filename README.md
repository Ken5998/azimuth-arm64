# azimuth-arm64

[Azimuth](https://almost-there-games.itch.io/azimuth), the Forza Horizon 2 PC
wrapper, on ARM64 Linux handhelds such as the Retroid Pocket 6 with ArmadaOS.

Azimuth runs the game's Xbox One executable and translates its graphics to
Direct3D 12, which Proton turns into Vulkan with vkd3d-proton. On the Retroid
Pocket 6 two things in the Vulkan driver, Turnip, stop it:

- Azimuth opens D3D12 heaps over the game's own memory
  (`OpenExistingHeapFromAddress`). vkd3d-proton needs
  `VK_EXT_external_memory_host` for that, which Turnip doesn't offer on the
  `msm` kernel driver, so Azimuth stops at startup with *the D3D12 driver
  cannot open heaps over existing memory*.
- Some of the game's shaders crash Turnip's compiler while Azimuth builds its
  pipelines (`Unhandled ALU op: fmadz`), and the game closes.

This repository is an overlay: Mesa patches, scripts and CI that build
ArmadaOS's Turnip "Devel" driver with them. It never contains the game,
Azimuth or files from either.

## Install on the Retroid Pocket 6 (ArmadaOS)

You need Azimuth set up with your Forza Horizon 2 files and added to Steam,
as Azimuth's own guide describes.

1. In Desktop Mode, open a terminal and run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/Ken5998/azimuth-arm64/main/scripts/install-armadaos.sh | bash
   ```

   It installs the driver in `~/.local/share/armada/turnip/azimuth` and prints
   the launch options. Add `-s -- --test` after `bash` to also check that the
   driver imports host memory on your device.
2. In Steam, Azimuth > Properties:
   - Compatibility: **Proton Experimental (arm64)**.
   - Launch options, with your home folder:

     ```
     VK_DRIVER_FILES=/var/home/armada/.local/share/armada/turnip/azimuth/icd.json VK_ICD_FILENAMES=/var/home/armada/.local/share/armada/turnip/azimuth/icd.json %command%
     ```

   The driver also shows up in Armada Control's Turnip list, but for Azimuth
   that choice doesn't reach the game, so set it in the launch options.
3. In Azimuth's launcher set **Frame pacing** to **Real-time**. The game's
   logic advances one step per frame; with *Fixed* it plays in slow motion
   whenever it runs below its frame rate.

The first start builds Azimuth's pipelines and takes a while.

## Performance

On the Retroid Pocket 6 (Adreno 740 at its 680 MHz maximum) races run at
about 20-24 fps at 720p, whatever the preset. The GPU is the limit: about
3,500 draws per frame, with the time spread over some 200 of the game's
shaders, so resolution, presets and driver switches (`TU_DEBUG=sysmem`,
`gmem`, `noubwc`, `IR3_SHADER_DEBUG=nopreamble`) change little. With
Real-time frame pacing the game runs at the right speed. Locking the frame
rate at 20 in the quick access menu makes it steadier.

An experimental NIR optimization removes redundant positive-zero checks
around FP32 squares while retaining strict floating-point behavior. Its
effect on device performance still needs measurement. The [IR3 experiment
guide](docs/ir3-guarded-squares.md) documents the dump analysis, compiler
checks, and a workflow that builds matching baseline and modified drivers.

## What is here

| Path | What it does |
| --- | --- |
| `upstream.json` | The Mesa commit (ArmadaOS's Devel pin) and the ArmadaOS commit whose base patches are applied first. |
| `patches/0001-*` | Turnip: emulates `VK_EXT_external_memory_host` on `msm`. The host range is copied into a cached-coherent buffer object that is then mapped over the same address, so the game keeps its pointer and shares the pages with the GPU; on free the range gets ordinary memory back with the last contents. |
| `patches/0002-*` | ir3: lowers the `fmulz`/`ffmaz`/`fmadz` left after the last algebraic pass, which the backend can't compile. |
| `patches/0003-*` | NIR: removes `x == +0.0 ? +0.0 : x*x` for FP32, with strict floating-point regression tests. |
| `scripts/prepare.sh` | Downloads Mesa and applies ArmadaOS's patches and these. |
| `scripts/build.sh` | Builds Turnip with ArmadaOS's flags and packages it with its label and `azimuth-hosttest`. |
| `scripts/install-armadaos.sh` | The install above. |
| `scripts/install-ir3-variant.sh` | Installs a local IR3 A/B artifact in its own driver directory. |
| `.github/workflows/ir3-square-ab.yml` | Builds baseline and square-optimization artifacts from the same Mesa pin and build flags. |
| `tools/hosttest.c` | Imports host memory, writes it from the GPU and frees it, to check the driver on a device. |

CI builds on an aarch64 runner in Fedora 44, the base of ArmadaOS. Releases
hold only the driver and the test tool.

## License

MIT, as the Mesa code the patches change; see LICENSE and NOTICE. Azimuth and
Forza Horizon 2 belong to their owners and are not affiliated with this
repository.
