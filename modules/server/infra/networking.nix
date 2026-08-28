# Server networking — wired, no WiFi, firewall for homelab services
# SECURITY: Only expose ports that MUST be directly accessible.
# Services behind Caddy reverse proxy do NOT need direct port access.
{ config, lib, pkgs, ... }: {
  # Use systemd-networkd for wired servers (more reliable than NetworkManager)
  networking.useNetworkd = true;
  networking.useDHCP = false;

  # Disable wait-online timeout (WiFi takes too long on test machine)
  # NOTE: re-enabled for THIS host (wired only) so dnsmasq doesn't race
  # networkd at boot. anyInterface = wait for the first link, not all.
  systemd.network.wait-online.enable = true;
  systemd.network.wait-online.anyInterface = true;

  # Wired interface — adjust name if needed (check `ip a` on homelab)
  systemd.network.networks."10-wired" = {
    matchConfig.Name = "en*";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
    # Dedicated LAN DNS address for the split-horizon resolver (dnsmasq in dns.nix).
    # Router DHCP hands out 10.0.0.46 as DNS to LAN devices.
    addresses = [
      { Address = "10.0.0.46/24"; }
    ];
    linkConfig.RequiredForOnline = true;
  };

  # WiFi interface — for the test machine (real homelab is wired-only)
  systemd.network.networks."20-wireless" = {
    matchConfig.Name = "wl*";
    networkConfig = {
      DHCP = "ipv4";
      IPv6AcceptRA = true;
    };
  };

  # Firewall — MINIMAL open ports
  # Only ports that MUST be directly accessible (not via Caddy).
  # Services behind Caddy with forward_auth do NOT need direct access.
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [
    22        # SSH
    53        # AdGuard Home DNS (must be accessible for LAN clients)
    80        # Caddy HTTP (redirects to HTTPS)
    443       # Caddy HTTPS (all web services)
    51820     # Tailscale VPN
  ];
  networking.firewall.allowedUDPPorts = [
    53        # AdGuard Home DNS
    51820     # Tailscale VPN
  ];

  # Tailscale
  services.tailscale = {
    useRoutingFeatures = "server";
    enable = true;
  };

  # DNS — use AdGuard Home directly, bypass systemd-resolved
  networking.nameservers = [ "127.0.0.1" ];
  services.resolved = {
    enable = false;  # AdGuard Home handles DNS directly
  };
}
