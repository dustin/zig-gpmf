{
  description = "GPMF for Zig";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      eachSystem = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
    in {
      packages = eachSystem (system: let pkgs = import nixpkgs { inherit system; }; in {
        default = pkgs.stdenv.mkDerivation {
          name = "zig-gpmf";
          src = ./.;
          buildInputs = [ pkgs.zig_0_15 ];
        };
      });

      devShells = eachSystem (system: let pkgs = import nixpkgs { inherit system; }; in {
        default = pkgs.mkShell {
          buildInputs = [ pkgs.zig_0_15 ];
        };
      });
    };
}
