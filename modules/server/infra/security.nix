# CrowdSec — intrusion detection system for the homelab
# Just the detection engine (no firewall bouncer yet — that needs nftables integration)
# Security: bound to localhost, cap-drop ALL, no-new-privileges
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  # Create directories for CrowdSec
  systemd.tmpfiles.rules = [
    "d /var/lib/crowdsec 0755 root root -"
    "d /var/lib/crowdsec/config 0755 root root -"
    "d /var/lib/crowdsec/data 0755 root root -"
  ];

  # CrowdSec acquisition config - syslog + Caddy access logs
  environment.etc."crowdsec/acquis.yaml".text = ''
    filenames:
      - /var/log/*.log
      - /var/log/journal
    labels:
      type: syslog
    ---
    filenames:
      - /var/log/caddy/access.log
    labels:
      type: caddy
  '';

  # CrowdSec container service
  systemd.services.crowdsec = {
    description = "CrowdSec intrusion detection";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull crowdsecurity/crowdsec:latest || true'";
      ExecStart = pkgs.writeScript "crowdsec-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f crowdsec 2>/dev/null || true
        exec ${docker} run -d --name crowdsec \
          --restart unless-stopped \
          --cap-drop ALL \
          --cap-add NET_ADMIN \
          --cap-add NET_RAW \
          --security-opt no-new-privileges \
          --read-only \
          --tmpfs /tmp:rw,noexec,nosuid,size=64m \
          --tmpfs /var/run:rw,noexec,nosuid,size=1m \
          --memory 256m \
          --cpus 0.5 \
          --pids-limit 50 \
          -p 127.0.0.1:8080:8080 \
          -v /var/lib/crowdsec/config:/etc/crowdsec \
          -v /var/lib/crowdsec/data:/var/lib/crowdsec/data \
          -v /var/log:/var/log:ro \
          -e TZ="America/New_York" \
          crowdsecurity/crowdsec:latest
      '';
      ExecStop = "${docker} stop crowdsec";
    };
  };
}
