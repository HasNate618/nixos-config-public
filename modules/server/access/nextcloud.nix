# Nextcloud — file sync and sharing
# Native NixOS module with PostgreSQL + Redis + Caddy reverse proxy
# Data lives on NAS mount at //10.0.0.20/homelab/cloud
{ config, lib, pkgs, ... }:

{
  # Admin password file (required for initial setup)
  environment.etc."nextcloud-admin-pass".source = config.sops.secrets."nextcloud-admin-pass".path;

  # CIFS utils for NAS mount
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Mount NAS cloud data at Nextcloud's default data directory
  fileSystems."/var/lib/nextcloud/data" = {
    device = "//10.0.0.20/homelab/cloud";
    fsType = "cifs";
    options = [ "_netdev,credentials=/etc/samba/creds,uid=nextcloud,gid=nextcloud,forceuid,forcegid,noperm,dir_mode=0770,file_mode=0770,vers=3.0,x-systemd.automount,noauto,x-systemd.after=network-online.target x-systemd.after=samba-creds-sync.service,x-systemd.mount-timeout=30" ];
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud32;

    # Domain
    hostName = "cloud.home";

    # Database — use shared PostgreSQL
    database.createLocally = true;
    config.dbtype = "pgsql";

    # Redis caching
    configureRedis = true;

    # Admin password (initial setup)
    config.adminpassFile = "/etc/nextcloud-admin-pass";

    # Max upload size
    maxUploadSize = "16G";

    # PHP configuration
    phpOptions = {
      "opcache.enable" = "1";
      "opcache.enable_cli" = "1";
      "opcache.interned_strings_buffer" = "16";
      "opcache.max_accelerated_files" = "10000";
      "opcache.memory_consumption" = "128";
      "opcache.revalidate_freq" = "1";
      "upload_max_filesize" = "16G";
      "post_max_size" = "16G";
      "max_execution_time" = "3600";
      "max_input_time" = "3600";
    };

    # Office suite — Collabora Online integration
    extraAppsEnable = true;
    extraApps = with config.services.nextcloud.package.packages.apps; {
      richdocuments = richdocuments;
    };

    # Settings
    settings = {
      # Overwrite settings for reverse proxy
      overwriteprotocol = "http";
      overwrite.cli.url = "http://cloud.home.lab";
      trusted_proxies = [ "127.0.0.1" ];
      trusted_domains = [ "cloud.home" "cloud.home.lab" ];
      
      # Performance
      default_phone_region = "CA";
      maintenance_window_start = 1;
      
      # Disable maintenance mode
      maintenance = false;

      # App store
      appstoreenabled = true;
    };
  };

  # Change nginx to listen on localhost:8082 (Caddy handles external traffic)
  services.nginx.virtualHosts.${config.services.nextcloud.hostName}.listen = [
    { addr = "127.0.0.1"; port = 8082; }
  ];
}
