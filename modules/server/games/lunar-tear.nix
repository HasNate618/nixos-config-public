# Lunar Tear — self-hosted private server for a discontinued mobile game.
#
# Three containers from the upstream published images, pinned by digest:
#   lunar-tear-cdn     octo-cdn      HTTP asset CDN (serves list.bin + asset bundles)
#   lunar-tear-server  lunar-tear    gRPC game server + admin webhook
#   lunar-tear-auth    auth-server   username/password login (replaces the dead FB SDK)
#
# CLIENT-FACING ADDRESSES ARE BAKED INTO THE PATCHED APK. The values below
# (tsIp / grpcPort / cdnPort / authPort) MUST match the arguments the client
# patcher was run with, or the client will silently fail to fetch assets:
#   gRPC 100.64.0.10:8042   CDN 100.64.0.10:8043   auth 100.64.0.10:8044
#
# Ports are published ONLY on the Tailscale address, so this stack is reachable
# from tailnet devices (the phone) and NOT from the LAN — note that docker's
# published ports bypass the NixOS firewall entirely, so binding to the tailnet
# IP (rather than 0.0.0.0) is what actually keeps it private.
#
# The upstream server image's entrypoint (entrypoint.sh) ignores extra argv and
# only reads LUNAR_* env vars, so it cannot be told to run with --no-register.
# We therefore override the entrypoint and run the goose migration step
# explicitly as a one-shot before starting the server.
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  iproute = "${pkgs.iproute2}/bin/ip";

  net = "lunar-tear";

  tsIp = "100.64.0.10";
  grpcPort = 8042;
  cdnPort = 8043;
  authPort = 8044;
  adminPort = 8045;

  assetsDir = "/mnt/homelab-full/lunar-tear/assets";
  dataDir = "/var/lib/lunar-tear";
  dbDir = "${dataDir}/db";

  # pinned by digest so a moved :latest can't silently change the server
  imgServer = "kretts/lunar-tear@sha256:0e774b54b2efb0efdf4a34ee35af71b47e4979e5e8cd434ef7bd9d4cc150ce50";
  imgCdn = "kretts/octo-cdn@sha256:55ba575f5cf7e4a809685e5b837872b1ae24ab0f73908092bab6dc643f16fd04";
  imgAuth = "kretts/auth-server@sha256:6b10c12b6df918dbc264cdc65efc0869013f92e75702fc43b44fddc44ae86e31";

  # Fail loudly if the asset tree is absent (the server exits early without it
  # anyway). Also forces the CIFS automount to activate before docker binds it.
  assetsGuard = ''
    if [ ! -f ${assetsDir}/release/20240404193219.bin.e ]; then
      echo "lunar-tear: asset tree missing ${assetsDir}/release/20240404193219.bin.e" >&2
      exit 1
    fi
  '';

  # tailscale0 may not have its address yet when this unit is ordered at boot.
  waitForIp = ''
    for _ in $(seq 1 20); do
      ${iproute} -o addr show tailscale0 2>/dev/null | grep -q ${tsIp} && break
      sleep 3
    done
  '';
in
{
  systemd.tmpfiles.rules = [
    # uid/gid 1000 matches USER 1000 in the upstream images — they must be able
    # to write the SQLite databases.
    "d ${dataDir} 0755 1000 1000 -"
    "d ${dbDir} 0755 1000 1000 -"
  ];

  # ── asset CDN ─────────────────────────────────────────────────────────────
  systemd.services.lunar-tear-cdn = {
    description = "Lunar Tear asset CDN (octo-cdn)";
    after = [ "network-online.target" "docker.service" "docker-networks.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${docker} pull ${imgCdn}";
      ExecStart = pkgs.writeScript "lunar-tear-cdn-start" ''
        #!${pkgs.bash}/bin/bash
        set -e
        ${assetsGuard}
        ${docker} rm -f lunar-tear-cdn 2>/dev/null || true
        exec ${docker} run -d --name lunar-tear-cdn \
          --restart unless-stopped \
          --network ${net} \
          --cap-drop ALL \
          --cap-add NET_BIND_SERVICE \
          --security-opt no-new-privileges \
          --memory 1g --cpus 2.0 --pids-limit 300 \
          -p ${tsIp}:${toString cdnPort}:8080 \
          -v ${assetsDir}:/opt/octo-cdn/assets:ro \
          ${imgCdn} \
          --listen 0.0.0.0:8080 \
          --public-addr ${tsIp}:${toString cdnPort}
      '';
      ExecStop = "${docker} stop lunar-tear-cdn";
    };
  };

  # ── auth server ───────────────────────────────────────────────────────────
  systemd.services.lunar-tear-auth = {
    description = "Lunar Tear auth server";
    after = [ "network-online.target" "docker.service" "docker-networks.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${docker} pull ${imgAuth}";
      ExecStart = pkgs.writeScript "lunar-tear-auth-start" ''
        #!${pkgs.bash}/bin/bash
        set -e
        ${waitForIp}
        ${docker} rm -f lunar-tear-auth 2>/dev/null || true
        exec ${docker} run -d --name lunar-tear-auth \
          --restart unless-stopped \
          --network ${net} \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 256m --cpus 1.0 --pids-limit 200 \
          -p ${tsIp}:${toString authPort}:3000 \
          -v ${dbDir}:/opt/auth-server/db \
          ${imgAuth} \
          --listen 0.0.0.0:3000 \
          --db db/auth.db \
          --no-register \
          --secret $(cat ${config.sops.secrets."lunar-auth-secret".path})
      '';
      ExecStop = "${docker} stop lunar-tear-auth";
    };
  };

  # ── game server ───────────────────────────────────────────────────────────
  systemd.services.lunar-tear-server = {
    description = "Lunar Tear game server (gRPC)";
    after = [ "network-online.target" "docker.service" "docker-networks.service"
              "lunar-tear-cdn.service" "lunar-tear-auth.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${docker} pull ${imgServer}";
      ExecStart = pkgs.writeScript "lunar-tear-server-start" ''
        #!${pkgs.bash}/bin/bash
        set -e
        ${assetsGuard}
        ${waitForIp}
        # goose migrations — normally done by entrypoint.sh, which we bypass
        ${docker} run --rm --network none \
          -v ${dbDir}:/opt/lunar-tear/db \
          --entrypoint /bin/sh ${imgServer} \
          -c "mkdir -p db && goose -dir migrations sqlite3 db/game.db up"
        ${docker} rm -f lunar-tear-server 2>/dev/null || true
        exec ${docker} run -d --name lunar-tear-server \
          --restart unless-stopped \
          --network ${net} \
          --cap-drop ALL \
          --cap-add NET_BIND_SERVICE \
          --security-opt no-new-privileges \
          --memory 2g --cpus 2.0 --pids-limit 500 \
          -p ${tsIp}:${toString grpcPort}:8003 \
          -p 127.0.0.1:${toString adminPort}:8082 \
          -e LUNAR_ADMIN_TOKEN=$(cat ${config.sops.secrets."lunar-admin-token".path}) \
          -v ${dbDir}:/opt/lunar-tear/db \
          -v ${assetsDir}:/opt/lunar-tear/assets:ro \
          --entrypoint /opt/lunar-tear/lunar-tear ${imgServer} \
          --listen 0.0.0.0:8003 \
          --public-addr ${tsIp}:${toString grpcPort} \
          --octo-url http://${tsIp}:${toString cdnPort} \
          --auth-url http://lunar-tear-auth:3000 \
          --admin-listen 0.0.0.0:8082 \
          --no-register
      '';
      ExecStop = "${docker} stop lunar-tear-server";
    };
  };
}
