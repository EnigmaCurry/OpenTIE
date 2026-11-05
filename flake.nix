{
  description = "OpenTIE — open-source Star Wars: TIE Fighter reimplementation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # OpenTIE's FSR 3.1.4 shader generator drives shadercross with
        # --enable-16bit-types and --spirv-vulkan1.1, which upstream does not
        # implement. The project carries the patch that adds them, and it
        # applies cleanly to the revision nixpkgs packages. If a nixpkgs bump
        # ever breaks it, re-pin to the Dockerfile's SHADERCROSS_COMMIT.
        shadercross = pkgs.sdl3-shadercross.overrideAttrs (old: {
          pname = "sdl3-shadercross-opentie";
          patches = (old.patches or [ ]) ++ [ ./packaging/common/shadercross-fsr3.patch ];
        });

        # Mirrors packaging/linux/Dockerfile. Versions come from the locked
        # nixpkgs rather than the Dockerfile's exact release pins (SDL3 3.4.18
        # here vs 3.4.14 there), which satisfies the >= 3.4 requirement in
        # aeron/CMakeLists.txt.
        buildDeps = with pkgs; [
          sdl3
          zstd
          ffmpeg
          fluidsynth
          speexdsp
          curl
        ];

        nativeDeps = [
          shadercross
        ] ++ (with pkgs; [
          cmake
          ninja
          pkg-config
          ccache
        ]);

        # Upstream builds on the Ubuntu 22.04 GCC 12 of
        # packaging/linux/Dockerfile. Pin a toolchain in that supported range
        # rather than tracking whatever GCC nixpkgs ships today.
        stdenv = pkgs.gcc14Stdenv;

        # Driven through dlopen at runtime, so they need to be on the loader
        # path rather than in the link line. The nixpkgs vulkan-loader reads
        # ICDs from /run/opengl-driver, which is where the host driver lives.
        runtimeDeps = with pkgs; [
          vulkan-loader
          libGL
          wayland
          libxkbcommon
          libx11
          libxcursor
          libxi
          libxrandr
        ];

        tools = with pkgs; [
          just
          innoextract
          git
          vulkan-tools
        ];
      in
      {
        devShells.default = (pkgs.mkShell.override { inherit stdenv; }) {
          name = "opentie";

          nativeBuildInputs = nativeDeps ++ tools;
          buildInputs = buildDeps ++ runtimeDeps;

          shellHook = ''
            # Lets the Justfile tell whether it already runs inside this shell,
            # so `just` does not nest another `nix develop`.
            export IN_OPENTIE_SHELL=1
            export AERON_SHADERCROSS_EXECUTABLE="${shadercross}/bin/shadercross"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath runtimeDeps}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
          '';
        };

        packages.shadercross = shadercross;
      }
    );
}
