# Homelab host — REAL HARDWARE
# Intel i5-6600K, GTX 960, 16GB RAM, 225GB NVMe
{ config, lib, pkgs, modulesPath, ... }: {
  imports = [
    ./hardware-configuration.nix
    ../../modules/server
  ];

  networking.hostName = "home";
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  networking.extraHosts = "100.103.1.61 home.lab";

  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda";

  # NVIDIA GTX 960 (GM206, Maxwell)
  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    package = config.boot.kernelPackages.nvidiaPackages.legacy_535;
  };
  hardware.nvidia-container-toolkit.enable = true;

  systemd.tmpfiles.rules = [
    "d /srv/homelab 0755 nate users -"
    "d /srv/homelab/compose 0755 nate users -"
    "d /srv/homelab/data 0755 nate users -"
    "d /srv/homelab/data/nas 0755 nate users -"
    "d /srv/homelab/data/nas/media 0755 nate users -"
    "d /srv/homelab/data/nas/gitea 0755 nate users -"
    "d /srv/homelab/data/nas/cloud 0755 nate users -"
    "d /srv/homelab/data/nas/photos 0755 nate users -"
  ];
}
