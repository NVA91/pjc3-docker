# REGEL.md — pjc3-docker

## Einordnung
Dieses Repo ist der **Home-Infrastruktur Stack**.
Es liegt unter: `/home/ubhp-nova/claude-c/pjc3-docker/`

Alle 3 Repos sind **gleichrangig und unabhängig**:
```
/home/ubhp-nova/claude-c/
├── pjc3/          ← Hauptrepo (Claude API, Skills, Agents)
├── pjc3-docker/   ← dieses Repo (Home-Infrastruktur)
└── pjc3-viz1/     ← eigenständiges Repo (PDF-Analyse-Tool)
```

---

## Unverbrüchliche Regeln

### Isolation
- Dieses Repo arbeitet **ausschließlich** in `/home/ubhp-nova/claude-c/pjc3-docker/`
- Kein Zugriff auf Dateien anderer Repos ohne explizite Nutzeranweisung
- Keine Symlinks die auf Verzeichnisse **außerhalb** dieses Repos zeigen
- `venv/` liegt in diesem Repo — kein Import aus anderen venvs

### Cross-Repo-Verbote
- Kein Lesen, Schreiben, Verändern von `pjc3/` oder `pjc3-viz1/` ohne Auftrag
- Kein Übertragen von Docker-Configs in andere Repos
- Kein Erstellen von Verweisen (Symlink, Hardlink, relative Pfade) auf andere Repos

### Docker-Sicherheit (STRIKT)
- Kein absoluter Host-Pfad als Volume-Source (außer dokumentierte Ausnahmen)
- Kein `/var/run/docker.sock`-Mount — NIEMALS
- `user:` niemals root — immer UID 1001–1003
- `cap_drop: [ALL]` immer gesetzt
- Operationen immer via Makefile mit `-p`-Flag

### Git
- Remote: `git@github.com:NVA91/pjc3-docker.git`
- Branch-Schema: `claude/<feature-name>`
- Commits nur in diesem Repo

### Aufgaben
- Offene Aufgaben immer explizit benennen
- Erledigte Aufgaben sofort als erledigt markieren
- Keine Aufgabe gilt als "erledigt" ohne Verifikation (Container läuft, Test grün)

---

## Was dieses Repo enthält
- Caddy (Reverse Proxy + Wildcard SSL via DNS-01)
- Vaultwarden (Passwort-Manager)
- Pi-hole (DNS + Ad-Blocking)
- Prometheus + Grafana + Loki (Monitoring, opt-in)
- MCP Docker Agent (`mcp_docker_agent.py`)

---

## Abbruch-Befehl
Bei JEDER Unklarheit zu Architektur, Auftrag oder Kontext: **Arbeit SOFORT einstellen.**
Konflikt an den User melden. Kein Weitermachen auf Verdacht. Keine Workarounds.

## Verstöße
Jede Aktion die gegen diese Regeln verstößt ist **ungültig und rückgängig zu machen**.
Der Nutzer ist sofort zu informieren.
