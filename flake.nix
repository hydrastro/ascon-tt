{
  description = "Tiny Tapeout ASCON AEAD project";

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
      py = pkgs.python3;

      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib

        librelane

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

          py
          py.pkgs.pip
          py.pkgs.virtualenv
          py.pkgs.setuptools
          py.pkgs.wheel

          which
          coreutils
          findutils
          gnugrep
          gnused
          gnutar
          gzip
        ];

        ASCON_RTL = "${ascon-rtl}";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
        QT_QPA_PLATFORM = "offscreen";

        shellHook = ''
          echo "ascon-tt dev shell"
          echo "ASCON_RTL=${ascon-rtl}"
          echo "LD_LIBRARY_PATH includes runtime libs for klayout and cairosvg."
          echo
          echo "Recommended after dependency changes:"
          echo "  make tt12-python-reset"
          echo "  make tt12-python-venv"
          echo "  make tt12-python-check"
        '';
      };
    };
}
