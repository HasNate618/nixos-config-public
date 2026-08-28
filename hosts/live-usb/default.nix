# Generic live USB host — boots Hyprland desktop on any x86_64 machine
{ config, lib, pkgs, ... }: {
  networking.hostName = lib.mkForce "nixos-live";

  # ── Disable device-specific services (Flow laptop) ──
  services.asusd.enable = lib.mkForce false;
  services.tlp.enable = lib.mkForce false;
  services.power-profiles-daemon.enable = lib.mkForce false;
  virtualisation.docker.enable = lib.mkForce false;

  # Disable NVIDIA (generic ISO — no proprietary drivers)
  services.xserver.videoDrivers = lib.mkForce [ "modesetting" ];
  hardware.nvidia = lib.mkForce {};

  # Disable device-specific systemd units
  systemd.services.asusd-fan-curves.enable = lib.mkForce false;
  systemd.services.rapl-reset.enable = lib.mkForce false;
  systemd.services.asus-ec-power-tune.enable = lib.mkForce false;
  systemd.services.platform-profile-switch.enable = lib.mkForce false;
  systemd.services.mini-led-shutdown.enable = lib.mkForce false;
  systemd.services.mini-led-boot.enable = lib.mkForce false;
  systemd.services.unbind-power-button.enable = lib.mkForce false;
  systemd.services.iio-sensor-proxy.enable = lib.mkForce false;
  systemd.services.aura-keyboard-sleep.enable = lib.mkForce false;
  systemd.timers.platform-profile-switch.enable = lib.mkForce false;

  # Disable btop intel GPU wrapper (no cap_perfmon on generic HW)
  security.wrappers = lib.mkForce {};

  # Disable specialisation (battery mode is Flow-specific)
  specialisation = lib.mkForce {};

  # Disable resume device (swap UUID is Flow-specific)
  boot.resumeDevice = lib.mkForce "";

  # Disable device-specific modprobe options
  boot.extraModprobeConfig = lib.mkForce "";
  boot.blacklistedKernelModules = lib.mkForce [ "nouveau" ];

  # Disable homelab CA cert and SSH keys
  security.pki.certificateFiles = lib.mkForce [];
  users.users.nate.openssh.authorizedKeys.keys = lib.mkForce [];

  # Disable sudo rules for device-specific commands
  security.sudo.extraRules = lib.mkForce [];

  # Set password for live ISO (standard nixos convention — no secrets)
  users.users.nate.initialPassword = lib.mkForce "nixos";
}
