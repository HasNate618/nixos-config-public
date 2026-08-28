# SearXNG — Privacy-respecting metasearch engine
# Used by trawl for web search (replaced DeGoog as primary backend)
# Engine requests route through gluetun (NordVPN) via HTTP proxy.
# NOTE: NordVPN exit IPs can get flagged (429/CAPTCHA) — fix is `docker restart gluetun`
# to rotate the exit, NOT removing the proxy. google cse stays removed (keyless, always 429).
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  settingsFile = pkgs.writeText "searxng-settings.yml" ''
    # SearXNG settings — optimized for trawl agent use
    use_default_settings:
      engines:
        remove:
          - google cse  # keyless default engine — always 429, pollutes results

    general:
      instance_name: "HomeLab Search"
      debug: false

    search:
      safe_search: 0
      autocomplete: "google"
      default_lang: "en"
      formats:
        - html
        - json
      # Weight engines by quality
      default_timer: 3


    server:
      # __SEARXNG_SECRET_KEY__ is replaced with the real sops value at service start
      secret_key: "__SEARXNG_SECRET_KEY__"
      bind_address: "0.0.0.0"
      port: 8080
      limiter: false
      image_proxy: false

    ui:
      default_theme: simple
      static_use_hash: true

    outgoing:
      request_timeout: 5.0
      max_request_timeout: 15.0
      useragent_suffix: ""
      pool_connections: 100
      pool_maxsize: 20
      proxies:
        http: http://gluetun:8888
        https: http://gluetun:8888

    engines:
      # Google - best general results — NOTE: inactive by default in this image
      # (JS wall), kept for when Google relaxes scraping
      - name: google
        engine: google
        shortcut: go
        disabled: false
        inactive: true
        weight: 1.2

      # Bing - reliable through VPN, tolerates scrapers (re-added 2026-08-15)
      - name: bing
        engine: bing
        shortcut: bi
        disabled: false
        weight: 1.0

      # Brave Search - excellent quality
      - name: brave
        engine: brave
        shortcut: br
        disabled: false
        weight: 1.1

      # DuckDuckGo - good variety, no tracking
      - name: duckduckgo
        engine: duckduckgo
        shortcut: ddg
        disabled: false
        weight: 1.0

      # Startpage - Google results with privacy
      - name: startpage
        engine: startpage
        shortcut: sp
        disabled: false
        weight: 0.9

      # Wikipedia - for reference queries
      - name: wikipedia
        engine: wikipedia
        shortcut: wp
        disabled: false
        weight: 0.8

      # Mojeek - independent engine, good for diversity
      - name: mojeek
        engine: mojeek
        shortcut: mj
        disabled: false
        weight: 0.6

      # Qwant - European engine
      - name: qwant
        engine: qwant
        shortcut: qw
        disabled: false
        weight: 0.6
  '';
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/searxng 0755 root root -"
  ];

  systemd.services.searxng = {
    description = "SearXNG Metasearch Engine (Docker)";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "searxng";
      ExecStart = pkgs.writeShellScript "searxng-start" ''
        set -euo pipefail
        ${docker} rm -f searxng 2>/dev/null || true
        # /run is tmpfs: Docker's auto-restart (restart=unless-stopped) can create
        # this bind source as a DIRECTORY before the unit runs — remove any such
        # poison so sed can write the real file (2026-08-13 boot race).
        rm -rf /run/searxng/settings.yml
        test -s ${config.sops.secrets."searxng-secret-key".path} || { echo "searxng secret missing" >&2; exit 1; }
        # sops value only exists at runtime — substitute into a generated settings file
        sed "s|__SEARXNG_SECRET_KEY__|$(cat ${config.sops.secrets."searxng-secret-key".path})|" \
          ${settingsFile} > /run/searxng/settings.yml
        exec ${docker} run -d --name searxng \
          --restart unless-stopped \
          --network proxy \
          --cap-drop ALL \
          --security-opt no-new-privileges \
          --memory 512m \
          --cpus 1.0 \
          -p 127.0.0.1:8888:8080 \
          -v /run/searxng/settings.yml:/etc/searxng/settings.yml:ro \
          searxng/searxng:latest
      '';
      ExecStop = "${docker} stop searxng";
    };
  };
}
