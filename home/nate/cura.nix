{ config, lib, pkgs, ... }:

{

  home.packages = [ pkgs.cura-appimage ];

  # Cura profiles are managed outside Nix (copied from Arch/Windows install)
  # Cura needs writable files at runtime, which nix symlinks don't support.

}
