# Caddy — reverse proxy for all homelab services
# Running as Docker container to avoid NixOS module quirks
# HTTP only — Tailscale encrypts the wire, no cert management needed
# LAN: http://home.lab (port 80)
# Tailscale: http://home.lab via split DNS → 100.64.0.10
# 10.0.0.10 only serves /jellyfin for smart TVs
{ pkgs, lib, config, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  caddyfile = pkgs.writeText "Caddyfile" ''
    {
      order crowdsec before reverse_proxy
      crowdsec {
        api_url http://127.0.0.1:8080
        api_key {$CROWDSEC_API_KEY}
        ticker_interval 15s
      }
      log {
        output file /var/log/caddy/access.log {
          roll_size 10mb
          roll_keep 5
        }
        format json
      }
    }

    # Smart TV access — ONLY /jellyfin on the IP
    http://10.0.0.10 {
      handle /jellyfin* {
        uri strip_prefix /jellyfin
        reverse_proxy 127.0.0.1:8096
      }
      handle {
        respond "Access denied. Use home.lab instead." 403
      }
    }

    # Main block — landing page only
    http://home.lab {
      crowdsec
      respond "Homelab NixOS — home.lab" 200
    }

    # AdGuard Home
    http://adguard.home.lab {
      crowdsec
      # Auth is enabled via a bcrypt hash supplied from a sops secret rather
      # than committed here.
      # basic_auth {
      #   admin <bcrypt hash>
      # }
      reverse_proxy 127.0.0.1:3000
    }

    # Bifrost LLM Gateway
    http://bifrost.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:18081
    }
    # EmbeddingGemma 2 local embedding server (text + image + audio)
    http://embeddinggemma.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8081
    }

    # Forgejo Git Forge
    http://forgejo.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:3001
    }

    # DeGoog Search
    http://degoog.home.lab {



      crowdsec



      reverse_proxy 127.0.0.1:18082



    }

    # SearXNG — Privacy search engine (used by trawl)
    http://searxng.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8888
    }



    # Open Terminal — AI shell for Open WebUI
    http://terminal.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:18083
    }

    # Open WebUI
    http://webui.home.lab {
      crowdsec
      handle /ws/* {
        reverse_proxy 127.0.0.1:18080 {
          transport http {
            versions 1.1
          }
          flush_interval -1
        }
      }
      handle {
        reverse_proxy 127.0.0.1:18080 {
          transport http {
            versions 1.1
          }
          flush_interval -1
        }
      }
    }

    # Trawl MCP
    http://trawl.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:11236 {
        transport http {
          versions 1.1
        }
        flush_interval -1
      }
    }


    # HippoCampus (web app — Phase 3; 502 until the app binds :8087)
    http://school.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8087 {
        flush_interval -1
      }
    }

    # HippoCampus over Tailscale HTTPS — required for PWA install on Android
    # (browsers refuse service workers + install over plain HTTP)
    home.tailXXXXXXXX.ts.net {
      crowdsec
      tls /etc/tailscale-certs/home.tailXXXXXXXX.ts.net.crt /etc/tailscale-certs/home.tailXXXXXXXX.ts.net.key
      reverse_proxy 127.0.0.1:8087 {
        flush_interval -1
      }
    }
    # Jellyfin Media Server
    http://jellyfin.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8096
    }

    # Brightspace MCP
    http://brightspace.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:11234 {
        transport http {
          versions 1.1
        }
        flush_interval -1
      }
    }

    # Excalidraw — Virtual Whiteboard
    http://excalidraw.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:11237
    }

    # Excalidraw MCP — Interactive Diagram Server
    http://excalidraw-mcp.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:11238 {
        transport http {
          versions 1.1
        }
        flush_interval -1
      }
    }

    # *arr Stack
    http://sonarr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8989
    }

    http://radarr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:7878
    }

    http://lidarr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8686
    }

    http://bazarr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:6767
    }

    http://prowlarr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:9696
    }

    http://qbit.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8084
    }

    # Dashboard
    http://dashboard.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8083
    }

    # Immich Photo Management
    http://immich.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:2283 {
        transport http {
          versions 1.1
        }
      }
    }

    # Vaultwarden Password Manager
    https://vault.home.lab {
      crowdsec
      tls /data/certs/home.lab.crt /data/certs/home.lab.key
      header Content-Security-Policy ""
      reverse_proxy 127.0.0.1:8222
    }

    # PDF Parser — Docling + PP-OCRv6
    # PDF Parser — Cohere Parse + PyMuPDF
    http://pdf.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8003
    }

    # BentoPDF — client-side PDF toolkit
    http://bento.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8095
    }

    # Whisper Transcriber — Audio to text via GPU
    http://whisper.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8086
    }

    # Uptime Kuma — Uptime Monitoring
    http://monitor.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:3002
    }

    # Netdata — System Metrics
    http://netdata.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:19999
    }

    # ntfy — Push Notifications
    http://ntfy.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8085 {
        header_up X-Real-IP {remote_host}
      }
    }

    # ByParr — Cloudflare bypass proxy
    http://byparr.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8191
    }

    # Nextcloud — cloud.home.lab
    http://cloud.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8082
    }

    # Collabora Online — collabora.home.lab
    http://collabora.home.lab {
      crowdsec
      header -Content-Security-Policy
      reverse_proxy [::1]:9980 {
        transport http {
          versions 1.1
        }
        flush_interval -1
      }
    }


    # FileBrowser — NAS file manager
    http://nas.home.lab {
      crowdsec
      reverse_proxy 127.0.0.1:8089
    }

    # Bazarr — Subtitle Manager

  '';
in
{
  services.caddy.enable = false;

  systemd.tmpfiles.rules = [
    "d /var/lib/caddy 0755 root root -"
    "d /var/log/caddy 0755 root root -"
    "d /var/lib/tailscale/certs 0755 root root -"
  ];

  systemd.services.caddy = {
    description = "Caddy reverse proxy (Docker)";
    after = [ "network-online.target" "docker.service" "adguardhome.service" ];
    wants = [ "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # Non-fatal pull — if DNS isn't ready at boot, use cached image
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull serfriz/caddy-crowdsec:latest || true'";
      ExecStart = pkgs.writeScript "caddy-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f caddy 2>/dev/null || true
        # Retry loop for post-power-cut resilience — Docker/network might not be ready
        for i in 1 2 3 4 5; do
          ${docker} run -d --name caddy \
            --restart unless-stopped \
            --network host \
            --cap-drop ALL \
            --cap-add NET_BIND_SERVICE \
            --security-opt no-new-privileges \
            --read-only \
            --tmpfs /tmp:rw,noexec,nosuid,size=16m \
            --tmpfs /config:rw,noexec,nosuid,size=32m \
            --memory 256m \
            --cpus 0.5 \
            --pids-limit 50 \
            -e CROWDSEC_API_KEY=$(cat ${config.sops.secrets."crowdsec-api-key".path}) \
            -v ${caddyfile}:/etc/caddy/Caddyfile:ro \
            -v /var/lib/caddy:/data \
            -v /var/log/caddy:/var/log/caddy \
            -v /var/lib/tailscale/certs:/etc/tailscale-certs:ro \
            serfriz/caddy-crowdsec:latest caddy run --config /etc/caddy/Caddyfile \
            && exit 0
          echo "caddy run attempt $i failed, retrying in 5s..."
          sleep 5
        done
        exit 1
      '';
      ExecStop = "${docker} stop caddy";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 ];


  systemd.services.tailscale-cert-renew = {
    description = "Renew Tailscale HTTPS certs for the PWA host";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/var/lib/tailscale/certs";
      ExecStart = "${pkgs.tailscale}/bin/tailscale cert home.tailXXXXXXXX.ts.net";
      ExecStartPost = "${docker} exec caddy caddy reload --config /etc/caddy/Caddyfile";
    };
  };

  systemd.timers.tailscale-cert-renew = {
    description = "Weekly Tailscale cert renewal";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
