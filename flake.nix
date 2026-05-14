{
  description = "Tiny Tapeout ASCON AEAD project";

  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-unstable";
    ascon-rtl.url = "github:hydrastro/ascon-rtl";
    ascon-rtl.flake = false;
    ascon-c.url   = "github:ascon/ascon-c";
    ascon-c.flake = false;
  };

  outputs = { self, nixpkgs, ascon-rtl, ascon-c }:
    let
      system = "x86_64-linux";
      pkgs   = import nixpkgs { inherit system; };
      lib    = pkgs.lib;

      # python3.withPackages bakes _tkinter.so into the interpreter derivation.
      # This is the only way to make tkinter importable inside a venv on NixOS,
      # because venvs inherit the C-extension search path from their base Python.
      # Adding py.pkgs.tkinter to `packages` alone does NOT work for venvs.
      py = pkgs.python3.withPackages (ps: [ ps.tkinter ]);

      runtimeLibs = with pkgs; [
        stdenv.cc.cc.lib
        tcl
        tk

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
          # EDA tools — librelane uses these from PATH, no container needed
          yosys
          openroad
          klayout
          magic-vlsi
          netgen
          verilator
          iverilog

          # Python (with tkinter baked in — required by librelane PDK config parsing)
          py
          py.pkgs.pip
          py.pkgs.virtualenv
          py.pkgs.setuptools
          py.pkgs.wheel
          py.pkgs.tkinter

          # Build tools for pip wheel compilation
          ninja meson cmake pkg-config gcc

          # Version control + utilities
          git gnumake which
          coreutils findutils gnugrep gnused gnutar gzip
        ];

        ASCON_RTL   = "${ascon-rtl}";
        ASCON_C_DIR = "${ascon-c}";
        LD_LIBRARY_PATH = lib.makeLibraryPath runtimeLibs;
        QT_QPA_PLATFORM = "offscreen";

        # Disable container engine — librelane uses PATH tools directly
        LIBRELANE_CONTAINER_ENGINE = "";

        shellHook = ''
          export NIX_LD_LIBRARY_PATH="$LD_LIBRARY_PATH"
          echo "ascon-tt dev shell"
          echo "  ASCON_RTL   = ${ascon-rtl}"
          echo "  ASCON_C_DIR = ${ascon-c}"
          echo
          echo "First time setup:"
          echo "  make tt12-python-venv"
          echo
          echo "To build:"
          echo "  make gen-vectors sim-aead-vectors-prod-directout lint synth"
          echo "  make tt12-harden"
        '';
      };
    };
}
