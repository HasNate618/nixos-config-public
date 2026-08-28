# Jellyfin — Media server
# Docker container (like Bifrost/crawl4ai — oci-containers uses podman which can't see Docker networks)
# Media on NAS at //10.0.0.6/homelab/media
{ config, lib, pkgs, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  # CIFS utils for NAS mount
  environment.systemPackages = [ pkgs.cifs-utils ];

  # Mount NAS media share (regular mount — NAS is local LAN, always available)
  fileSystems."/srv/homelab/data/nas/media" = {
    device = "//10.0.0.6/homelab/media";
    fsType = "cifs";
    options = [ "_netdev,credentials=/etc/samba/creds,uid=1000,gid=1000,forceuid,forcegid,noperm,dir_mode=0775,file_mode=0664,vers=3.0,noauto,x-systemd.automount,x-systemd.after=network-online.target x-systemd.after=samba-creds-sync.service,x-systemd.mount-timeout=30" ];
  };

  # Create Jellyfin data directories
  system.activationScripts.jellyfin-dirs = lib.mkAfter ''
    mkdir -p /var/lib/jellyfin/{config,cache,data,logs,transcodes}
    # Set Jellyfin BaseUrl to / (not /jellyfin) so Caddy strip_prefix works
    cat > /var/lib/jellyfin/config/network.xml << 'XMLEOF'
    <?xml version="1.0" encoding="utf-8"?>
    <NetworkConfiguration>
      <BaseUrl>/</BaseUrl>
    </NetworkConfiguration>
    XMLEOF
    chown -R 1000:1000 /var/lib/jellyfin
    mkdir -p /srv/homelab/data/nas/media/{movies,tv,music}
  '';

  systemd.services.jellyfin = {
    description = "Jellyfin Media Server (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull jellyfin/jellyfin:10.11.11 || true'";
      ExecStart = pkgs.writeScript "jellyfin-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f jellyfin 2>/dev/null || true
        exec ${docker} run -d --name jellyfin \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 2g \
          --cpus 2.0 \
          -u 1000:1000 \
          --group-add 44 \
          --group-add 992 \
          --device /dev/dri/renderD128:/dev/dri/renderD128 \
          --device /dev/dri/card0:/dev/dri/card0 \
          -p 8096:8096 \
          -v /var/lib/jellyfin/config:/config \
          -v /var/lib/jellyfin/config/network.xml:/config/network.xml:ro \
          -v /var/lib/jellyfin/cache:/cache \
          -v /var/lib/jellyfin/data:/var/lib/jellyfin \
          -v /var/lib/jellyfin/logs:/logs \
          -v /var/lib/jellyfin/transcodes:/transcodes \
          -v /srv/homelab/data/nas/media/movies:/media/movies \
          -v /srv/homelab/data/nas/media/tv:/media/tv \
          -v /srv/homelab/data/nas/media/music:/media/music \
          -e TZ=America/Toronto \
          -e JELLYFIN_CACHE_DIR=/cache \
          -e JELLYFIN_CONFIG_DIR=/config \
          -e JELLYFIN_DATA_DIR=/var/lib/jellyfin \
          -e JELLYFIN_LOG_DIR=/logs \
          -e JELLYFIN_PublishedServerUrl=https://home.lab \
          -e JELLYFIN_ADVERTISED_IP=10.0.0.45 \
          docker.io/jellyfin/jellyfin:latest
      '';
      ExecStop = "${docker} stop jellyfin";
    };
  };

  networking.firewall.allowedTCPPorts = [ 8096 ];
}
