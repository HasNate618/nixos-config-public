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
  ];
}
