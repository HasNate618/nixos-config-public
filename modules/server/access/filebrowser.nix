# FileBrowser — Web file manager for NAS root
# Mounts all NAS shares under /mnt/nas/ and serves them via FileBrowser
# Uses NAS credentials via a samba creds file (sec=ntlmssp required)
# Shares with spaces in names are remapped (e.g. "File Share" → "FileShare")
{ config, lib, pkgs, ... }:

let
  docker = "${pkgs.docker}/bin/docker";
  nasShareMap = {
    "homelab" = "homelab";
    "Backup" = "Backup";
    "Backup Vol2" = "BackupVol2";
    "File Share" = "FileShare";
    "homes" = "homes";
    "music" = "music";
    "photo" = "photo";
    "video" = "video";
    "SCANS" = "SCANS";
    "home" = "home";
  };
in
{
  environment.systemPackages = [ pkgs.cifs-utils ];

  # NAS credentials (sec=ntlmssp auth). Not committed in this repo: supply your
  # own, ideally from a sops secret or an out-of-band credentials file.
  environment.etc."samba/creds-ne".text = ''
    username=<your-user>
    password=<your-password>
  '';
  environment.etc."samba/creds-ne".mode = "0600";

  # Mount all NAS shares under /mnt/nas/<mountname>
  fileSystems = lib.mapAttrs' (share: mountName: {
    name = "/mnt/nas/${mountName}";
    value = {
      device = "//10.0.0.20/${share}";
      fsType = "cifs";
      options = [ "_netdev,credentials=/etc/samba/creds-ne,vers=3.0,sec=ntlmssp,uid=1000,gid=1000,forceuid,forcegid,noperm,dir_mode=0775,file_mode=0664,x-systemd.after=network-online.target,x-systemd.mount-timeout=30" ];
    };
  }) nasShareMap;

  systemd.tmpfiles.rules = [
    "d /mnt/nas 0755 root root -"
    "d /var/lib/filebrowser 0755 1000 1000 -"
    "f /var/lib/filebrowser/filebrowser.db 0666 root root -"
  ];

  # FileBrowser Docker container — credentials configured on first run
  systemd.services.filebrowser = {
    description = "FileBrowser — web file manager for NAS";
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = "${pkgs.bash}/bin/bash -c '${docker} pull filebrowser/filebrowser:latest || true'";
      ExecStart = pkgs.writeScript "filebrowser-start" ''
        #!${pkgs.bash}/bin/bash
        ${docker} rm -f filebrowser 2>/dev/null || true
        ${docker} run -d --name filebrowser \
          --restart unless-stopped \
          --network host \
          --cap-drop ALL \
          --cap-add DAC_OVERRIDE \
          --security-opt no-new-privileges \
          --memory 256m \
          --cpus 0.5 \
          --pids-limit 50 \
          -v /mnt/nas:/mnt/nas:ro \
          -v /var/lib/filebrowser/filebrowser.db:/database/filebrowser.db \
          -e TZ=UTC \
          filebrowser/filebrowser:latest \
          --root /mnt/nas \
          --address 127.0.0.1 \
          --port 8089 \
          --database /database/filebrowser.db
      '';
      ExecStop = "${docker} stop filebrowser";
    };
  };
}
