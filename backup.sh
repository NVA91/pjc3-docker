#!/usr/bin/env bash
set -euo pipefail

# Backup-Konfiguration
AGENT_NAMESPACE="${AGENT_NAMESPACE:-CLAUDE}"
VOLUME_NAME="${AGENT_NAMESPACE}-pjc3docker-vol-vw-data"
BACKUP_ROOT="/home/ubhp-nova/backups/docker"
DATE="$(date +%Y-%m-%d)"
BACKUP_DIR="${BACKUP_ROOT}/${DATE}"
RETAIN_DAYS=14

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup gestartet: ${VOLUME_NAME}"

# Zielordner anlegen
mkdir -p "${BACKUP_DIR}"

# Volume prüfen
if ! docker volume inspect "${VOLUME_NAME}" > /dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] FEHLER: Volume '${VOLUME_NAME}' nicht gefunden." >&2
  exit 1
fi

# Volume exportieren
docker run --rm \
  -v "${VOLUME_NAME}:/data:ro" \
  -v "${BACKUP_DIR}:/backup" \
  alpine \
  tar czf "/backup/vw-data.tar.gz" -C /data .

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup gespeichert: ${BACKUP_DIR}/vw-data.tar.gz"

# Integrität prüfen
if ! tar tzf "${BACKUP_DIR}/vw-data.tar.gz" > /dev/null 2>&1; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] FEHLER: Backup-Archiv defekt." >&2
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Archiv-Integritaet OK."

# Alte Backups loeschen (>14 Tage)
find "${BACKUP_ROOT}" -maxdepth 1 -type d -mtime +${RETAIN_DAYS} -exec rm -rf {} +

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup abgeschlossen."
