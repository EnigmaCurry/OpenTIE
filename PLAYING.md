# Playing OpenTIE on NixOS

`flake.nix` pins the toolchain and libraries; the `Justfile` drives extraction,
the build, and launching. Everything runs from the repository root.

```sh
just play        # extract game data, build, launch
just --list      # all recipes
```

Recipes re-enter the Nix dev shell on their own, so `just play` works from a
bare shell with nothing but Nix installed. `just shell` opens the same
environment interactively if you want `cmake`/`ninja` on PATH directly.

## Game data

Put the GOG installers in `dl/` and run `just extract`. Each edition is
extracted with `innoextract` into its own directory and matched by filename:

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

Vulkan comes from the host driver via `/run/opengl-driver`, which the nixpkgs
`vulkan-loader` already searches. `just status` and `vulkaninfo --summary`
(available in the dev shell) are the quick checks if rendering fails to start.
