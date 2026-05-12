{
  description = "Tiny Tapeout ASCON AEAD project - reproducible Nix dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ascon-rtl.url = "github:hydrastro/ascon-rtl";
    ascon-rtl.flake = false;
  };

  outputs = { self, nixpkgs, ascon-rtl }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      python = pkgs.python312;
      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib zlib libffi openssl
        cairo pixman libpng expat glib pango harfbuzz fribidi gdk-pixbuf librsvg libjpeg libtiff
        fontconfig freetype libGL libxkbcommon
        libx11 libxext libxrender libxcb libxft libxi libxrandr libxcursor libxinerama libsm libice
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          bashInteractive gnumake git cacert curl wget which coreutils findutils gnugrep gnused gawk
          gnutar gzip unzip zip file patch pkg-config
          iverilog verilator yosys symbiyosys z3 boolector
          openroad klayout docker-client dvc
          python python.pkgs.pip python.pkgs.virtualenv python.pkgs.setuptools python.pkgs.wheel
        ];

        ASCON_RTL = "${ascon-rtl}";
        PDK_ROOT = "$(pwd)/.ttsetup/pdk";
        PDK = "sky130A";
        LIBRELANE_TAG = "3.0.0rc1";
        QT_QPA_PLATFORM = "offscreen";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
        LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;

        shellHook = ''
          export PATH="$PWD/.venv/bin:$PATH"
          export ASCON_RTL="${ascon-rtl}"
          export PDK_ROOT="$PWD/.ttsetup/pdk"
          export PDK="${PDK:-sky130A}"
          export LIBRELANE_TAG="${LIBRELANE_TAG:-3.0.0rc1}"
          export QT_QPA_PLATFORM=offscreen
          echo "ascon-tt dev shell"
          echo "  Python: $(python --version 2>&1)"
          echo "  ASCON_RTL=$ASCON_RTL"
          echo "  PDK_ROOT=$PDK_ROOT"
          echo "  PDK=$PDK"
          echo "  LIBRELANE_TAG=$LIBRELANE_TAG"
          echo
          echo "First run / after changing tt-support-tools:"
          echo "  make tt-env-bootstrap"
          echo "  make tt-env-check"
        '';
      };
    };
}
