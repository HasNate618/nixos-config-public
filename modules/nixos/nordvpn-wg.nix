# NordVPN via plain WireGuard (wg-quick) — replaces nordvpnd daemon.
# Session key lives at /etc/nordlynx.key (root:root 0600).
# Refresh runbook: connect daemon, capture showconf, update key file.
{ ... }: {
  networking.wg-quick.interfaces.nordlynx = {
    autostart = false;
    address = [ "10.5.0.2/32" ];
    dns = [ "103.86.96.100" "103.86.99.100" ];
    mtu = 1420;
    privateKeyFile = "/etc/nordlynx.key";
    # Two fixes for NordVPN+Tailscale coexistence:
    #
    # 1. Route Tailscale's own WireGuard packets (fwmark 0x80000/0xff0000)
    #    to the main table so they exit via wlan0, not NordVPN. Without
    #    this, tailscaled's encrypted UDP to peers gets captured by
    #    wg-quick's catch-all at priority 5209.
    #
    # 2. Route APPLICATION traffic to Tailscale IPs (100.64.0.0/10)
    #    to table 52 before NordVPN's catch-all can intercept it.
    #    Without this, ssh/curl/dns to 100.x.x.x goes through the VPN
    #    tunnel and never reaches the tailnet peer.
    postUp = [
      "ip rule add fwmark 0x80000/0xff0000 lookup main priority 5207"
      "ip rule add to 100.64.0.0/10 lookup 52 priority 5206"
    ];
    postDown = [
      "ip rule del fwmark 0x80000/0xff0000 lookup main priority 5207"
      "ip rule del to 100.64.0.0/10 lookup 52 priority 5206"
    ];
    peers = [{
      publicKey = "qIhtTW9K4iXWFo5Q4dOPdXg8/xubXr9yEGoN55D8xnA=";
      allowedIPs = [ "0.0.0.0/0" "::/0" ];
      endpoint = "187.15.142.120:51820";
      persistentKeepalive = 25;
    }];
  };
  systemd.tmpfiles.rules = [
    "f /etc/nordlynx.key 0600 root root - -"
  ];
}
