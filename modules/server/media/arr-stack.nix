# *arr Stack — Media management (Sonarr, Radarr, Lidarr, Bazarr, Prowlarr, qBittorrent+Gluetun)
# Docker containers on proxy network. Data restored from pre-NixOS backup.
# Media on NAS at //10.0.0.6/homelab/media (mounted by jellyfin.nix)
{ config, lib, pkgs, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  uid = 1000;
  gid = 1000;
  dataDir = "/var/lib/arr-stack";
  # Downloads live on the NAS, not the root disk. This keeps large 4K REMUX
  # grabs off /dev/sda1 (only 226G) and lets Radarr/Sonarr hardlink imports
  # within the same NAS filesystem instead of copying.
  downloadsDir = "/srv/homelab/data/nas/media/downloads";
  mediaDir = "/srv/homelab/data/nas/media";

  securityFlags = ''
    --cap-drop ALL \
    --cap-add SETGID \
    --cap-add SETUID \
    --cap-add DAC_OVERRIDE \
    --security-opt no-new-privileges \
    --pids-limit 100 \
  '';

  bazarrSecurityFlags = ''
    --cap-drop ALL \
    --cap-add SETGID \
    --cap-add SETUID \
    --cap-add DAC_OVERRIDE \
    --security-opt no-new-privileges \
    --pids-limit 200 \
  '';

  commonEnv = {
    TZ = "America/Toronto";
    PUID = toString uid;
    PGID = toString gid;
  };

  envFlags = env:
    lib.concatStringsSep " " (
      lib.mapAttrsToList (k: v: "-e ${k}=${v}") env
    );

  # Python script to set qBittorrent password and save_path via API
  qbitSetupScript = pkgs.writeScript "qbit-setup.py" ''
    import http.cookiejar, urllib.request, urllib.parse, json, sys
    temp_pass = sys.argv[1]
    new_pass = sys.argv[2]
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    login_data = urllib.parse.urlencode({'username': 'admin', 'password': temp_pass}).encode()
    req = urllib.request.Request('http://127.0.0.1:8080/api/v2/auth/login', data=login_data)
    opener.open(req)
    pw_data = urllib.parse.urlencode({'json': json.dumps({'web_ui_password': new_pass, 'save_path': '/downloads'})}).encode()
    req2 = urllib.request.Request('http://127.0.0.1:8080/api/v2/app/setPreferences', data=pw_data)
    opener.open(req2)
    print('qBittorrent: password set, save_path=/downloads')
  '';
in
{
  # Create data directories
  system.activationScripts.arr-stack-dirs = lib.mkAfter ''
    mkdir -p ${dataDir}/{sonarr,radarr,lidarr,bazarr,prowlarr,gluetun,qbittorrent}
    chown -R ${toString uid}:${toString gid} ${dataDir}
    # Downloads live on the NAS so large grabs never fill the root disk.
    mkdir -p ${downloadsDir}
    chown -R ${toString uid}:${toString gid} ${downloadsDir} || true
    chown -R ${toString uid}:${toString gid} ${dataDir}
  '';

  # Prowlarr (indexer manager)
  systemd.services.arr-prowlarr = {
    description = "Prowlarr — Indexer Manager (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull lscr.io/linuxserver/prowlarr:latest || true\"";
      ExecStart = pkgs.writeScript "prowlarr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f prowlarr 2>/dev/null || true
        exec ${docker} run -d --name prowlarr \
          --restart unless-stopped \
          --network proxy \
          ${securityFlags} \
          --memory 1g \
          --cpus 1.0 \
          -p 127.0.0.1:9696:9696 \
          -v ${dataDir}/prowlarr:/config \
          ${envFlags commonEnv} \
          lscr.io/linuxserver/prowlarr:latest
      '';
      ExecStop = "${docker} stop prowlarr";
    };
  };

  # Sonarr (TV shows)
  systemd.services.arr-sonarr = {
    description = "Sonarr — TV Show Manager (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull lscr.io/linuxserver/sonarr:latest || true\"";
      ExecStart = pkgs.writeScript "sonarr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f sonarr 2>/dev/null || true
        exec ${docker} run -d --name sonarr \
          --restart unless-stopped \
          --network proxy \
          ${securityFlags} \
          --memory 1g \
          --cpus 1.0 \
          -p 127.0.0.1:8989:8989 \
          -v ${dataDir}/sonarr:/config \
          -v ${mediaDir}:/media \
          -v ${mediaDir}/tv:/tv \
          -v ${downloadsDir}:/downloads \
          ${envFlags commonEnv} \
          lscr.io/linuxserver/sonarr:latest
      '';
      ExecStop = "${docker} stop sonarr";
    };
  };

  # Radarr (Movies)
  systemd.services.arr-radarr = {
    description = "Radarr — Movie Manager (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull lscr.io/linuxserver/radarr:latest || true\"";
      ExecStart = pkgs.writeScript "radarr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f radarr 2>/dev/null || true
        exec ${docker} run -d --name radarr \
          --restart unless-stopped \
          --network proxy \
          ${securityFlags} \
          --memory 1g \
          --cpus 1.0 \
          -p 127.0.0.1:7878:7878 \
          -v ${dataDir}/radarr:/config \
          -v ${mediaDir}:/media \
          -v ${mediaDir}/movies:/movies \
          -v ${downloadsDir}:/downloads \
          ${envFlags commonEnv} \
          lscr.io/linuxserver/radarr:latest
      '';
      ExecStop = "${docker} stop radarr";
    };
  };

  # Lidarr (Music)
  systemd.services.arr-lidarr = {
    description = "Lidarr — Music Manager (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull ghcr.io/hotio/lidarr:pr-plugins || true\"";
      ExecStart = pkgs.writeScript "lidarr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f lidarr 2>/dev/null || true
        exec ${docker} run -d --name lidarr \
          --restart unless-stopped \
          --network proxy \
          ${securityFlags} \
          --memory 1g \
          --cpus 1.0 \
          -p 127.0.0.1:8686:8686 \
          -v ${dataDir}/lidarr:/config \
          -v ${mediaDir}:/media \
          -v ${mediaDir}/music:/music \
          -v ${downloadsDir}:/downloads \
          ${envFlags commonEnv} \
          ghcr.io/hotio/lidarr:pr-plugins
      '';
      ExecStop = "${docker} stop lidarr";
    };
  };

  # Bazarr (Subtitles)
  systemd.services.arr-bazarr = {
    description = "Bazarr — Subtitle Manager (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull lscr.io/linuxserver/bazarr:latest || true\"";
      ExecStart = pkgs.writeScript "bazarr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f bazarr 2>/dev/null || true
        exec ${docker} run -d --name bazarr \
          --restart unless-stopped \
          --network proxy \
          ${bazarrSecurityFlags} \
          --memory 1g \
          --cpus 1.0 \
          -p 127.0.0.1:6767:6767 \
          -v ${dataDir}/bazarr:/config \
          -v ${mediaDir}/movies:/movies \
          -v ${mediaDir}/tv:/tv \
          ${envFlags commonEnv} \
          lscr.io/linuxserver/bazarr:latest
      '';
      ExecStop = "${docker} stop bazarr";
    };
  };

  # Gluetun (VPN tunnel for qBittorrent)
  systemd.services.arr-gluetun = {
    description = "Gluetun — VPN Tunnel for qBittorrent (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull qmcgaw/gluetun:latest || true\"";
      ExecStart = pkgs.writeScript "gluetun-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f gluetun 2>/dev/null || true
        exec ${docker} run -d --name gluetun \
          --restart unless-stopped \
          --network proxy \
          --cap-add NET_ADMIN \
          --device /dev/net/tun:/dev/net/tun \
          --security-opt no-new-privileges \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 50 \
          -p 127.0.0.1:6881:6881 \
          -p 127.0.0.1:6881:6881/udp \
          -p 127.0.0.1:8084:8080 \
          -v ${dataDir}/gluetun:/gluetun \
          -e VPN_SERVICE_PROVIDER=nordvpn \
          -e VPN_TYPE=wireguard \
          -e WIREGUARD_PRIVATE_KEY=$(cat ${config.sops.secrets."nordvpn-wg-key".path}) \
          -e DOT=on \
          -e HTTPPROXY=on \
          -e DNS_ADFILTER_BLOCK_ENABLED=on \
          -e SOCKS5_ENABLED=on \
          -e SERVER_COUNTRIES=Canada \
          -e SOCKS5_LISTENING_ADDRESS=:1080 \
          -e TZ=America/Toronto \
          qmcgaw/gluetun:latest
      '';
      ExecStop = "${docker} stop gluetun";
    };
  };

  # qBittorrent (torrent client, traffic through Gluetun)
  systemd.services.arr-qbittorrent = {
    description = "qBittorrent — Torrent Client (Docker, via Gluetun VPN)";
    after = [ "network.target" "docker.service" "arr-gluetun.service" ];
    requires = [ "docker.service" "arr-gluetun.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull lscr.io/linuxserver/qbittorrent:4.6.6 || true\"";
      ExecStart = pkgs.writeScript "qbittorrent-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f qbittorrent 2>/dev/null || true
        exec ${docker} run -d --name qbittorrent \
          --restart unless-stopped \
          --network container:gluetun \
          --cap-drop ALL \
          --cap-add SETGID \
          --cap-add SETUID \
          --cap-add DAC_OVERRIDE \
          --security-opt no-new-privileges \
          --pids-limit 100 \
          --memory 1g \
          --cpus 2.0 \
          -v ${dataDir}/qbittorrent:/config \
          -v ${downloadsDir}:/downloads \
          -e TZ=America/Toronto \
          -e PUID=${toString uid} \
          -e PGID=${toString gid} \
          -e WEBUI_PORT=8080 \
          lscr.io/linuxserver/qbittorrent:4.6.6
      '';
      ExecStop = "${docker} stop qbittorrent";
      ExecStartPost = pkgs.writeScript "qbittorrent-poststart" ''
        #!${pkgs.bash}/bin/bash
        # Wait for qBittorrent WebUI to be ready
        for i in $(seq 1 30); do
          ${docker} exec qbittorrent wget -q -O /dev/null http://127.0.0.1:8080/ 2>/dev/null && break
          sleep 1
        done
        # Get temp password from logs
        TEMP_PASS=$(${docker} logs qbittorrent 2>&1 | grep "temporary password" | tail -1 | sed 's/.*session: //')
        if [ -n "$TEMP_PASS" ]; then
          QBIT_PW=$(cat ${config.sops.secrets."qbittorrent-password".path})
          ${docker} cp ${qbitSetupScript} qbittorrent:/tmp/qbit-setup.py
          ${docker} exec qbittorrent python3 /tmp/qbit-setup.py "$TEMP_PASS" "$QBIT_PW"
          ${docker} exec qbittorrent rm /tmp/qbit-setup.py
        fi
        # Fix proxy settings — qBittorrent writes wrong defaults on first boot.
        # Use SOCKS5 on 127.0.0.1:1080 (gluetun). Unlike HTTP/8888, SOCKS5 can
        CONF="/var/lib/arr-stack/qbittorrent/qBittorrent/qBittorrent.conf"
        NEEDS_FIX=0
        if grep -q "Hostname=172.18.0.8" "$CONF" 2>/dev/null || grep -q "Type=3$" "$CONF" 2>/dev/null; then
          NEEDS_FIX=1
        fi
        if [ "$NEEDS_FIX" = "1" ]; then
          sed -i \
            -e 's/^Hostname=.*/Hostname=127.0.0.1/' \
            -e 's/^Port=.*/Port=1080/' \
            -e 's/^Type=.*/Type=2/' \
            -e 's/^UseProxyForDHTConnections=.*/UseProxyForDHTConnections=true/' \
            "$CONF"
          # Also fix the parent config if it exists
          PARENT_CONF="/var/lib/arr-stack/qbittorrent/qBittorrent.conf"
          if [ -f "$PARENT_CONF" ]; then
            sed -i \
              -e 's/^Hostname=.*/Hostname=127.0.0.1/' \
              -e 's/^Port=.*/Port=1080/' \
              -e 's/^Type=.*/Type=2/' \
              -e 's/^UseProxyForDHTConnections=.*/UseProxyForDHTConnections=true/' \
              "$PARENT_CONF"
          fi
          ${docker} restart qbittorrent
          # Wait for it to come back
          for i in $(seq 1 30); do
            ${docker} exec qbittorrent wget -q -O /dev/null http://127.0.0.1:8080/ 2>/dev/null && break
            sleep 1
          done
        fi
      '';
    };
  };



  # Byparr — Cloudflare bypass proxy for Prowlarr
  systemd.services.arr-byparr = {
    description = "Byparr — Cloudflare Bypass Proxy (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull ghcr.io/flaresolverr/flaresolverr:latest || true\"";
      ExecStart = pkgs.writeScript "byparr-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f byparr 2>/dev/null || true
        exec ${docker} run -d --name byparr \
          --restart unless-stopped \
          --network proxy \
          --shm-size=2g \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 2g \
          --cpus 2.0 \
          --pids-limit 200 \
          -p 127.0.0.1:8191:8191 \
          -e LOG_LEVEL=info \
          -e TZ=America/Toronto \
          -e BROWSER_ARGS="--no-sandbox" \
          ghcr.io/flaresolverr/flaresolverr:latest
      '';
      ExecStop = "${docker} stop byparr";
    };
  };

  # --- Dedicated gluetun for SearXNG with rotating NordVPN exit ---
  # Separate container so SearXNG egress rotates independently of torrent VPN.
  systemd.services.gluetun-search = {
    description = "Gluetun — Rotating VPN Tunnel for SearXNG (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} pull qmcgaw/gluetun:latest || true\"";
      ExecStart = pkgs.writeScript "gluetun-search-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f gluetun-search 2>/dev/null || true
        exec ${docker} run -d --name gluetun-search \
          --restart unless-stopped \
          --network proxy \
          --cap-add NET_ADMIN \
          --device /dev/net/tun:/dev/net/tun \
          --security-opt no-new-privileges \
          --memory 512m \
          --cpus 1.0 \
          --pids-limit 50 \
          -p 127.0.0.1:8088:8888 \
          -v ${dataDir}/gluetun-search:/gluetun \
          -e VPN_SERVICE_PROVIDER=nordvpn \
          -e VPN_TYPE=wireguard \
          -e WIREGUARD_PRIVATE_KEY=$(cat ${config.sops.secrets."nordvpn-wg-key".path}) \
          -e DOT=on \
          -e HTTPPROXY=on \
          -e DNS_ADFILTER_BLOCK_ENABLED=on \
          -e SOCKS5_ENABLED=on \
          -e SOCKS5_LISTENING_ADDRESS=:1080 \
          -e SERVER_COUNTRIES=Netherlands \
          -e TZ=America/Toronto \
          qmcgaw/gluetun:latest
      '';
      ExecStop = "${docker} stop gluetun-search";
    };
  };

  # Rotation script: pick a random WireGuard hostname, restart gluetun-search,
  # then restart searxng (its per-engine suspensions live in memory and only
  # clear on container restart).
  systemd.services.gluetun-search-rotate = {
    description = "Rotate SearXNG gluetun exit to a random NordVPN server";
    after = [ "gluetun-search.service" "searxng.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeScript "gluetun-search-rotate" ''
        #!${pkgs.bash}/bin/bash
        set -uo pipefail
        CACHE="${dataDir}/gluetun/servers/nordvpn.json"
        GU=gluetun-search
        SX=searxng
        docker="${docker}"
        WGKEY=$(cat ${config.sops.secrets."nordvpn-wg-key".path})
        for attempt in $(seq 1 8); do
          HOSTNAME="$(${pkgs.python3}/bin/python3 -c 'import json,random,sys; d=json.load(open(sys.argv[1])); w=[s["hostname"] for s in d["servers"] if "wireguard" in s["vpn"].lower()]; print(random.choice(w))' "$CACHE")"
          echo "[rotate] $(date -u +%FT%TZ) attempt $attempt -> $HOSTNAME"
          "$docker" rm -f "$GU" 2>/dev/null || true
          "$docker" run -d --name "$GU" \
            --restart unless-stopped \
            --network proxy \
            --cap-add NET_ADMIN \
            --device /dev/net/tun:/dev/net/tun \
            --security-opt no-new-privileges \
            --memory 512m --cpus 1.0 --pids-limit 50 \
            -p 127.0.0.1:8088:8888 \
            -v ${dataDir}/gluetun-search:/gluetun \
            -e VPN_SERVICE_PROVIDER=nordvpn \
            -e VPN_TYPE=wireguard \
            -e WIREGUARD_PRIVATE_KEY="$WGKEY" \
            -e DOT=on -e HTTPPROXY=on -e DNS_ADFILTER_BLOCK_ENABLED=on \
            -e SOCKS5_ENABLED=on -e SOCKS5_LISTENING_ADDRESS=:1080 \
            -e SERVER_HOSTNAMES="$HOSTNAME" \
            -e TZ=America/Toronto \
            qmcgaw/gluetun:latest >/dev/null
          ok=0
          for i in $(seq 1 20); do
            if "$docker" exec "$GU" wget -qO- http://127.0.0.1:9999 >/dev/null 2>&1; then ok=1; break; fi
            sleep 3
          done
          if [ "$ok" -ne 1 ]; then echo "[rotate] $HOSTNAME failed healthcheck"; continue; fi
          if "$docker" exec "$GU" wget -qO- --timeout=10 http://ip-api.com/json >/dev/null 2>&1; then
            echo "[rotate] $HOSTNAME verified working"
            break
          else
            echo "[rotate] $HOSTNAME tunnel up but no egress, retrying"
          fi
        done
        "$docker" restart "$SX" >/dev/null 2>&1 || true
        echo "[rotate] done"
      '';
    };
  };

  # --- donsetch HTTP shim (exposes donsetch CLI to Trawl on the proxy net) ---
  systemd.services.donsetch-shim = {
    description = "donsetch search shim (HTTP) for Trawl";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "''${pkgs.bash}/bin/bash -c \"''${docker} build -t donsetch-shim:latest /etc/nixos/scripts/donsetch-shim || true\"";
      ExecStart = pkgs.writeScript "donsetch-shim-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f donsetch-shim 2>/dev/null || true
        exec ${docker} run -d --name donsetch-shim \
          --restart unless-stopped \
          --network proxy \
          --dns 1.1.1.1 \
          --dns 8.8.8.8 \
          -v /opt/donsetch:/opt/donsetch:ro \
          -v /nix/store:/nix/store:ro \
          donsetch-shim:latest
      '';
      ExecStop = "${docker} stop donsetch-shim";
    };
  };

  # NordVPN service credentials
  sops.secrets."nordvpn-user" = {};
  sops.secrets."nordvpn-pass" = {};
  sops.secrets."nordvpn-wg-key" = {};
  sops.secrets."qbittorrent-password" = {};
}
