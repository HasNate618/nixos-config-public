# Server core — shared base config for headless servers
{ config, lib, pkgs, ... }: {
  programs.zsh.enable = true;
  programs.fish.enable = true;
  nixpkgs.config.allowUnfree = true;

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    warn-dirty = false;
    auto-optimise-store = true;
    min-free = "5G";
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  system.stateVersion = "26.05";

  time.timeZone = "UTC";

  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  security.sudo.wheelNeedsPassword = false;

  users.users.nate = {
    isNormalUser = true;
    description = "Nathan Espejo";
    extraGroups = [ "wheel" "docker" "video" "render" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJiVc6NSRZW7A1ltpJaSjitmNzjt2qpZZis1uSMgE7sq nate@nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAzNw8Ej7Oi6ohDoTLsV0Gq3WxUupdIvhaHsxSiQM/3F nate@nixos"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINzl9uZh3hLZ2jm88AapzSF6dWTNOidYl6ZStIzCHWys u0_a460@localhost"
    ];
  };

  services.fstrim.enable = true;
  services.journald.extraConfig = "SystemMaxUse=500M";

  # Disable coredumps — FlareSolverr chromium crashes cause disk I/O storms
  systemd.coredump.enable = false;

  # Hardware watchdog: iTCO (PCH) is the reliable platform resetter.
  # intel_oc_wdt (the overclocking watchdog, which grabs /dev/watchdog0 on
  # this board) does NOT reliably reset the platform — proved 2026-08-01:
  # box hung ~8h with watchdog0 armed, no auto-reboot. Blacklist it so iTCO
  # is the only watchdog and always gets /dev/watchdog0.
  boot.blacklistedKernelModules = [ "intel_oc_wdt" ];
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "30s";
    WatchdogDevice = "/dev/watchdog0";
  };
}
