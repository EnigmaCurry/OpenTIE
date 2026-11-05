# Playing OpenTIE with Nix

`flake.nix` pins the toolchain and libraries; the `Justfile` drives extraction,
the build, and launching. Everything runs from the repository root.

This works on any x86-64 Linux distribution with Nix installed, not just
NixOS — the flake brings its own compiler, CMake, SDL3, and the rest, so the
host only provides the kernel, the GPU driver, and Nix itself. NixOS is where
it is tested; see [Non-NixOS hosts](#non-nixos-hosts) for the one thing that
differs. The dev shell is Linux-only: its runtime dependencies (`wayland`,
`libGL`, the X libraries) do not evaluate on macOS, which has its own build in
[packaging/macos](packaging/macos/README.md).

Requirements:

- Nix with the `nix-command` and `flakes` experimental features enabled
- the GOG installers for the original game (see [Game data](#game-data))

```sh
nix develop --command just play   # extract game data, build, launch
just --list                       # all recipes
```

Recipes re-enter the Nix dev shell on their own, so after the first call plain
`just play` works from a bare shell. The `nix develop --command` prefix is only
needed while `just` itself is missing from the host PATH, since it is one of
the tools the dev shell provides. `just shell` (or `nix develop`) opens the
same environment interactively if you want `cmake`/`ninja` on PATH directly.

## Game data

Put the GOG installers in `dl/` (`mkdir -p dl` first — the directory is
gitignored, so a fresh clone does not have it) and run `just extract`. Each
edition is extracted with `innoextract` into its own directory and matched by
filename:

| Directory    | Installer matched on | Edition                    |
| ------------ | -------------------- | -------------------------- |
| `game/tie95` | `collectors_cd`      | 1995 Collector's CD-ROM    |
| `game/tie98` | `(1998)`             | 1998 Windows release       |

`just extract` skips an edition that is already extracted and skips (without
failing) one whose installer is absent, so having only one edition is fine.
`just status` reports what is present.

The 1995 edition keeps its cutscenes, iMUSE music, and voice inside the
`game.gog` CD image. That is expected — OpenTIE mounts the image directly, so
there is nothing extra to unpack or loop-mount.

The 1994 floppy release in `dl/` is **not** supported by OpenTIE; only the 1995
and 1998 editions are, and both are installed here.

## Launching

`just run` passes `--tie95-data` and `--tie98-data` for whichever editions are
present, which skips the interactive first-run installation picker. Extra
arguments are forwarded: `just run --resource-root …`.

With both editions installed, OpenTIE offers the recommended configuration —
1995 menus, cutscenes, and adaptive iMUSE soundtrack over the 1998 flight
simulation and 3D assets. Pick it on first launch.

In-game:

- `TAB` — switch between classic and modern graphics
- `ESC` — OpenTIE settings (from the concourse, choose **OpenTIE Settings**)

Pilots, settings, and the remembered installation paths live in
`~/.local/share/TotallyOpen/OpenTIE`. `just reset-prefs` deletes them to make
setup run again.

## Notes on the Nix build

Two deliberate deviations from `packaging/linux/Dockerfile`, both commented in
place:

- **Patched shadercross.** OpenTIE's FSR 3.1.4 shader generator drives
  `shadercross` with `--enable-16bit-types` and `--spirv-vulkan1.1`, which
  upstream SDL_shadercross does not implement. The flake applies the project's
  own `packaging/common/shadercross-fsr3.patch` to the nixpkgs package.
- **`-include new`.** `aeron/src/fsr3/backend.cpp` uses `std::nothrow` without
  including `<new>`; GCC 14+ no longer pulls it in transitively. The flag is
  passed at configure time instead of editing the vendored submodule, so it
  survives `git submodule update`. It is a real upstream bug worth reporting.

The flake pins `gcc14Stdenv` — within upstream's supported "GCC 12 or newer"
range — rather than following whatever GCC nixpkgs ships. Library versions come
from nixpkgs and differ slightly from the release pins (SDL3 3.4.18 vs 3.4.14);
the `>= 3.4` requirement in `aeron/CMakeLists.txt` is satisfied.

Vulkan comes from the host driver, not from nixpkgs. The nixpkgs
`vulkan-loader` searches `/run/opengl-driver/share/vulkan/icd.d`, where NixOS
puts the driver's ICD manifests. `just status` and `vulkaninfo --summary`
(available in the dev shell) are the quick checks if rendering fails to start.

## Non-NixOS hosts

Only the graphics driver needs attention. The same `vulkan-loader` also
searches `/usr/local/share` and `/usr/share` along with the `XDG_DATA_DIRS`
paths, so the ICD manifests a normal distribution installs under
`/usr/share/vulkan/icd.d` are found without any extra configuration, and the
driver itself is loaded from the host.

If `vulkaninfo --summary` inside `just shell` reports no devices, point the
loader at the manifest explicitly:

```sh
export VK_DRIVER_FILES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json
```

Where the host driver and the Nix-built loader disagree too much to pair up —
most often with the proprietary NVIDIA driver, whose userspace library has to
match the running kernel module — [nixGL](https://github.com/nix-community/nixGL)
supplies a matching driver into the Nix environment, and `just run` can be
wrapped with it.
