# Design: Stack-Tester Subagent System

**Datum:** 2026-03-14
**Status:** Approved

---

## Ziel

Zwei unabhängige Claude Code Subagenten testen den pjc3-docker Stack vollständig — zero-knowledge, ohne Annahmen des Erstellers. Auslöser: `/test-stack` Slash-Command oder `make test`. Ergebnis: strukturierter Memory-Eintrag + Terminal-Ausgabe.

---

## Warum diese Entscheidung

**Zwei separate Agenten (stack-tester + stack-reviewer)** wurden gewählt weil:

1. **Echte Isolation** — Tester und Reviewer haben keinen gemeinsamen Kontext. Der Reviewer kann den Tester nicht rationalisieren.
2. **Zero-Knowledge** — Beide lesen das Repo selbst und leiten daraus ab was zu testen ist. Kein hardcoded Wissen über "was schon getestet wurde".
3. **Claude Code Agent** statt Bash-Skript — kann Fehler interpretieren, auf unerwartete Ausgaben reagieren, Empfehlungen geben.
4. **Memory statt Logs** — Testergebnisse werden als strukturiertes Projektwissen gespeichert, nicht als rohe Ausgabedateien.

---

## Architektur

```
pjc3-docker/
├── .claude/
│   ├── agents/
│   │   ├── stack-tester.md      # Subagent: testet Stack zero-knowledge
│   │   └── stack-reviewer.md    # Subagent: prüft Tester + Bericht unabhängig
│   └── commands/
│       └── test-stack.md        # /test-stack Slash-Command
└── Makefile                     # + make test Target
```

**Ablauf:**

```
/test-stack  oder  make test
      ↓
stack-tester (frischer Subagent, zero-knowledge)
  → liest Repo: docker-compose.yml, Caddyfile, .env, preflight.sh, secrets/
  → erstellt eigenen Testplan (3 Ebenen)
  → führt Tests aus
  → Terminal-Ausgabe (kompakt) + Memory-Eintrag schreiben
      ↓
stack-reviewer (frischer Subagent, unabhängig)
  → bekommt: Repo-Pfad + Memory-Eintrag
  → prüft Vollständigkeit und Plausibilität
  → ergänzt Memory-Eintrag mit Review-Ergebnis
      ↓
Finaler Bericht im Terminal
```

---

## Komponenten

### stack-tester Agent

**Trigger:** Von `/test-stack` oder `make test` gestartet.

**Eingabe:** Repo-Pfad

**Was er liest (selbst, zero-knowledge):**
- `docker-compose.yml` — welche Services existieren, welche Ports
- `.env` — HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN
- `secrets/` — welche Secret-Dateien vorhanden sein müssen
- `Caddyfile` — welche Subdomains definiert sind
- `preflight.sh` — welche Checks bereits implementiert sind

**Testplan (3 Ebenen):**

**Ebene 1 — Konfiguration (ohne Docker):**
- `.env` vorhanden + Pflichtfelder gesetzt + nicht leer (HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN)
- `docker-compose.yml` YAML-Syntax: `docker compose config --quiet`
- Secrets vorhanden: `secrets/pihole_webpassword`, `secrets/vw_admin_token`
- Ports frei: 53/tcp, 53/udp, 80, 443 (via `ss`)
- `preflight.sh` Bash-Syntax: `bash -n preflight.sh`

**Ebene 2 — Container-Start (TEST-Namespace):**
- `docker compose -p TEST-pjc3docker up -d` startet fehlerfrei
- Alle Container Status `running` (nicht `exited`, `restarting`)
- Jeder Service einzeln geprüft: caddy, vaultwarden, pihole

**Ebene 3 — Service-Healthchecks (Netzwerk-Stolpersteine beachten):**

| Service | Kommando | Erwartung | Begründung |
|---------|----------|-----------|------------|
| Caddy | `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1` | `308` | Caddy redirectet HTTP→HTTPS; 308 = gesund |
| Vaultwarden | `curl -s -o /dev/null -w "%{http_code}" -H "Host: vault.${HOME_DOMAIN}" http://127.0.0.1/alive` | `200` | Vaultwarden sitzt hinter Caddy im internen Netz; Host-Header erforderlich |
| Pi-hole | `dig @${LAN_IP} google.com` | Antwort ohne SERVFAIL | Pi-hole bindet Port 53 an LAN_IP, nicht localhost |

**Abschluss:**
- TEST-Stack wird immer bereinigt: `docker compose -p TEST-pjc3docker down`
- Memory-Eintrag schreiben (auch bei Fehler)
- Kompakte Terminal-Ausgabe: ✅/❌ pro Service

**Memory-Format:**
```markdown
---
name: Stack-Test 2026-03-14
description: Testergebnis pjc3-docker Stack vom 2026-03-14
type: project
---
**Ergebnis:** ✅ alle Tests bestanden / ❌ Fehler gefunden
**Getestet:** 2026-03-14

| Service | Konfiguration | Container | Healthcheck |
|---------|--------------|-----------|-------------|
| caddy | ✅ | ✅ | ✅ 308 |
| vaultwarden | ✅ | ✅ | ✅ 200 |
| pihole | ✅ | ✅ | ✅ DNS OK |

**Offene Punkte:** —
**Review:** (wird vom stack-reviewer ergänzt)
```

---

### stack-reviewer Agent

**Trigger:** Nach stack-tester, automatisch von `/test-stack`.

**Eingabe:** Repo-Pfad + Memory-Eintrag des Testers (Pfad)

**Prüft unabhängig:**
- Wurden alle 3 Services getestet (caddy, vaultwarden, pihole)?
- Sind alle 3 Ebenen abgedeckt (Konfiguration, Container, Healthcheck)?
- Sind die Healthcheck-Erwartungen korrekt (308/200/DNS ohne SERVFAIL)?
- Gibt es Widersprüche im Bericht?
- Wurde TEST-Stack bereinigt?

**Ausgabe:**
- Ergänzt Memory-Eintrag: `**Review:** ✅ vollständig / ❌ Lücken: [Liste]`
- Terminal: kurzes Review-Ergebnis

---

### `/test-stack` Slash-Command

Startet stack-tester → wartet → startet stack-reviewer → zeigt finalen Memory-Eintrag.

### `make test` Target

```makefile
test:
	@AGENT_NAMESPACE=$(AGENT_NS) AGENT_UID=$$(id -u) AGENT_GID=$$(id -g) \
	    claude --agent stack-tester "$(CURDIR)"
```

---

## Sicherheit

- TEST-Namespace ist vollständig von CLAUDE-Namespace isoliert (separate Named Volumes + Networks)
- Kein automatischer Produktionsstart durch Tests
- TEST-Stack wird immer bereinigt — auch bei Testfehler

---

## Out of Scope

- Monitoring-Stack (`docker-compose.monitor.yml`) — separater Test
- TLS-Validierung (Cloudflare DNS-01 braucht echte Domain + externes Netz)
- Vault-Integration (kommt später, siehe CLAUDE.md)
- Automatisches Fixen von Fehlern durch den Agenten

---

## Erweiterungsäste

- `stack-tester_monitor.md` — separater Tester für Monitoring-Stack
- `stack-tester_tls.md` — TLS-Validierung wenn Vault-Integration fertig
