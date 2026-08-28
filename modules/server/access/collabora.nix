# Collabora Online — LibreOffice-based document editor for Nextcloud
{ config, lib, pkgs, ... }:
{
  services.collabora-online = {
    enable = true;
    port = 9980;
    settings = {
      ssl = { enable = false; termination = false; };
      net = {
        listen = "loopback";
        post_allow.host = [ "127.0.0.1" "::1" ];
      };
      storage.wopi = { "@allow" = true; host = [ "cloud.home.lab" ]; };
      server_name = "collabora.home.lab";
      admin_console.enable = false;
    };
  };
  networking.hosts = {
    "127.0.0.1" = [ "cloud.home.lab" "collabora.home.lab" ];
    "::1" = [ "cloud.home.lab" "collabora.home.lab" ];
  };
  systemd.services.nextcloud-config-collabora = let
    inherit (config.services.nextcloud) occ;
    wopi_url = "http://[::1]:${toString config.services.collabora-online.port}";
    public_wopi_url = "http://collabora.home.lab";
    wopi_allowlist = lib.concatStringsSep "," [ "127.0.0.1" "::1" ];
  in {
    description = "Configure Nextcloud richdocuments for Collabora";
    wantedBy = [ "multi-user.target" ];
    after = [ "nextcloud-setup.service" "coolwsd.service" ];
    requires = [ "coolwsd.service" ];
    script = ''
      ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_url --value '${wopi_url}'
      ${occ}/bin/nextcloud-occ config:app:set richdocuments public_wopi_url --value '${public_wopi_url}'
      ${occ}/bin/nextcloud-occ config:app:set richdocuments wopi_allowlist --value '${wopi_allowlist}'
      ${occ}/bin/nextcloud-occ richdocuments:setup
    '';
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
  };
}
