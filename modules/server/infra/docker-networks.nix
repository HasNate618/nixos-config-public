# Docker network setup for homelab services
# Creates the 'proxy' and 'firecrawl-backend' networks if they don't exist
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.services.docker-networks = {
    description = "Create Docker networks for homelab services";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "docker-networks" ''
        #!${pkgs.bash}/bin/bash
        ${docker} network create proxy 2>/dev/null || true
        ${docker} network create firecrawl-backend 2>/dev/null || true
      '';
    };
  };
}
