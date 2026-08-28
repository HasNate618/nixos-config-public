# Brightspace MCP — D2L course management via MCP
# HTTP bridge (supergateway) with xvfb for Playwright auth
# Auth: docker exec -it brightspace-mcp-http bash -c 'DISPLAY=:99 node build/auth-cli.js'
# Source: /var/lib/brightspace-mcp/ (built from Dockerfile)
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  srcDir = "/var/lib/brightspace-mcp";
  configDir = "/var/lib/brightspace-mcp-config";
  sessionDir = "/var/lib/brightspace-mcp-session";
in
{
  systemd.tmpfiles.rules = [
    "d ${configDir} 0755 nate users -"
    "d ${sessionDir} 0755 nate users -"
  ];

  # Rebuild the image when source changes
  systemd.services.brightspace-mcp-build = {
    description = "Build Brightspace MCP Docker image";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${docker} build -t brightspace-mcp:latest ${srcDir}";
    };
  };

  systemd.services.brightspace-mcp-http = {
    description = "Brightspace MCP HTTP Bridge (supergateway + xvfb)";
    after = [ "network.target" "docker.service" "brightspace-mcp-build.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeScript "brightspace-mcp-http-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f brightspace-mcp-http 2>/dev/null || true
        exec ${docker} run -d --name brightspace-mcp-http \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:11234:3000 \
          --cap-drop ALL \
          --shm-size=1g \
          --security-opt no-new-privileges \
          --memory 2g \
          --cpus 2.0 \
          --pids-limit 200 \
          -v ${configDir}:/root/.brightspace-mcp:ro \
          -v ${sessionDir}:/root/.d2l-session \
          brightspace-mcp:latest \
          sh -c 'Xvfb :99 -screen 0 1280x720x24 &>/dev/null & DISPLAY=:99 npx -y supergateway --stdio "node build/index.js" --port 3000 --outputTransport streamableHttp'
      '';
      ExecStop = "${docker} stop brightspace-mcp-http";
    };
  };
}
