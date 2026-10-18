{ config, lib, pkgs, ... }: {
  programs.zsh.enable = true;
  programs.fish.enable = true;
  programs.fish.generateCompletions = false;
  nixpkgs.config.allowUnfree = true;

  # winboat 0.9.0 pins electron_40, which nixpkgs refuses because Electron 40 is
  # EOL (`knownVulnerabilities = "Electron version <41 is EOL"`, a version
  # comparison in electron/binary/generic.nix -- NOT a CVE or advisory). Nixpkgs'
  # documented escape hatch for depending on an EOL package is to waive it here.
  # WinBoat only composites the user's own Windows VM over RDP, so this adds no
  # real attack surface beyond the Electron apps already in this config.
  # When winboat bumps to electron_41+ upstream, drop this line.
  nixpkgs.config.permittedInsecurePackages = [ "electron-40.10.5" ];

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
    # Memory-exhaustion guard. Defaults (max-jobs=20 = nproc, cores=0 = unlimited
    # per job) let ~20 concurrent cc1plus/link jobs each balloon to multi-GB RSS
    # on this 38GB box, overrunning RAM+zswap faster than reclaim can keep up.
    # The kernel then wedges in the swap-cache reclaim path (page-alloc failure,
    # no OOM-kill) instead of killing a build job -> hard freeze, only a hard
    # reboot clears it. Cap concurrency and per-job cores so peak build RSS
    # stays well under RAM+swap. 4 jobs x ~3-4GB each ~= 14-16GB worst case,
    # leaving headroom for the desktop. cores=4 stops big C++/LLVM builds from
    # spawning one compiler thread per core.
    max-jobs = 4;
    cores = 4;
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
    extraGroups = [ "networkmanager" "wheel" "hermes" "video" "render" "docker" "input" "dialout" "kvm" ];
    packages = with pkgs; [ hyprlock cliphist wl-clipboard grim slurp ];
    shell = pkgs.fish;
  };

  # Seat-user access to USB serial devices (badges, dev boards, MCUs) so browsers
  # (Web Serial) and CLI tools can open ttyACM*/ttyUSB* without the dialout group
  # being live in the session. Numbered 69 deliberately: 73-seat-late.rules only
  # runs the uaccess builtin if the tag is already set, so putting this in
  # services.udev.extraRules (99-local.rules) would silently never apply.
  services.udev.packages = [
    (pkgs.writeTextDir "lib/udev/rules.d/69-serial-uaccess.rules" ''
      SUBSYSTEM=="tty", KERNEL=="ttyACM*", TAG+="uaccess"
      SUBSYSTEM=="tty", KERNEL=="ttyUSB*", TAG+="uaccess"
    '')
  ];

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