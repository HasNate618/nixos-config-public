# Pin Hyprland to 0.55.4 (nixpkgs rev 61b7c44c407, Jul 18 2026).
#
# WHY: Hyprland 0.56.0+ broke blur behind foot's transparent background
# (foot requests blur via the ext-background-effect-v1 protocol; the path
# regressed in 0.56 and was NOT fixed in 0.56.1 or 0.56.2). Zen and layer
# surfaces still blur — only foot-style protocol surfaces are affected.
#   https://github.com/hyprwm/Hyprland/discussions/15530
#   https://github.com/hyprwm/Hyprland/discussions/15524
# The old derivation is already in the store (built with gen 871), so this
# pin costs nothing to build.
#
# REMOVE THIS OVERLAY once a Hyprland release fixes the foot blur
# regression, then `nix flake update nixpkgs` to resume tracking unstable.

let
  oldNixpkgs = builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/61b7c44c4073f0b827768aff0049561b5110ea5a.tar.gz";
    sha256 = "1knbr9j7szzlppbp0r9rby06nml7b45vqhmskgycfbcnr1nanqnp";
  };
in
final: prev: {
  hyprland = (import oldNixpkgs {
    inherit (final) system;
    config.allowUnfree = true;
  }).hyprland;
}
