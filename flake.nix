{
  description = "Tiny Tapeout ASCON AEAD project";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    ascon-rtl.url = "github:hydrastro/ascon-rtl";
    ascon-rtl.flake = false;
    ascon-c.url = "github:ascon/ascon-c";
    ascon-c.flake = false;
  };

  outputs = { self, nixpkgs, ascon-rtl, ascon-c }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;
      py = pkgs.python3;

      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib

        # CairoSVG / cairocffi native runtime
        cairo
        pixman
        libpng
        zlib
        expat
        glib
        pango
        harfbuzz
        fribidi
        gdk-pixbuf
        librsvg
        libjpeg
        libtiff

        # Fonts/graphics/runtime dependencies
        fontconfig
        freetype
        libGL
        libxkbcommon

        # X11 libraries. Use renamed top-level nixpkgs attrs.
        libx11
        libxext
        libxrender
        libxcb
        libxft
        libxi
        libxrandr
        libxcursor
        libxinerama
        libsm
        libice
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          gnumake
          openroad
          git
          iverilog
          verilator
          yosys
          klayout

          # Python + venv
          py
          py.pkgs.pip
          py.pkgs.tkinter
          py.pkgs.virtualenv
          py.pkgs.setuptools
          py.pkgs.wheel

          # Native build tools needed by pip when building wheels from source
          # (numpy, scipy, etc. need these if no pre-built wheel matches)
          ninja
          meson
          cmake
          pkg-config
          gcc

          which
          coreutils
          findutils
          gnugrep
          gnused
          gnutar
          gzip
        ];

        ASCON_RTL = "${ascon-rtl}";
        ASCON_C_DIR = "${ascon-c}";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
        QT_QPA_PLATFORM = "offscreen";

        shellHook = ''
          echo "ascon-tt dev shell"
          echo "ASCON_RTL=${ascon-rtl}"
          echo "ASCON_C_DIR=${ascon-c}"
          echo

          # Make sure pip-built C extensions can find Nix-provided shared libs.
          export NIX_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"

          echo "Recommended after dependency changes:"
          echo "  make tt12-python-reset && make tt12-python-venv"
          echo
          echo "To generate simulation vectors:"
          echo "  make gen-vectors"
        '';
      };
    };
}
