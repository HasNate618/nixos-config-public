# Vaultwarden — self-hosted Bitwarden-compatible password manager
# SQLite backend, backups to NAS, accessed via vault.home.lab
{ config, lib, pkgs, ... }:

let
  vaultwardenPort = 8222;
  dataDir = "/var/lib/vaultwarden";
  backupDir = "/var/local/vaultwarden/backup";
in
{
  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite";
    backupDir = null;
    domain = "vault.home.lab";
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = vaultwardenPort;
      ROCKET_LOG = "critical";
      SIGNUPS_ALLOWED = false;
      # Admin panel disabled — manage via web vault
      # ADMIN_TOKEN will be set via environmentFile if needed
    };
    # Environment file for secrets (create manually or via sops)
    # environmentFile = "/etc/vaultwarden/env";
  };

  # Backup script — SQLite dump + copy to NAS (7-day retention)
  systemd.services.vaultwarden-backup = {
    description = "Vaultwarden SQLite backup to NAS";
    serviceConfig = { Type = "oneshot"; User = "root"; };
    script = let
      sqlite3 = "${pkgs.sqlite}/bin/sqlite3";
      rsync = "${pkgs.rsync}/bin/rsync";
      find = "${pkgs.findutils}/bin/find";
      mountpoint = "${pkgs.util-linux}/bin/mountpoint";
      nasBackupDir = "/mnt/homelab-full/backups/vaultwarden";
    in ''
      # Ensure NAS is mounted
      if ! ${mountpoint} -q /mnt/homelab-full; then
        echo "NAS not mounted, skipping backup"
        exit 0
      fi

      # Create backup directory
      mkdir -p ${nasBackupDir}

      # Dump SQLite database
      timestamp=$(date +%Y%m%d-%H%M%S)
      ${sqlite3} ${dataDir}/db.sqlite3 ".backup ${backupDir}/vaultwarden-$timestamp.db"

      # Copy to NAS
      ${rsync} -av --delete ${backupDir}/ ${nasBackupDir}/

      # Remove backups older than 7 days
      ${find} ${backupDir} -name "vaultwarden-*.db" -mtime +7 -delete
      ${find} ${nasBackupDir} -name "vaultwarden-*.db" -mtime +7 -delete

      echo "Vaultwarden backup completed: $timestamp"
    '';
  };

  systemd.timers.vaultwarden-backup = {
    description = "Nightly Vaultwarden backup";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "03:00"; Persistent = true; };
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0755 vaultwarden vaultwarden -"
    "d ${backupDir} 0755 root root -"
  ];
}
