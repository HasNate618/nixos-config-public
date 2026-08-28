{ config, lib, pkgs, ... }:
let
  # 1x1 black PNG to replace the default grey wallpaper
  blackBg = pkgs.runCommand "black.png" { nativeBuildInputs = [ pkgs.coreutils ]; } ''
    echo 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYGAAAAAEAAH2FzhVAAAAAElFTkSuQmCC' | base64 -d > $out
  '';
in {
  boot.loader = {
    efi.canTouchEfiVariables = true;
    timeout = 5;
    grub = {
      enable = true;
      efiSupport = true;
      device = "nodev";
      useOSProber = false;
      configurationLimit = 40;

      backgroundColor = "#000000";
      splashImage = "${blackBg}";
      splashMode = "normal";

      font = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
      fontSize = 28;

      extraConfig = ''
        set color_normal=white/black
        set menu_color_normal=white/black
        set menu_color_highlight=black/white
        set pager=1
      '';
    };
  };
}
