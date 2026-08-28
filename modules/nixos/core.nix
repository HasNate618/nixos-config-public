{ config, lib, pkgs, ... }: {
  programs.zsh.enable = true;
  programs.fish.enable = true;
  programs.fish.generateCompletions = false;
  nixpkgs.config.allowUnfree = true;

  # Allow dynamically linked executables (cursor-agent, opencode, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    fuse3
    icu
    nss
    openssl
    curl
    expat
  ];

  programs.nix-index-database.comma.enable = true;

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

  time.timeZone = "America/Toronto";

  i18n.defaultLocale = "en_CA.UTF-8";

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.nate = {
    isNormalUser = true;
    description = "Nathan Espejo";
    extraGroups = [ "networkmanager" "wheel" "hermes" "video" "render" "docker" "input" ];
    packages = with pkgs; [ hyprlock cliphist wl-clipboard grim slurp ];
    shell = pkgs.fish;
  };

  # Periodic SSD trim
  services.fstrim.enable = true;
  services.udisks2.enable = true;

  # Cap systemd journal to 500 MB
  services.journald.extraConfig = "SystemMaxUse=500M";

  # Cap stop-job timeout so stubborn processes don't stall shutdown/reboot
  systemd.settings.Manager.DefaultTimeoutStopSec = "15s";

  # Let Hyprland handle power key (not systemd logind)
  services.logind.settings.Login = {
    HandlePowerKey = "ignore";
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
  };

  # Disable keyboard LED during suspend
  systemd.services.aura-keyboard-sleep = {
    description = "Set keyboard LED to off during suspend";
    wantedBy = [ "multi-user.target" ];
    after = [ "asusd.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.asusctl}/bin/asusctl aura power keyboard --awake";
    };
  };
}