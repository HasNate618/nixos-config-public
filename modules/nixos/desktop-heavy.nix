# Large GUI apps — imported by flow only, skipped on live-usb ISO
{ pkgs, ... }: {
  environment.systemPackages = with pkgs; [
    blender
    obs-studio
    kdePackages.kdenlive
    pinta
    qbittorrent
  ];
}
