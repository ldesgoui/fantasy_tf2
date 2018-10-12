# nixpkgs.nix
#
# https://nixos.wiki/wiki/FAQ/Pinning_Nixpkgs

let
  hostPkgs = import <nixpkgs> {};
  pinnedVersion = hostPkgs.lib.importJSON ./pin.json;
  pinnedPkgs = hostPkgs.fetchFromGitHub {
    owner = "NixOS";
    repo = "nixpkgs-channels";
    inherit (pinnedVersion) rev sha256;
  };
in
  import pinnedPkgs {
    overlays = [
      (import ./overlay.nix)
    ];
  }
