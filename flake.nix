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

      # Current nixpkgs removed python3Full. Tkinter now lives in the Python
      # package set. The venv is created with --system-site-packages so it can
      # see this Nix-provided _tkinter extension.
      py = pkgs.python3.withPackages (ps: [
        ps.tkinter
        ps.rich
        ps.click
        ps.pip
        ps.virtualenv
        ps.setuptools
        ps.wheel
      ]);

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

          # Python and build helpers. py is python3.withPackages above;
          # keep pip/virtualenv inside that same interpreter family.
          py
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
          # OpenROAD executes LibreLane odbpy helpers with an embedded Python.
          # Expose both the project venv and the Nix Python package set.
          _pyver=$(python3 - <<'PYSITE'
import sys
print(f"python{sys.version_info.major}.{sys.version_info.minor}")
PYSITE
)
          _nix_site=$(python3 - <<'PYSITE'
import site
print(site.getsitepackages()[0])
PYSITE
)
          export PYTHONPATH="$PWD/.venv/lib/$_pyver/site-packages:$_nix_site:${PYTHONPATH:-}"
          mkdir -p "$PDK_ROOT"
          export LIBRELANE_CONTAINER_ENGINE=""
          export LIBRELANE_DOCKERLESS=1
          python3 - <<'PYTK'
import _tkinter, tkinter
print("Python tkinter OK:", _tkinter.TK_VERSION)
PYTK
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
