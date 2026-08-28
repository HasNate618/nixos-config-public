{ config, lib, pkgs, ... }: {
  # Steam gaming platform with Proton support
  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;
    extraCompatPackages = [ ];
  };

  # Gaming-related system packages
  environment.systemPackages = with pkgs; [
    protontricks
    protonup-ng
    gamescope
    mangohud
    winetricks
  ];

  # Ensure 32-bit OpenGL/Vulkan for Steam games with NVIDIA
  hardware.graphics.enable32Bit = true;

  # Steam already has nvidia-offload available from hardware.nvidia.prime.offload.enableOffloadCmd
}
