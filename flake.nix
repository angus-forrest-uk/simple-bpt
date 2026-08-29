{
  description = "Basic PAYE Tools, headless: HMRC's Django server without the Qt shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      lock = builtins.fromJSON (builtins.readFile ./lock.json);

      overlay = final: prev: {
        simple-bpt = final.callPackage ./nix/package.nix { inherit lock; };
      };
    in
    flake-utils.lib.eachDefaultSystem
      (system:
        let
          pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };
        in
        {
          packages = {
            simple-bpt = pkgs.simple-bpt;
            default = pkgs.simple-bpt;
          };

          apps.default = {
            type = "app";
            program = "${pkgs.simple-bpt}/bin/simple-bpt";
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [ curl unzip squashfsTools python3 shellcheck ];
          };
        })
    // {
      overlays.default = overlay;
      nixosModules.default = import ./nix/module.nix;
      nixosModules.simple-bpt = import ./nix/module.nix;
    };
}
