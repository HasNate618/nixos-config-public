# DNS — AdGuard Home
{ config, lib, pkgs, ... }: {

  services.adguardhome = {
    enable = true;
    openFirewall = true;
    mutableSettings = true;

    settings = {
      http = {
        address = "0.0.0.0:3000";
        session_ttl = "12h";
      };

      dns = {
        # Explicit binds instead of 0.0.0.0 — frees 10.0.0.11:53 for the
        # LAN split-horizon resolver (dnsmasq below).
        #   10.0.0.10    = LAN clients (get tailnet-IP answers via rewrites)
        #   100.64.0.10 = Tailscale clients (tailnet DNS override)
        #   127.0.0.1    = host + Docker embedded DNS (containers forward via host loopback)
        # NOTE: if a new Docker bridge network is created, containers on it
        # still resolve via 127.0.0.1 (embedded DNS) — no per-gateway binds needed.
        bind_hosts = [ "10.0.0.10" "100.64.0.10" "127.0.0.1" ];
        port = 53;
        upstream_dns = [
          "https://dns.quad9.net/dns-query"
          "https://cloudflare-dns.com/dns-query"
        ];
        bootstrap_dns = [ "9.9.9.9" "1.1.1.1" ];
        cache_size = 100000;
        cache_ttl_min = 3600;
        cache_ttl_max = 86400;
        cache_optimistic_enabled = true;
        dnssec_enabled = true;
      };

      query_log = {
        type = "sqlite";
        interval = "2160h";
      };

      statistics = {
        type = "sqlite";
        interval = "2160h";
      };

      tls.enabled = false;
      dhcp.enabled = false;
    };
  };

  # LAN split-horizon resolver. LAN devices (no Tailscale) point at
  # 10.0.0.11; it answers *.home.lab -> 10.0.0.10 (Caddy's LAN IP) and
  # forwards everything else to AdGuard so LAN users keep ad-blocking.
  # Remote/Tailscale clients are unaffected (they still query AdGuard's
  # tailnet IP and get 100.64.0.10 answers).
  services.dnsmasq = {
    enable = true;
    resolveLocalQueries = false;  # must be false — module would also bind 127.0.0.1:53 (AdGuard conflict)
    settings = {
      "bind-interfaces" = true;
      "listen-address" = "10.0.0.11";
      "no-resolv" = true;
      # /etc/hosts contains "100.64.0.10 home.lab" (host-local workaround);
      # without no-hosts it overrides the address directive for the bare
      # domain. LAN clients must get the LAN IP, so ignore hosts entirely.
      "no-hosts" = true;
      "server" = [ "10.0.0.10" ];
      # /.home.lab/ (≡ /home.lab/) matches the bare domain AND subdomains;
      # the real gotcha was /etc/hosts, handled by no-hosts above
      "address" = [ "/.home.lab/10.0.0.10" ];
      "cache-size" = 1000;
    };
  };

  # dnsmasq must start after 10.0.0.11 is up (bind-interfaces).
  # wait-online (anyInterface) guarantees the wired link + addresses.
  # Restart=always + no start limit: a transient bind failure (e.g. DHCP
  # renew reconfig) self-heals instead of hitting start-limit-hit.
  systemd.services.dnsmasq = {
    after = [ "systemd-networkd.service" "systemd-networkd-wait-online.service" ];
    wants = [ "systemd-networkd.service" "systemd-networkd-wait-online.service" ];
    startLimitIntervalSec = 0;
    serviceConfig = {
      # mkForce: the dnsmasq NixOS module sets Restart=on-failure itself
      Restart = lib.mkForce "always";
      RestartSec = "5";
    };
  };

  systemd.services.adguardhome = {
    postStart = lib.mkAfter ''
      sleep 3
      ${pkgs.curl}/bin/curl -s -X POST http://127.0.0.1:3000/control/rewrite/add \
        -H "Content-Type: application/json" \
        -d '{"domain":"home.lab","answer":"100.64.0.10"}' || true
      ${pkgs.curl}/bin/curl -s -X POST http://127.0.0.1:3000/control/rewrite/add \
        -H "Content-Type: application/json" \
        -d '{"domain":"*.home.lab","answer":"100.64.0.10"}' || true
    '';
  };

  networking.firewall.allowedTCPPorts = [ 53 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
}
