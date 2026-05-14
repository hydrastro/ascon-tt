{
  description = "ASCON AEAD128/128a Tiny Tapeout GF26a project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      # Python with tkinter compiled in; this matters for LibreLane/tt tooling
      # when a venv is created on NixOS.
      py = pkgs.python3.withPackages (ps: [ ps.tkinter ]);

      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib
        cairo pixman libpng zlib expat
        glib pango harfbuzz fribidi gdk-pixbuf librsvg
        libjpeg libtiff
        fontconfig freetype libGL libxkbcommon
        libx11 libxext libxrender libxcb libxft
        libxi libxrandr libxcursor libxinerama libsm libice
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # RTL/sim/synthesis
          yosys
          iverilog
          verilator

          # Physical-design/runtime tools used by LibreLane and TT helpers
          openroad
          klayout
          magic-vlsi
          # Do not add pkgs.netgen here: in nixpkgs that is the 3D mesh generator,
          # not Timothy Edwards' Netgen LVS tool.
          tcl
          tk

          # Python and build helpers
          py
          py.pkgs.pip
          py.pkgs.virtualenv
          py.pkgs.setuptools
          py.pkgs.wheel
          ninja meson cmake pkg-config gcc

          # Utilities
          git gnumake which
          coreutils findutils gnugrep gnused gnutar gzip jq
        ];

        PDK = "gf180mcuD";
        LIBRELANE_TAG = "3.0.0";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
        QT_QPA_PLATFORM = "offscreen";

        shellHook = ''
          export NIX_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
          export PDK_ROOT="$PWD/.ttsetup/pdk"
          mkdir -p "$PDK_ROOT"
          export LIBRELANE_CONTAINER_ENGINE=""
          export LIBRELANE_DOCKERLESS=1
          echo "ascon-tt GF26a dev shell"
          echo "  PDK=$PDK"
          echo "  PDK_ROOT=$PDK_ROOT"
          echo "  LIBRELANE_TAG=$LIBRELANE_TAG"
          echo
          echo "First time:  git submodule update --init --recursive && make tt12-python-venv"
          echo "Check RTL:   make gen-vectors-128a sim-128a && make gen-vectors-128 sim-128"
          echo "Harden:      make harden-128a-gf26a"
        '';
      };
    };
}
