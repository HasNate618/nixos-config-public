# Server services — SSH, Docker, fail2ban, Tailscale
{ config, lib, pkgs, ... }: {
  # SSH
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # Fail2ban — rate-limit SSH brute-force
  services.fail2ban.enable = true;

  # Docker — for OCI containers
  virtualisation.docker = {
    enable = true;
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" "--filter" "until=168h" ];
    };
    # Storage driver — overlay2 is default and fine for ext4
    # If using ZFS, may need to adjust
    # NOTE: Only uncomment --default-runtime=nvidia on the real homelab
    # (GTX 960 with nvidia-container-toolkit). On test machines without
    # NVIDIA, this will prevent Docker from starting.
    # extraOptions = ''
    #   --default-runtime=nvidia
    # '';
  };

  # NVIDIA container runtime — for GPU workloads (pdf-parser, etc.)
  hardware.nvidia-container-toolkit.enable = true;
  # ^ Uncomment when NVIDIA driver is installed

  # Hermes agent user — restricted, for homelab management
  users.users.hermes-agent = {
    isSystemUser = true;
    group = "hermes-agent";
    shell = pkgs.bash;
    home = "/var/lib/hermes-agent";
    createHome = true;
  };
  users.groups.hermes-agent = {};

  # Restricted sudoers for hermes-agent
  security.sudo.extraRules = [
    {
      users = [ "hermes-agent" ];
      commands = [
        { command = "/run/current-system/sw/bin/systemctl status *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl restart *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl start *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/systemctl stop *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/journalctl *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/docker compose *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/docker ps *"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/docker logs *"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];
}
