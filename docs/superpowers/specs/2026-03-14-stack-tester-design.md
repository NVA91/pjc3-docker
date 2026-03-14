# Design: Stack-Tester Subagent System

**Datum:** 2026-03-14
**Status:** Approved

---

## Ziel

Zwei unabhängige Claude Code Subagenten testen den pjc3-docker Stack vollständig — zero-knowledge, ohne Annahmen des Erstellers. Primärer Auslöser: `/test-stack` Slash-Command innerhalb einer Claude Code Session. Ergebnis: strukturierter Memory-Eintrag + Terminal-Ausgabe.

---

## Warum diese Entscheidung

**Zwei separate Agenten (stack-tester + stack-reviewer)** wurden gewählt weil:

1. **Echte Isolation** — Tester und Reviewer haben keinen gemeinsamen Kontext. Der Reviewer kann den Tester nicht rationalisieren.
2. **Zero-Knowledge** — Beide lesen das Repo selbst und leiten daraus ab was zu testen ist. Kein hardcoded Wissen über "was schon getestet wurde".
3. **Claude Code Agent** statt Bash-Skript — kann Fehler interpretieren, auf unerwartete Ausgaben reagieren, Empfehlungen geben.
4. **Memory statt Logs** — Testergebnisse werden als strukturiertes Projektwissen gespeichert (Datei-basiertes Memory-System unter `~/.claude/projects/.../memory/`), nicht als rohe Ausgabedateien.

---

## Architektur

```
pjc3-docker/
├── .claude/
│   ├── agents/
│   │   ├── stack-tester.md      # Subagent: testet Stack zero-knowledge
│   │   └── stack-reviewer.md    # Subagent: prüft Tester + Bericht unabhängig
│   └── commands/
│       └── test-stack.md        # /test-stack Slash-Command (primärer Auslöser)
└── Makefile                     # + make test Target (sekundär, Hinweis auf /test-stack)
```

**Ablauf:**

```
/test-stack  (innerhalb Claude Code Session)
      ↓
Präkondition: docker compose build (Caddy Custom-Image)
      ↓
stack-tester (frischer Subagent, zero-knowledge)
  → liest Repo selbst: docker-compose.yml, Caddyfile, .env, preflight.sh, secrets/
  → erstellt eigenen Testplan (3 Ebenen)
  → führt Tests aus mit Env-Variablen aus .env
  → Terminal-Ausgabe (kompakt) + Memory-Datei schreiben
      ↓
stack-reviewer (frischer Subagent, unabhängig)
  → bekommt: Repo-Pfad + Memory-Dateipfad
  → prüft Vollständigkeit und Plausibilität
  → Fallback wenn Memory fehlt: meldet "Tester hat keinen Bericht hinterlassen"
  → ergänzt Memory-Eintrag mit Review-Ergebnis
      ↓
Finaler Bericht im Terminal
```

---

## Komponenten

### stack-tester Agent

**Trigger:** Von `/test-stack` als Subagent gestartet.

**Eingabe:** Repo-Pfad

**Was er liest (selbst, zero-knowledge):**
- `docker-compose.yml` — welche Services existieren, welche Ports gebunden sind
- `.env` — HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN (werden für Tests benötigt)
- `secrets/` — welche Secret-Dateien vorhanden sein müssen
- `Caddyfile` — welche Subdomains definiert sind
- `preflight.sh` — welche Checks bereits implementiert sind

**Präkondition Ebene 2:**
Vor `docker compose up` muss das Caddy-Image gebaut werden, da es ein Custom-Dockerfile nutzt:
```bash
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    docker compose build caddy 2>&1
```
Schlägt der Build fehl → Ebene 2 abbrechen, Fehler melden.

**Testplan (3 Ebenen):**

**Ebene 1 — Konfiguration (ohne Docker):**
- `.env` vorhanden + Pflichtfelder gesetzt + nicht leer (HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN)
- `docker-compose.yml` YAML-Syntax: `AGENT_NAMESPACE=TEST AGENT_UID=... docker compose config --quiet`
- Secrets vorhanden: `secrets/pihole_webpassword`, `secrets/vw_admin_token`
- Ports frei: 53/tcp, 53/udp, 80, 443 (via `ss`)
- `preflight.sh` Bash-Syntax: `bash -n preflight.sh`

**Ebene 2 — Container-Start (TEST-Namespace):**

Alle Befehle mit Env-Variablen aus `.env` (insbesondere `LAN_IP` für Pi-hole Port-Binding):
```bash
source .env  # Variablen laden
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    LAN_IP="${LAN_IP}" HOME_DOMAIN="${HOME_DOMAIN}" \
    docker compose -p "TEST-pjc3docker" up -d
```
- Alle Container Status `running` (nicht `exited`, `restarting`)
- Jeder Service einzeln geprüft: caddy, vaultwarden, pihole
- Warten: `sleep 10` nach Start (Caddy braucht etwas länger)

**Ebene 3 — Service-Healthchecks (Netzwerk-Stolpersteine):**

| Service | Kommando | Erwartung | Begründung |
|---------|----------|-----------|------------|
| Caddy | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1` | `308` | Caddy redirectet HTTP→HTTPS; `308 Permanent Redirect` = gesund und aktiv |
| Vaultwarden | `curl -s -o /dev/null -w "%{http_code}" -H "Host: vault.${HOME_DOMAIN}" http://127.0.0.1/api/alive` | `200` | Vaultwarden sitzt hinter Caddy im internen Netz; Host-Header erforderlich; korrekter Endpunkt: `/api/alive` |
| Pi-hole | `dig @${LAN_IP} google.com` | Antwort ohne `SERVFAIL` | Pi-hole bindet Port 53 an `$LAN_IP`, nicht localhost; Query muss an LAN-IP gerichtet werden |

**Abschluss (immer, auch bei Fehler):**
```bash
docker compose -p "TEST-pjc3docker" down 2>/dev/null || true
```
- Memory-Datei schreiben (auch bei Fehler)
- Kompakte Terminal-Ausgabe: ✅/❌ pro Service + Ebene

**Memory-Format** (Datei-basiert, `~/.claude/projects/.../memory/test_stack_YYYY-MM-DD.md`):
```markdown
---
name: Stack-Test YYYY-MM-DD
description: Testergebnis pjc3-docker Stack vom YYYY-MM-DD — ✅/❌
type: project
---
**Ergebnis:** ✅ alle Tests bestanden / ❌ Fehler gefunden
**Getestet:** YYYY-MM-DD HH:MM

| Service | Ebene 1 Config | Ebene 2 Container | Ebene 3 Healthcheck |
|---------|---------------|-------------------|---------------------|
| caddy | ✅ | ✅ | ✅ 308 |
| vaultwarden | ✅ | ✅ | ✅ 200 |
| pihole | ✅ | ✅ | ✅ DNS OK |

**Why:** [Was wurde getestet, was war der Kontext]
**How to apply:** [Bei erneutem Test: auf diese Punkte achten]
**Offene Punkte:** —
**Review:** (wird vom stack-reviewer ergänzt)
```

---

### stack-reviewer Agent

**Trigger:** Nach stack-tester, automatisch von `/test-stack`.

**Eingabe:** Repo-Pfad + Memory-Dateipfad

**Fallback:** Wenn Memory-Datei fehlt (Tester abgebrochen) → meldet im Terminal: "stack-tester hat keinen Bericht hinterlassen — Test unvollständig" und schreibt eigenen Fehler-Memory-Eintrag.

**Prüft unabhängig:**
- Wurden alle 3 Services getestet (caddy, vaultwarden, pihole)?
- Sind alle 3 Ebenen abgedeckt (Konfiguration, Container, Healthcheck)?
- Sind die Healthcheck-Erwartungen korrekt (308 / 200 auf `/api/alive` / DNS ohne SERVFAIL)?
- Gibt es Widersprüche im Bericht?
- Wurde TEST-Stack bereinigt (kein `TEST-pjc3docker` in `docker ps`)?

**Ausgabe:**
- Ergänzt Memory-Eintrag: `**Review:** ✅ vollständig / ❌ Lücken: [Liste]`
- Terminal: kurzes Review-Ergebnis mit finaler Bewertung

---

### `/test-stack` Slash-Command

**Primärer Auslöser** — innerhalb einer aktiven Claude Code Session.

Ablauf:
1. Präkondition: `docker compose build caddy`
2. Startet `stack-tester` als Subagent
3. Wartet auf Abschluss + Memory-Pfad
4. Startet `stack-reviewer` als Subagent mit Memory-Pfad
5. Zeigt finalen Bericht im Terminal

### `make test` Target (sekundär)

Da Claude Code Agenten nicht direkt von der CLI als separate Prozesse gestartet werden, dient `make test` als Hinweis:

```makefile
test:
	@echo "[$(AGENT_NS)/$(PROJ_ID)] Test via Claude Code starten:"
	@echo "  Öffne eine Claude Code Session im Repo-Verzeichnis"
	@echo "  Führe aus: /test-stack"
```

---

## Sicherheit

- TEST-Namespace vollständig isoliert von CLAUDE-Namespace (separate Named Volumes + Networks)
- Kein automatischer Produktionsstart durch Tests
- TEST-Stack wird immer bereinigt — auch bei Testfehler (`|| true` Fallback)
- `.env` wird nur gelesen, nie verändert

---

## Out of Scope

- Monitoring-Stack (`docker-compose.monitor.yml`) — separater Test (`stack-tester_monitor.md`)
- TLS-Validierung (Cloudflare DNS-01 braucht echte Domain + externes Netz)
- Vault-Integration (kommt später, siehe CLAUDE.md)
- Automatisches Fixen von Fehlern durch den Agenten

---

## Erweiterungsäste

- `.claude/agents/stack-tester_monitor.md` — separater Tester für Monitoring-Stack
- `.claude/agents/stack-tester_tls.md` — TLS-Validierung wenn Vault-Integration fertig
