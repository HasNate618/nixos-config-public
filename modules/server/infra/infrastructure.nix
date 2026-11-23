# Core infrastructure — PostgreSQL, Redis (shared backends)
{ config, lib, pkgs, ... }: {

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    settings = {
      shared_buffers = "2GB";
      effective_cache_size = "6GB";
      maintenance_work_mem = "512MB";
      checkpoint_completion_target = 0.9;
      wal_buffers = "64MB";
      default_statistics_target = 100;
      random_page_cost = 1.1;
      effective_io_concurrency = 200;
      work_mem = "64MB";
      huge_pages = "try";
      min_wal_size = "1GB";
      max_wal_size = "4GB";
      max_worker_processes = 4;
      max_parallel_workers_per_gather = 2;
      max_parallel_workers = 4;
      max_parallel_maintenance_workers = 2;
    };

    extensions = extensions: with extensions; [ pgvector ];

    initialScript = pkgs.writeText "init.sql" ''
      CREATE DATABASE nextcloud;
      CREATE DATABASE forgejo;
      CREATE USER nextcloud WITH PASSWORD 'nextcloud';
      CREATE USER forgejo WITH PASSWORD 'forgejo';
      GRANT ALL PRIVILEGES ON DATABASE nextcloud TO nextcloud;
      GRANT ALL PRIVILEGES ON DATABASE forgejo TO forgejo;
    '';
  };

  # Sync PostgreSQL passwords from sops on every start
  systemd.services.postgresql-password-sync = {
    description = "Sync PostgreSQL passwords from sops secrets";
    after = [ "postgresql.service" "sops-nix.service" ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = let
      psql = "${pkgs.postgresql_16}/bin/psql";
      runuser = "${pkgs.util-linux}/bin/runuser";
    in ''
      for pair in nextcloud:postgres-nextcloud-password forgejo:postgres-forgejo-password; do
        user="''${pair%%:*}"
        secret="''${pair#*:}"
        pw=$(cat /run/secrets/$secret)
        ${runuser} -u postgres -- ${psql} -c "ALTER USER $user WITH PASSWORD '$pw'"
      done
    '';
  };

  services.redis.servers.default = {
    enable = true;
    port = 6377;
    bind = "127.0.0.1";
    settings = { maxmemory = "1gb"; maxmemory-policy = "allkeys-lru"; };
  };

  # Redis password sync from sops
  systemd.services.redis-password-sync = {
    description = "Set Redis password from sops";
    after = [ "redis-default.service" "sops-nix.service" ];
    requires = [ "redis-default.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      REDIS_PASS=$(cat /run/secrets/redis-password)
      ${pkgs.redis}/bin/redis-cli -p 6377 -a "$REDIS_PASS" CONFIG SET requirepass "$REDIS_PASS"
      ${pkgs.redis}/bin/redis-cli -p 6377 -a "$REDIS_PASS" CONFIG REWRITE
    '';
  };

  # Write Samba credentials from sops (for CIFS NAS mounts)
  systemd.services.samba-creds-sync = {
    description = "Write Samba credentials from sops secrets";
    after = [ "sops-nix.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = ''
      mkdir -p /etc/samba
      echo "username=homelab" > /etc/samba/creds
      echo "password=$(cat /run/secrets/samba-password)" >> /etc/samba/creds
      chmod 0600 /etc/samba/creds
    '';
  };

  systemd.services.postgresql-backup = {
    description = "PostgreSQL backup to NAS";
    serviceConfig = { Type = "oneshot"; User = "postgres"; };
    script = let
      pgDump = "${pkgs.postgresql_16}/bin/pg_dumpall";
      rsync = "${pkgs.rsync}/bin/rsync";
      find = "${pkgs.findutils}/bin/find";
      mountpoint = "${pkgs.util-linux}/bin/mountpoint";
      nasDir = "/mnt/homelab-full/backups/postgresql";
    in ''
      set -euo pipefail
      dumpDir=/var/lib/postgresql/backups
      ${pgDump} -f $dumpDir/postgresql-$(date +%Y%m%d).sql
      # Off-box copy to NAS (if mounted) + 7-day retention on both sides
      if ${mountpoint} -q /mnt/homelab-full; then
        mkdir -p ${nasDir}
        ${rsync} -a $dumpDir/postgresql-*.sql ${nasDir}/
        ${find} ${nasDir} -name "postgresql-*.sql" -mtime +7 -delete
      else
        echo "NAS not mounted — local-only backup this run"
      fi
      ${find} $dumpDir -name "postgresql-*.sql" -mtime +7 -delete
    '';
  };

  # Consolidated misc-data backup to NAS (open-webui, configs, hermes profile)
  systemd.services.homelab-misc-backup = {
    description = "Misc homelab data backup to NAS";
    serviceConfig = { Type = "oneshot"; User = "root"; };
    script = let
      tar = "${pkgs.gnutar}/bin/tar";
      gzip = "${pkgs.gzip}/bin/gzip";
      find = "${pkgs.findutils}/bin/find";
      mkdir = "${pkgs.coreutils}/bin/mkdir";
      date = "${pkgs.coreutils}/bin/date";
      mountpoint = "${pkgs.util-linux}/bin/mountpoint";
      nasDir = "/mnt/homelab-full/backups/misc";
    in ''
      set -euo pipefail
      if ! ${mountpoint} -q /mnt/homelab-full; then
        echo "NAS not mounted, skipping misc backup"
        exit 0
      fi
      stamp=$(${date} +%Y-%m-%d_%H-%M)
      dest=${nasDir}/$stamp
      ${mkdir} -p $dest
      # Open WebUI (chat history, RAG knowledge)
      ${tar} --use-compress-program=${gzip} -cf $dest/open-webui.tar.gz -C /var/lib open-webui
      # NixOS config
      ${tar} --use-compress-program=${gzip} -cf $dest/nixos-config.tar.gz -C /etc nixos
      # Hermes profile (skills, memories)
      ${tar} --use-compress-program=${gzip} -cf $dest/hermes-profile.tar.gz -C /home/nate .hermes
      # Arr-stack configs (exclude downloads)
      ${tar} --use-compress-program=${gzip} -cf $dest/arr-stack-config.tar.gz -C /var/lib --exclude='arr-stack/downloads' arr-stack
      # Jellyfin config (exclude cache)
      ${tar} --use-compress-program=${gzip} -cf $dest/jellyfin-config.tar.gz -C /var/lib/jellyfin config
      # Campus (study system)
      ${tar} --use-compress-program=${gzip} -cf $dest/campus.tar.gz -C /home/nate campus
      ${tar} --use-compress-program=${gzip} -cf $dest/campus-dot.tar.gz -C /home/nate .hippocampus
      # Bifrost LLM gateway config (provider keys) — NOT the 5.4G logs.db
      ${tar} --use-compress-program=${gzip} -cf $dest/bifrost-config.tar.gz -C /var/lib/bifrost config.db config.db-wal
      # SOPS age key — REQUIRED to decrypt secrets/homelab.yaml; without it the
      # secrets in nixos-config.tar.gz are undecryptable
      ${tar} --use-compress-program=${gzip} -cf $dest/sops-age-key.tar.gz -C /root/.config/sops/age keys.txt
      # Nextcloud config (config.php + instance secrets — data is on NAS)
      ${tar} --use-compress-program=${gzip} -cf $dest/nextcloud-config.tar.gz -C /var/lib/nextcloud config
      # AdGuard Home settings (runtime-mutable, diverges from dns.nix)
      ${tar} --use-compress-program=${gzip} -cf $dest/adguard-config.tar.gz -C /var/lib/AdGuardHome AdGuardHome.yaml
      # Small service configs (each = a manual re-setup if lost)
      ${tar} --use-compress-program=${gzip} -cf $dest/service-configs.tar.gz \
        -C /var/lib glance/config \
        -C /var/lib uptime-kuma \
        -C /var/lib crowdsec/config \
        -C /var/lib caddy \
        -C /var/lib ntfy \
        -C /var/lib trawl \
        -C /var/lib brightspace-mcp-config \
        -C /var/lib pdf-extractor
      # Retention: keep 7 days of misc snapshots
      ${find} ${nasDir} -maxdepth 1 -type d -mtime +7 -exec rm -rf {} +
      echo "Misc backup complete: $stamp"
    '';
  };

  systemd.timers.homelab-misc-backup = {
    description = "Nightly misc homelab data backup to NAS";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "02:30"; Persistent = true; };
  };

  systemd.timers.postgresql-backup = {
    description = "Daily PostgreSQL backup";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "daily"; Persistent = true; };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/postgresql/backups 0755 postgres postgres -"
  ];
}
