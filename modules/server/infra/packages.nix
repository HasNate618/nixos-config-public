# Server packages — headless server tools
{ pkgs, ... }: {
  imports = [ ../../shared/packages.nix ];

  environment.systemPackages = with pkgs; [
    # Server tools
    docker-compose
    tailscale
    restic          # backups
    iperf3          # bandwidth testing
    rsync           # file sync
    sqlite          # for various service DBs

    # WiFi tools (for the test machine)
    iw              # WiFi interface info
    wpa_supplicant  # WiFi management (wpa_cli)
    networkmanagerapplet  # nm-applet tray icon (optional)

    # NixOS tools
    nix-output-monitor  # prettier nixos-rebuild output
    nvd             # nix diff between generations

    # VPN rotation helper — manual trigger for gluetun-search (SearXNG/DeGoog egress)
    (pkgs.writeScriptBin "rotate-vpn" ''
      #!${pkgs.bash}/bin/bash
      # Rotate the SearXNG gluetun exit on demand (no auto-timer).
      # Usage: rotate-vpn
      set -uo pipefail
      echo ">> rotating gluetun-search (picking random NordVPN WireGuard host)..."
      sudo systemctl start gluetun-search-rotate.service
      while systemctl is-active --quiet gluetun-search-rotate.service; do sleep 2; done
      echo ">> rotation done. new exit:"
      docker exec gluetun-search wget -qO- http://ip-api.com/json 2>/dev/null | \
        python3 -c "import sys,json;d=json.load(sys.stdin);print('   ',d.get('query'),d.get('country'),d.get('city'),'|',d.get('org'))" 2>/dev/null
      echo ">> waiting for searxng to settle, then checking results:"
      sleep 6
      timeout 15 curl -s "http://127.0.0.1:8888/search?q=test&format=json" 2>/dev/null | \
        python3 -c "import sys,json;d=json.load(sys.stdin);print('   results:',len(d.get('results',[])),'| errors:',d.get('unresponsive_engines'))" 2>/dev/null || echo "   (searxng unreachable)"
    '')
  ];
}
