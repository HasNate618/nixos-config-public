#!/bin/bash
# Forgejo backup to NAS
set -euo pipefail
# NixOS systemd services have minimal PATH — export full PATH or tar/find/du fail
export PATH=/run/current-system/sw/bin:$PATH

BACKUP_DIR="/mnt/homelab-full/backups"
FORGEJO_DIR="/var/lib/forgejo"
DATE=$(date +%Y-%m-%d_%H-%M)
KEEP=7

# /mnt/homelab-full is mounted automatically by NixOS (fileSystems in forgejo.nix)
if ! mountpoint -q /mnt/homelab-full; then
  echo "NAS not mounted, skipping forgejo backup"
  exit 0
fi
mkdir -p "$BACKUP_DIR"

tar czf "$BACKUP_DIR/forgejo-$DATE.tar.gz" \
  -C /var/lib \
  --exclude='forgejo/log/*' \
  --exclude='forgejo/tmp/*' \
  --exclude='forgejo/home/*' \
  forgejo

find "$BACKUP_DIR" -name "forgejo-*.tar.gz" -mtime +$KEEP -delete

echo "Backup complete: forgejo-$DATE.tar.gz ($(du -sh $BACKUP_DIR/forgejo-$DATE.tar.gz | cut -f1))"
