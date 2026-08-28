# Forgejo — lightweight Git forge (replaces Gitea)
{ config, lib, pkgs, ... }:

let
  forgejoSshPort = 2222;
  forgejoUser = "forgejo";
  forgejoGroup = "forgejo";
  forgejoState = "/var/lib/forgejo";
  forgejoExe = "${config.services.forgejo.package}/bin/forgejo";
  forgejoConfig = "${config.services.forgejo.customDir}/conf/app.ini";
in
{
  services.forgejo = {
    enable = true;

    settings.server.HTTP_ADDR = "127.0.0.1";
    settings.server.HTTP_PORT = 3001;
    settings.server.DOMAIN = "forgejo.home.lab";
    settings.server.ROOT_URL = "http://forgejo.home.lab/";

    database = {
      type = "postgres";
      host = "/run/postgresql";
      port = 5432;
      name = "forgejo";
      user = "forgejo";
    };

    settings.server.SSH_PORT = forgejoSshPort;
    settings.server.DISABLE_SSH = false;

    stateDir = forgejoState;
    lfs.enable = true;

    settings = {
      security.INSTALL_LOCK = true;
      ssh = {
        START_SSH_SERVER = false;
      };
      service = {
        DISABLE_REGISTRATION = true;
        REQUIRE_SIGNIN_VIEW = true;
      };
      openid = {
        ENABLE_OPENID_SIGNIN = true;
        ENABLE_OPENID_SIGNUP = false;
      };
      metrics.ENABLED = true;
    };
  };

  systemd.services.forgejo.preStart = lib.mkAfter ''
    mkdir -p ${forgejoState}/.ssh
    ${forgejoExe} admin regenerate keys --config ${forgejoConfig} || true
    sed -i '/--work-path/!s|serv key-|--work-path ${forgejoState} serv key-|g' ${forgejoState}/.ssh/authorized_keys || true
    chmod 644 ${forgejoState}/.ssh/authorized_keys || true
    chmod 700 ${forgejoState}/.ssh || true
  '';

  systemd.services.forgejo.serviceConfig.TimeoutStartSec = lib.mkForce "10min";
  systemd.services.forgejo.environment = {
    FORGEJO__modules__setting__f3__path = "${forgejoState}/f3";
  };

  users.users.${forgejoUser} = {
    isSystemUser = true;
    group = forgejoGroup;
    home = forgejoState;
    shell = pkgs.bashInteractive;
  };
  users.groups.${forgejoGroup} = {};

  # Standalone sshd config for Forgejo SSH
  environment.etc."forgejo/sshd_config".text = ''
    Port ${toString forgejoSshPort}
    ListenAddress 0.0.0.0
    HostKey ${forgejoState}/ssh/ssh_host_ed25519_key
    AuthorizedKeysFile ${forgejoState}/.ssh/authorized_keys
    LogLevel INFO
    PubkeyAuthentication yes
    PasswordAuthentication no
    PermitRootLogin no
    X11Forwarding no
    AllowTcpForwarding no
    AllowAgentForwarding no
    MaxAuthTries 3
    LoginGraceTime 30
    UsePAM yes
    StrictModes no
    PidFile /run/forgejo-ssh/sshd.pid
  '';

  systemd.services.forgejo-ssh = {
    description = "Forgejo SSH server (git operations only)";
    after = [ "network.target" "forgejo.service" ];
    wants = [ "forgejo.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = 5;
      RuntimeDirectory = "forgejo-ssh";
      RuntimeDirectoryMode = "0755";
    };

    preStart = ''
      mkdir -p ${forgejoState}/.ssh /run/forgejo-ssh

      # Generate host key if missing
      if [ ! -f ${forgejoState}/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -t ed25519 -f ${forgejoState}/ssh/ssh_host_ed25519_key -N ""
        chown ${forgejoUser}:${forgejoGroup} ${forgejoState}/ssh/ssh_host_ed25519_key
        chmod 600 ${forgejoState}/ssh/ssh_host_ed25519_key
      fi

      # Regenerate authorized_keys (forgejo refuses to run as root, use su wrapper)
      /run/wrappers/bin/su -s ${pkgs.bash}/bin/bash ${forgejoUser} -c '${forgejoExe} admin regenerate keys --config ${forgejoConfig}' || true
      sed -i '/--work-path/!s|serv key-|--work-path ${forgejoState} serv key-|g' ${forgejoState}/.ssh/authorized_keys || true
      chmod 644 ${forgejoState}/.ssh/authorized_keys || true
      chmod 700 ${forgejoState}/.ssh || true
    '';

    script = ''
      exec ${pkgs.openssh}/bin/sshd -D -e -f /etc/forgejo/sshd_config
    '';
  };

  networking.firewall.allowedTCPPorts = [ forgejoSshPort ];

  # Forgejo backup to NAS
  systemd.services.forgejo-backup = {
    description = "Forgejo backup to NAS via NFS";
    after = [ "network-online.target" "forgejo.service" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.bash}/bin/bash /etc/nixos/scripts/forgejo-backup.sh";
    };
  };

  systemd.timers.forgejo-backup = {
    description = "Daily Forgejo backup to NAS";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
  # Forgejo backup mount (CIFS to NAS)
  fileSystems."/mnt/homelab-full" = {
    device = "//10.0.0.6/homelab";
    fsType = "cifs";
    options = [ "_netdev,credentials=/etc/samba/creds,uid=0,gid=0,forceuid,forcegid,noperm,vers=3.0,noauto,x-systemd.automount,x-systemd.after=network-online.target x-systemd.after=samba-creds-sync.service,x-systemd.mount-timeout=30" ];
  };
}
