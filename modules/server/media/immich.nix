# Immich — self-hosted photo and video management
# Native NixOS module (no Docker)
# NAS photos at //10.0.0.20/homelab/photos → /mnt/photos
{ config, lib, pkgs, ... }:

{
  # CIFS utils for NAS mount
  environment.systemPackages = [ pkgs.cifs-utils ];
  # Mount NAS photos share for Immich
  fileSystems."/mnt/photos" = {
    device = "//10.0.0.20/homelab/photos";
    fsType = "cifs";
    options = [ "_netdev,credentials=/etc/samba/creds,uid=1000,gid=1000,forceuid,forcegid,noperm,dir_mode=0775,file_mode=0664,vers=3.0,x-systemd.automount,noauto,x-systemd.after=network-online.target x-systemd.after=samba-creds-sync.service,x-systemd.mount-timeout=30" ];
  };

  services.immich = {
    enable = true;
    port = 2283;
    host = "127.0.0.1";
    mediaLocation = "/mnt/photos";

    # Use existing PostgreSQL (module adds pgvector + vectorchord extensions)
    database = {
      enable = true;
      createDB = true;
      name = "immich";
      host = "/run/postgresql";
    };

    # Immich manages its own Redis instance
    redis = {
      enable = true;
    };

    # Hardware acceleration (GTX 960 — when NVIDIA is enabled)
    # accelerationDevices = null;  # uncomment when NVIDIA is re-enabled

    environment = {
      IMMICH_LOG_LEVEL = "warn";
    };
  };

  # Add immich user to video/render groups for GPU transcoding
  users.users.immich.extraGroups = [ "video" "render" ];

  # Reduce Redis log verbosity
  services.redis.servers.immich.logLevel = "warning";
}
