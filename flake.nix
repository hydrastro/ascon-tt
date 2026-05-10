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
    in {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          gnumake
          git
          iverilog
          verilator
          yosys
          python3
        ];

        shellHook = ''
          echo "ascon-tt dev shell"
          echo "ASCON_RTL=${ascon-rtl}"
        '';
      };
    };
}
