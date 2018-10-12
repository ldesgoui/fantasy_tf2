# overlay.nix
#
# https://nixos.org/nixpkgs/manual/#chap-overlays
# https://nixos.wiki/wiki/Overlays

self: super: with self; {
  postgrest = callPackage ./postgrest.nix {};
}
