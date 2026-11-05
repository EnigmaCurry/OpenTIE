# OpenTIE — extract the original game data, build the engine, and play.
#
#   just play      # do everything: extract, build, launch
#   just --list    # all recipes
#
# Every recipe works from a bare shell: it re-enters the Nix dev shell itself
# when needed. On a machine with only Nix installed, bootstrap with
# `nix develop --command just play` — the dev shell is what provides `just`.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Directory holding the GOG installer .exe files.
dl_dir := "dl"
# Where the extracted original game data lands.
data_dir := "game"
# CMake build tree. Holds OpenTIE, resources/, and shaders/ together.
build_dir := "build"
# Release or Debug. Debug also enables OpenTIE's in-game debug UI.
build_type := "Release"

jobs := `nproc`

# Prefix that re-enters the dev shell, or nothing when already inside it.
# `nix develop --command` passes all remaining arguments through untouched.
nix := if env("IN_OPENTIE_SHELL", "") == "1" { "" } else { "nix develop --command" }

tie95 := data_dir / "tie95"
tie98 := data_dir / "tie98"

# User data: pilots, settings, and the remembered installation paths.
prefs := env("XDG_DATA_HOME", env("HOME") / ".local/share") / "TotallyOpen/OpenTIE"

[private]
default:
    @just --list --unsorted

# Extract game data, build the engine, then launch it.
play: extract build run

# Enter a shell with the full toolchain on PATH.
shell:
    nix develop

# Check out the aeron, landru, and imuse submodules.
submodules:
    git submodule update --init --recursive

# Extract the GOG installers into game/. Skips editions already present.
extract: (_extract "tie95" "collectors_cd") (_extract "tie98" "(1998)")

# Extracts the single installer in {{dl_dir}} whose name contains `match`.
[private]
_extract edition match:
    #!/usr/bin/env bash
    set -euo pipefail
    dest="{{data_dir}}/{{edition}}"
    if [ -e "$dest/STRINGS.DAT" ]; then
        echo "{{edition}}: already extracted in $dest"
        exit 0
    fi
    shopt -s nullglob
    installers=({{dl_dir}}/*"{{match}}"*.exe)
    if [ ${#installers[@]} -eq 0 ]; then
        echo "{{edition}}: no installer matching '*{{match}}*.exe' in {{dl_dir}}/ — skipping" >&2
        exit 0
    fi
    if [ ${#installers[@]} -gt 1 ]; then
        printf '%s\n' "{{edition}}: multiple installers match '*{{match}}*.exe':" "${installers[@]}" >&2
        exit 1
    fi
    echo "{{edition}}: extracting ${installers[0]}"
    mkdir -p "$dest"
    {{nix}} innoextract --extract --gog --output-dir "$dest" "${installers[0]}"

# Report which editions are installed and which OpenTIE will use.
status:
    #!/usr/bin/env bash
    set -euo pipefail
    for pair in "1995 Collector's CD:{{tie95}}" "1998 Windows:{{tie98}}"; do
        label="${pair%%:*}"; dir="${pair#*:}"
        if [ -e "$dir/STRINGS.DAT" ]; then
            echo "present  $label  ($dir)"
        else
            echo "missing  $label  ($dir)"
        fi
    done
    echo
    echo "build:  $([ -x '{{build_dir}}/OpenTIE' ] && echo '{{build_dir}}/OpenTIE' || echo 'not built')"
    echo "prefs:  $([ -d '{{prefs}}' ] && echo '{{prefs}}' || echo 'none yet')"

# -include new below works around aeron/src/fsr3/backend.cpp using std::nothrow
# without including <new>; GCC 14+ no longer pulls it in transitively. Applied
# here rather than by editing the vendored aeron submodule, so it survives
# `git submodule update`. Harmless once upstream adds the include.
#
# The blank line matters: `just --list` shows only the comment block directly
# above a recipe, and only its last line.

# Configure the CMake build tree.
configure:
    {{nix}} cmake -S . -B {{build_dir}} -G Ninja \
        -DCMAKE_BUILD_TYPE={{build_type}} \
        -DCMAKE_CXX_FLAGS='-include new' \
        -DENABLE_FLUIDSYNTH=ON \
        -DENABLE_FM4_OPL3=ON \
        -DENABLE_NUKED_SC55=ON \
        -DTIE_BUILD_TOOLS=OFF \
        -DTIE_ENABLE_DEBUG_UI={{ if build_type == "Debug" { "ON" } else { "OFF" } }}

# Build the OpenTIE executable, its resources, and its shaders.
build: submodules configure
    {{nix}} cmake --build {{build_dir}} --target tie --parallel {{jobs}}

# Launch OpenTIE against the extracted game data.
run *args:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ ! -x "{{build_dir}}/OpenTIE" ]; then
        echo "OpenTIE is not built yet — run 'just build'." >&2
        exit 1
    fi
    # Passing the data directories skips the interactive first-run picker.
    opts=()
    [ -e "{{tie95}}/STRINGS.DAT" ] && opts+=(--tie95-data "$PWD/{{tie95}}")
    [ -e "{{tie98}}/STRINGS.DAT" ] && opts+=(--tie98-data "$PWD/{{tie98}}")
    if [ ${#opts[@]} -eq 0 ]; then
        echo "No game data found under {{data_dir}}/ — run 'just extract'." >&2
        exit 1
    fi
    {{nix}} ./{{build_dir}}/OpenTIE "${opts[@]}" {{args}}

# Delete the build tree.
clean:
    rm -rf {{build_dir}}

# Delete pilots, settings, and remembered installation paths, so setup re-runs.
reset-prefs:
    rm -rf '{{prefs}}'

# Delete the extracted game data. The installers in dl/ are kept.
clean-data:
    rm -rf {{data_dir}}
