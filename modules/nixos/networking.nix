{ ... }: {
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";

  # iwd for wireless association only — NM owns IP config (DHCP, DNS, routes).
  # EnableNetworkConfiguration=false prevents iwd from trying to configure IP
  # via NM's D-Bus (which fails when wlan0 is unmanaged by NM).
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        EnableNetworkConfiguration = false;
      };
      Network = {
        EnableNetworkConfiguration = false;
      };
    };
  };

  # Force NM to manage wlan0 — NM's iwd backend misidentifies the iwd
  # station as a wifi-p2p device at /net/connman/iwd/0 instead of managing
  # wlan0 directly. Without this, wlan0 stays "unmanaged" and no DHCP runs.
  # The udev rule triggers on wlan0 add and sets NM_UNMANAGED=0.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNEL=="wlan0", ENV{NM_UNMANAGED}="0"
  '';

  # WiFi power save — saves 1-3W on battery
  boot.extraModprobeConfig = "options iwlwifi power_save=1";

  # DNS — fallback when Tailscale is down
  services.resolved = {
    enable = true;
    fallbackDns = [ "1.1.1.1" "8.8.8.8" ];
    dnssec = "allow-downgrade";
    dnsovertls = "opportunistic";
  };
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
