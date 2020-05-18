{ ... }:
let
  sources = import ./nix/sources.nix { };
  nixpkgs = import sources.nixpkgs { };
in with nixpkgs;
stdenv.mkDerivation {
  name = "pongex";
  buildInputs =
    [ elixir glew glfw pkgconfig darwin.apple_sdk.frameworks.Cocoa ];
}
