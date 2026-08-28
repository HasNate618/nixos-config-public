# Open WebUI — ChatGPT-like interface for LLMs
# Running as Docker container, connects to Bifrost for model routing
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/open-webui 0755 1000 1000 -"
  ];

  systemd.services.open-webui = {
    description = "Open WebUI (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "5s";
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull ghcr.io/open-webui/open-webui:main || true'";
      ExecStart = pkgs.writeScript "open-webui-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f open-webui 2>/dev/null || true
        exec ${docker} run -d --name open-webui \
          --restart unless-stopped \
          --network proxy \
          -p 127.0.0.1:18080:8080 \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --tmpfs /tmp:rw,noexec,nosuid,size=64m \
          -v /var/lib/open-webui:/app/backend/data \
          --memory 2g \
          --cpus 2.0 \
          --pids-limit 200 \
          -e WEBUI_URL="http://webui.home.lab" \
          -e "CORS_ALLOW_ORIGIN=http://webui.home.lab;http://home.lab;http://home;http://10.0.0.45" \
          -e WEBUI_SESSION_COOKIE_SECURE="false" \
          -e WEBUI_AUTH_COOKIE_SECURE="false" \
          -e TERMINAL_SERVER_CONNECTIONS='[{"id": "local", "name": "Home Terminal", "url": "http://open-terminal:8000", "api_key": "'"$(cat ${config.sops.secrets."open-terminal-api-key".path})"'", "enabled": true}]' \
          -e EXTERNAL_DOCUMENT_LOADER_URL="http://pdf-parse:8000" \
          -e DOCLING_SERVER_URL="http://pdf-parse:8000" \
          -e ENABLE_SIGNUP="false" \
          ghcr.io/open-webui/open-webui:main
      '';
      ExecStop = "${docker} stop open-webui";
    };
  };
}
