{ ... }: {
  networking.networkmanager.enable = true;
  networking.networkmanager.wifi.backend = "iwd";

  # iwd for impala + auto-connect
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        EnableNetworkConfiguration = true;
      };
      Network = {
        EnableNetworkConfiguration = true;
      };
    };
  };

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
