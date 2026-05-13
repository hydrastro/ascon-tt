{
  description = "Tiny Tapeout ASCON AEAD project";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    # Vendored ASCON RTL core (read-only; consumed via $ASCON_RTL env var).
    ascon-rtl.url   = "github:hydrastro/ascon-rtl";
    ascon-rtl.flake = false;
  };

  outputs = { self, nixpkgs, ascon-rtl }:
    let
      system = "x86_64-linux";
      pkgs   = import nixpkgs { inherit system; };
      lib    = pkgs.lib;
      py     = pkgs.python3;

      # Native shared-library runtime required by klayout and cairosvg.
      # These are *not* Python packages; they are loaded via LD_LIBRARY_PATH.
      nativeLibs = with pkgs; [
        stdenv.cc.cc.lib   # libstdc++

        # Cairo / cairosvg / cairocffi
        cairo pixman libpng zlib expat
        glib pango harfbuzz fribidi
        gdk-pixbuf librsvg libjpeg libtiff

        # Font / rendering
        fontconfig freetype libGL libxkbcommon

        # X11 (klayout uses Qt/X11 even in offscreen mode)
        libx11 libxext libxrender libxcb
        libxft libxi libxrandr libxcursor
        libxinerama libsm libice
      ];
    in {
      devShells.${system}.default = pkgs.mkShell {
        # System-level tools provided by Nix.
        # Python packages (chevron, klayout, cairosvg, librelane …) are
        # installed into a repo-local .venv/ via "make tt12-python-venv".
        # Do NOT add them here; the venv pins the versions from tt/requirements.txt.
        packages = with pkgs; [
          # Build / HDL tools
          gnumake
          yosys
          iverilog
          verilator
          openroad
          klayout
          git

          # Python base (venv is built on top of this)
          py
          py.pkgs.pip
          py.pkgs.virtualenv
          py.pkgs.setuptools
          py.pkgs.wheel

          # POSIX utilities used by shell scripts
          which coreutils findutils
          gnugrep gnused gnutar gzip
        ];

        # Points to the Nix-store copy of ascon-rtl (read-only).
        # For vector generation that needs a writable checkout, pass
        # ASCON_RTL_WORKTREE=../ascon-rtl on the make command line.
        ASCON_RTL = "${ascon-rtl}";

        # Make klayout / cairosvg shared-library deps findable at runtime.
        LD_LIBRARY_PATH = lib.makeLibraryPath nativeLibs;

        # Prevent klayout from trying to open a real display.
        QT_QPA_PLATFORM = "offscreen";

        shellHook = ''
          echo "ascon-tt dev shell"
          echo "ASCON_RTL  = ${ascon-rtl}"
          echo
          echo "First-time setup (or after dependency changes):"
          echo "  make tt12-python-venv"
          echo "  make tt12-python-check"
          echo
          echo "See docs/QUICKSTART.md for the full flow."
        '';
      };
    };
}
