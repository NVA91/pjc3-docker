# Design: Vaultwarden Backup

**Datum:** 2026-03-14
**Status:** Approved

---

## Ziel

Tägliches automatisches Backup des Vaultwarden Docker Volumes auf den lokalen Host. Backups älter als 14 Tage werden automatisch gelöscht.

---

## Architektur

```
pjc3-docker/
├── backup.sh          # Backup-Skript (neu)
└── Makefile           # + make backup Target (neu)

/home/ubhp-nova/backups/docker/
└── YYYY-MM-DD/
    └── vw-data.tar.gz
```

---

## Komponenten

### backup.sh

**Umgebung:** Erwartet `AGENT_NAMESPACE` als Umgebungsvariable (Default: `CLAUDE`).

**Ablauf:**
1. Zielordner `/home/ubhp-nova/backups/docker/YYYY-MM-DD/` anlegen
2. Vollständigen Volume-Namen auflösen: `${AGENT_NAMESPACE}-pjc3docker-vol-vw-data`
3. Volume exportieren via `docker run --rm -v <vollständiger-volume-name>:/data alpine tar czf`
4. Cleanup: Datum-Ordner älter als 14 Tage via `find /home/ubhp-nova/backups/docker/ -maxdepth 1 -type d -mtime +14 -exec rm -rf {} +`
5. Log-Ausgabe mit Timestamps zu stdout
6. Exit-Code ungleich 0 bei Fehler (Volume nicht gefunden, Disk voll, Docker nicht erreichbar)

**Docker-Socket:** `backup.sh` nutzt den Host-Docker-Socket via `docker run`. Das ist eine bewusste Host-Level-Ausnahme — kein docker.sock-Mount in Containern (CLAUDE.md-Regel gilt für Container-Level, nicht Host-Skripte).

### Makefile-Target

```makefile
backup:
ifndef AGENT_NAMESPACE
    $(error AGENT_NAMESPACE ist nicht gesetzt — Aufruf: AGENT_NAMESPACE=CLAUDE make backup)
endif
    bash backup.sh
```

Folgt dem bestehenden `ifndef AGENT_NAMESPACE`-Guard-Pattern des Makefiles.

### Cron

Cron exportiert `AGENT_NAMESPACE` explizit, da Cron in minimaler Umgebung läuft:

```
0 2 * * * AGENT_NAMESPACE=CLAUDE /home/ubhp-nova/claude-c/pjc3-docker/backup.sh >> /home/ubhp-nova/backups/docker/backup.log 2>&1
```

---

## Datenstrom

```
Docker Volume (${AGENT_NAMESPACE}-pjc3docker-vol-vw-data)
  → docker run alpine tar czf
  → /home/ubhp-nova/backups/docker/YYYY-MM-DD/vw-data.tar.gz
  → find -mtime +14 -exec rm -rf: Datum-Ordner älter 14 Tage → gelöscht
```

---

## Sicherheit

- `backup.sh` läuft als normaler User (docker-Gruppe-Mitglied — Host-Level-Ausnahme, kein Container-Socket-Mount)
- Backup-Ordner liegt außerhalb des Repos (nicht committed)
- Kein docker.sock-Mount innerhalb von Containern

---

## Manuelle Restore (Referenz)

```bash
docker run --rm -v CLAUDE-pjc3docker-vol-vw-data:/data -v /home/ubhp-nova/backups/docker/YYYY-MM-DD:/backup alpine \
  tar xzf /backup/vw-data.tar.gz -C /data
```

Backup-Integrität prüfen: `tar tzf /home/ubhp-nova/backups/docker/YYYY-MM-DD/vw-data.tar.gz`

---

## Out of Scope

- Remote-Backup / Cloud-Sync
- Verschlüsselung der Backup-Dateien
- Backup weiterer Volumes (caddy, pihole)
- Restore-Automatisierung
