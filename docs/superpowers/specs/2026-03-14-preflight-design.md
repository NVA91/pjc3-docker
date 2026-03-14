# Design: Pre-Flight Stack-Start-Checkliste

**Datum:** 2026-03-14
**Status:** Approved

---

## Ziel

Sicherer, schrittweiser Start des pjc3-docker Stacks mit vollständiger Validierung vor dem Produktionsstart. Jede Phase ist einzeln nachvollziehbar, stoppt bei Fehler und erfordert explizite Bestätigung vor dem nächsten Schritt.

---

## Warum diese Entscheidung (Begründung)

**Option A — Einzel-Skript mit Phasen** wurde gewählt weil:

1. **Klare Phasenabgrenzung** — Jede Phase hat einen eindeutigen Zweck und ist einzeln nachvollziehbar. Fehler sind sofort einer Phase zuordenbar.
2. **Bash > Makefile für Fehlerbehandlung** — Komplexe Fehlerlogik (Subagent-Aktivierung, Port-Checks, Container-Verifikation) ist in Bash direkt und lesbar; Makefile-Syntax wäre umständlich.
3. **Zweistufige Sicherheit** — Dry-Run simuliert, Test-Namespace startet echt aber isoliert. Erst nach beiden Stufen wird Produktion freigegeben.
4. **Test-Namespace-Isolation** — `AGENT_NAMESPACE=TEST` schreibt in separate Named Volumes und Networks, berührt den Produktions-Namespace nicht.
5. **Kleinstmögliche Schritte** — Jeder Übergang erfordert explizite Kontrolle (kein Auto-Continue bei kritischen Schritten).

---

## Architektur

```
pjc3-docker/
├── preflight.sh          # Haupt-Skript (4 Phasen, sequenziell)
└── Makefile              # + make preflight Target
```

**Ablauf:**

```
Phase 1: Syntax & Config
  → .env vorhanden + Pflichtfelder (HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN)
  → docker compose config --quiet (YAML-Validierung)
  → caddy validate --config Caddyfile (Caddyfile-Syntax)
  → Secrets vorhanden: pihole_webpassword, vw_admin_token
  → Ports frei: 53/tcp, 53/udp, 80, 443

Phase 2: .env-Subagent (nur bei .env-Fehler in Phase 1)
  → Interaktiver Subagent erstellt .env aus .env.example
  → Phase 1 wird danach automatisch wiederholt

Phase 3: Dry-Run (AGENT_NAMESPACE=TEST)
  → docker compose --dry-run
  → Zeigt was Docker tun würde, ohne zu starten
  → Abbruch bei Dry-Run-Fehler

Phase 4: Test-Namespace Start
  → AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) make up
  → docker ps: alle Container laufen?
  → AGENT_NAMESPACE=TEST make down (Test-Stack entfernen)
  → Manuelle Bestätigung vor Produktionsstart
```

---

## Komponenten

### preflight.sh

- `set -euo pipefail` für strikte Fehlerbehandlung
- Farb-Ausgabe: `[OK]` grün, `[FAIL]` rot, `[INFO]` gelb
- Jede Phase als eigene Funktion (`phase1_syntax`, `phase2_env`, etc.)
- Exit-Code 0 = alle Phasen bestanden, Stack kann gestartet werden
- Exit-Code 1 = Fehler, mit klarer Fehlermeldung welche Phase/Prüfung

### make preflight Target

```makefile
preflight:
    @AGENT_NAMESPACE=$(AGENT_NS) AGENT_UID=$(AGENT_UID) AGENT_GID=$(AGENT_GID) bash preflight.sh
```

---

## Sicherheit

- Test-Namespace (`AGENT_NAMESPACE=TEST`) ist vollständig isoliert von Produktion (`CLAUDE`)
- Kein Auto-Start der Produktion — immer manuelle Bestätigung
- Port-Checks vor Start verhindert stille Konflikte (z.B. systemd-resolved auf Port 53)

---

## Out of Scope

- Automatischer Produktionsstart (immer manuell)
- Monitoring-Stack (docker-compose.monitor.yml) — separater Schritt
- Netzwerk-Konnektivitätstest nach Start
- Cloudflare DNS-01 Challenge Verifikation
