# azimuth-arm64

[Azimuth](https://almost-there-games.itch.io/azimuth), the Forza Horizon 2 PC
wrapper, on ARM64 Linux handhelds such as the Retroid Pocket 6 with ArmadaOS.
Since 1.0 Azimuth also runs Forza Motorsport 5, Forza Motorsport 6 and Forza
Horizon 3; this repository was tested with Forza Horizon 2 only.

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

Both still hold with Azimuth 1.0.4: it still requires heaps over existing
memory, and the shaders are still the game's own.

This repository is an overlay: two Mesa patches, scripts and CI that build
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
2. Only for Azimuth 1.0.0 to 1.0.2: they compile the launcher's shaders with
   `D3DCompiler_47`, and Proton's own version can't compile them (*E5017: not
   yet implemented feature*), so Azimuth closes at once. Install Microsoft's
   in Azimuth's prefix, with the App ID that `protontricks -l` shows for the
   shortcut, and add `d3dcompiler_47=n;` at the start of the overrides below:

   ```sh
   protontricks <APPID> d3dcompiler_47
   ```

   Azimuth 1.0.4 ships its shaders compiled and no longer needs it.
3. In Steam, Azimuth > Properties:
   - Compatibility: **Proton Experimental (arm64)**.
   - Launch options, with your home folder:

     ```
     WINEDLLOVERRIDES="vcruntime140,vcruntime140_1,msvcp140,concrt140,msvcp110,msvcr110=n" VK_DRIVER_FILES=/var/home/armada/.local/share/armada/turnip/azimuth/icd.json VK_ICD_FILENAMES=/var/home/armada/.local/share/armada/turnip/azimuth/icd.json %command%
     ```

   The overrides make Proton load the Visual C++ runtimes Azimuth ships in
   `data/bin`. The driver also shows up in Armada
   Control's Turnip list, but for Azimuth that choice doesn't reach the game,
   so set it in the launch options.
4. Azimuth 1.0 and later always run the game at real time. On 0.9.x set
   **Frame pacing** to **Real-time** in the launcher: the game's logic
   advances one step per frame, and with *Fixed* it plays in slow motion
   whenever it runs below its frame rate.

The first start builds Azimuth's pipelines and takes a while. Azimuth
writes its log and crash dumps in `data/logs` beside `azimuth.exe`.

## Performance

On the Retroid Pocket 6 (Adreno 740 at its 680 MHz maximum) races run at
about 20-24 fps at 720p, whatever the preset. The GPU is the limit: about
3,500 draws per frame, with the time spread over some 200 of the game's
shaders, so resolution, presets and driver switches (`TU_DEBUG=sysmem`,
`gmem`, `noubwc`, `IR3_SHADER_DEBUG=nopreamble`) change little. With
Real-time frame pacing the game runs at the right speed. Locking the frame
rate at 20 in the quick access menu makes it steadier.

Azimuth 1.0 adds per-game graphics settings, among them Shadow detail, Shadow
distance, Shadow redraw and Scenery detail. Shadows were the largest single
cost in the GPU trace (depth-only draws, about a sixth of the frame), so they
are the first settings to lower. Azimuth 1.0.2 also does much less of its own
work per frame, which helps with stutter but not with the GPU limit.

## Lighter graphics on the Retroid Pocket 6

Forza Horizon 2 takes its render settings from small XML files in
`media/RenderScenarios`, one base file and one per situation (race, replay,
menus, split screen). `scripts/fh2-lowspec.py` copies them from your game
folder, turns down the car, crowd, mirror and reflection settings and writes them as a
mod for [Extra Options](https://github.com/RokkuDayo/ForzaHorizon2_ExtraOptions),
which loads it in place of the originals. No game file is changed.

1. Install Extra Options for Azimuth (its files go beside `azimuth.exe`) and add
   `WINEDLLOVERRIDES="winmm.dll=n,b"` to the launch options, next to the
   overrides above.
2. Run, with your Azimuth folder and, if it isn't below it, the game folder:

   ```sh
   python3 fh2-lowspec.py ~/Games/PC/azimuth-fh2 [GAME_DIR]
   ```

   Extra Options adds `rp6-lowspec` to `mods/loadorder.txt` on the next start;
   `FH2_ExtraOptions.log` then lists `rp6-lowspec: media addon ready`.

What it lowers: car reflections are no longer re-rendered every frame (also
on AI cars), no windshield reflections, 256 shadow maps without high-detail
car shadows and without shadows from fences and the crowd, cars switch to
simpler models at half the distance, no crowd, no motion blur, bloom at half
rate, particles at a quarter, a lighter mirror.

On the Retroid Pocket 6 this gives about 3 fps: the pause menu at the Horizon
festival goes from 23 to 26 fps and the road from the festival to the bridge
from 22-28 to 24-30. The rest of the frame is the world itself, which these
files don't touch. To undo it, run the script with `--remove` or put
`# rp6-lowspec` in `loadorder.txt`.

## What is here

| Path | What it does |
| --- | --- |
| `upstream.json` | The Mesa commit (ArmadaOS's Devel pin) and the ArmadaOS commit whose base patches are applied first. |
| `patches/0001-*` | Turnip: emulates `VK_EXT_external_memory_host` on `msm`. The host range is copied into a cached-coherent buffer object that is then mapped over the same address, so the game keeps its pointer and shares the pages with the GPU; on free the range gets ordinary memory back with the last contents. |
| `patches/0002-*` | ir3: lowers the `fmulz`/`ffmaz`/`fmadz` left after the last algebraic pass, which the backend can't compile. |
| `scripts/prepare.sh` | Downloads Mesa and applies ArmadaOS's patches and these. |
| `scripts/build.sh` | Builds Turnip with ArmadaOS's flags and packages it with its label and `azimuth-hosttest`. |
| `scripts/install-armadaos.sh` | The install above. |
| `scripts/fh2-lowspec.py` | Writes the lighter render settings as an Extra Options mod, from your own game files. |
| `tools/hosttest.c` | Imports host memory, writes it from the GPU and frees it, to check the driver on a device. |

CI builds on an aarch64 runner in Fedora 44, the base of ArmadaOS. Releases
hold only the driver and the test tool.

## License

MIT, as the Mesa code the patches change; see LICENSE and NOTICE. Azimuth and
Forza Horizon 2 belong to their owners and are not affiliated with this
repository.
