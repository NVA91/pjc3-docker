# Stack-Tester Subagent System — Implementierungsplan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Zwei unabhängige Claude Code Subagenten (`stack-tester` + `stack-reviewer`) testen den pjc3-docker Stack vollständig — aufrufbar via `/test-stack` Slash-Command.

**Architecture:** `stack-tester` liest das Repo zero-knowledge, testet 3 Ebenen (Config, Container, Healthchecks), schreibt Memory-Eintrag. `stack-reviewer` prüft den Bericht unabhängig und ergänzt ihn. `/test-stack` orchestriert beide sequenziell.

**Tech Stack:** Claude Code Agents (Markdown-Frontmatter), Claude Code Commands, Bash, Docker Compose v2, curl, dig.

**Spec:** `docs/superpowers/specs/2026-03-14-stack-tester-design.md`

---

## Datei-Map

| Aktion | Pfad | Zweck |
|--------|------|-------|
| Create | `.claude/agents/stack-tester.md` | Subagent: testet Stack zero-knowledge |
| Create | `.claude/agents/stack-reviewer.md` | Subagent: prüft Bericht unabhängig |
| Create | `.claude/commands/test-stack.md` | `/test-stack` Slash-Command |
| Modify | `Makefile` | `make test` Hinweis-Target |
| Modify | `CLAUDE.md` | Verlinkung Test-System + Befehle |

---

## Chunk 1: stack-tester Agent

### Task 1: `.claude/agents/stack-tester.md` erstellen

**Files:**
- Create: `.claude/agents/stack-tester.md`

- [ ] **Step 1: Verzeichnis anlegen**

```bash
mkdir -p /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents
```

- [ ] **Step 2: Agent-Datei schreiben**

Exakter Inhalt `.claude/agents/stack-tester.md`:

```markdown
---
name: stack-tester
description: Testet den pjc3-docker Stack vollständig — zero-knowledge, 3 Ebenen (Config, Container, Healthcheck). Schreibt strukturierten Memory-Eintrag.
---

Du bist der stack-tester für den pjc3-docker Stack. Du testest vollständig und unabhängig — du liest alles selbst, du nimmst nichts als gegeben hin.

## Deine Aufgabe

Du bekommst einen Repo-Pfad. Arbeite ausschließlich in diesem Verzeichnis.

## Schritt 1: Repo einlesen (zero-knowledge)

Lies diese Dateien und verstehe den Stack:
- `docker-compose.yml` — welche Services, welche Ports
- `.env` — HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN
- `secrets/` — welche Secret-Dateien existieren müssen
- `Caddyfile` — welche Subdomains definiert sind
- `preflight.sh` — welche Checks bereits implementiert sind

Falls `.env` fehlt: Memory-Eintrag mit Fehler schreiben, abbrechen.

## Schritt 2: Ebene 1 — Konfiguration (kein Docker)

Führe jeden Check durch und notiere ✅/❌:

```bash
# .env vorhanden?
[[ -f ".env" ]] && echo "OK" || echo "FAIL: .env fehlt"

# Pflichtfelder in .env gesetzt und nicht leer?
for var in HOME_DOMAIN LAN_IP CLOUDFLARE_API_TOKEN; do
    val=$(grep "^${var}=" .env 2>/dev/null | cut -d= -f2-)
    [[ -n "$val" ]] && echo "OK: $var" || echo "FAIL: $var leer/fehlt"
done

# YAML-Syntax valid?
source .env
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    docker compose config --quiet 2>&1 && echo "OK: YAML" || echo "FAIL: YAML"

# Secrets vorhanden?
for s in secrets/pihole_webpassword secrets/vw_admin_token; do
    [[ -f "$s" ]] && echo "OK: $s" || echo "FAIL: $s fehlt"
done

# Ports frei?
for port in 53 80 443; do
    ss -ltnup 2>/dev/null | grep -q ":${port} " && echo "FAIL: Port $port belegt" || echo "OK: Port $port frei"
done
ss -lunp 2>/dev/null | grep -q ":53 " && echo "FAIL: Port 53/udp belegt" || echo "OK: Port 53/udp frei"

# preflight.sh Bash-Syntax?
bash -n preflight.sh 2>&1 && echo "OK: preflight.sh Syntax" || echo "FAIL: preflight.sh Syntax"
```

## Schritt 3: Präkondition Ebene 2 — Caddy Build

Caddy nutzt ein Custom-Dockerfile. Vor `up` muss das Image gebaut werden:

```bash
source .env
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    HOME_DOMAIN="${HOME_DOMAIN}" LAN_IP="${LAN_IP}" \
    docker compose build caddy 2>&1
```

Falls Build fehlschlägt: Ebene 2+3 überspringen, Fehler in Memory notieren.

## Schritt 4: Ebene 2 — Container-Start (TEST-Namespace)

```bash
source .env
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    HOME_DOMAIN="${HOME_DOMAIN}" LAN_IP="${LAN_IP}" \
    docker compose -p "TEST-pjc3docker" up -d 2>&1
```

Warte 10 Sekunden, dann prüfe jeden Service einzeln:

```bash
for svc in caddy vaultwarden pihole; do
    status=$(docker compose -p "TEST-pjc3docker" ps --filter "name=${svc}" --format "{{.Status}}" 2>/dev/null)
    echo "$svc: $status"
done
```

Erwartung: jeder Status enthält `Up` oder `running`.

## Schritt 5: Ebene 3 — Healthchecks

**WICHTIG — Netzwerk-Stolpersteine:**

```bash
source .env

# Caddy: HTTP→HTTPS Redirect = 308 (NICHT 200!)
caddy_code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1 2>/dev/null)
[[ "$caddy_code" == "308" ]] && echo "OK: Caddy 308" || echo "FAIL: Caddy antwortet $caddy_code (erwartet 308)"

# Vaultwarden: Host-Header erforderlich (sitzt hinter Caddy), Endpunkt /api/alive
vw_code=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Host: vault.${HOME_DOMAIN}" http://127.0.0.1/api/alive 2>/dev/null)
[[ "$vw_code" == "200" ]] && echo "OK: Vaultwarden 200" || echo "FAIL: Vaultwarden antwortet $vw_code (erwartet 200)"

# Pi-hole: Port 53 gebunden an LAN_IP (nicht localhost!)
dig_result=$(dig @${LAN_IP} google.com +short 2>/dev/null | head -1)
[[ -n "$dig_result" ]] && echo "OK: Pi-hole DNS antwortet" || echo "FAIL: Pi-hole DNS keine Antwort von $LAN_IP"
```

## Schritt 6: Cleanup (IMMER, auch bei Fehler)

```bash
docker compose -p "TEST-pjc3docker" down 2>/dev/null || true
```

## Schritt 7: Memory-Eintrag schreiben

Schreibe eine Datei nach:
`/home/ubhp-nova/.claude/projects/-home-ubhp-nova-claude-c-pjc3/memory/test_stack_YYYY-MM-DD.md`

(Datum von heute einsetzen)

Format:
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
| caddy | ✅/❌ | ✅/❌ | ✅ 308 / ❌ [code] |
| vaultwarden | ✅/❌ | ✅/❌ | ✅ 200 / ❌ [code] |
| pihole | ✅/❌ | ✅/❌ | ✅ DNS OK / ❌ keine Antwort |

**Why:** Automatischer Stack-Test vor Produktionsdeploy
**How to apply:** Bei erneutem Test prüfen ob bekannte Fehler behoben wurden
**Offene Punkte:** [Liste oder —]
**Review:** (wird vom stack-reviewer ergänzt)
```

Auch `MEMORY.md` aktualisieren: Zeile hinzufügen:
```
- [Stack-Test YYYY-MM-DD](./test_stack_YYYY-MM-DD.md) — Testergebnis pjc3-docker
```

## Abschluss

Gib im Terminal eine kompakte Zusammenfassung aus:
```
=== Stack-Test Ergebnis ===
Ebene 1 (Config):     ✅ / ❌ [was fehlschlug]
Ebene 2 (Container):  ✅ / ❌ [was fehlschlug]
Ebene 3 (Healthcheck):✅ / ❌ [was fehlschlug]
Memory: ~/.claude/.../memory/test_stack_YYYY-MM-DD.md
```
```

- [ ] **Step 3: Syntax prüfen** (Frontmatter korrekt?)

```bash
head -5 /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents/stack-tester.md
```

Erwartung: `---`, `name: stack-tester`, `description: ...`, `---`

- [ ] **Step 4: Commit**

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker && git add .claude/agents/stack-tester.md && git commit -m "feat: add stack-tester agent (zero-knowledge 3-level stack test)"
```

---

## Chunk 2: stack-reviewer Agent

### Task 2: `.claude/agents/stack-reviewer.md` erstellen

**Files:**
- Create: `.claude/agents/stack-reviewer.md`

- [ ] **Step 1: Agent-Datei schreiben**

Exakter Inhalt `.claude/agents/stack-reviewer.md`:

```markdown
---
name: stack-reviewer
description: Prüft den stack-tester Bericht unabhängig auf Vollständigkeit und Korrektheit. Ergänzt den Memory-Eintrag mit Review-Ergebnis.
---

Du bist der stack-reviewer für den pjc3-docker Stack. Du prüfst den Tester-Bericht unabhängig — du hast keinen gemeinsamen Kontext mit dem Tester.

## Deine Eingabe

Du bekommst:
1. Repo-Pfad
2. Pfad zur Memory-Datei des Testers

## Schritt 1: Fallback — Memory fehlt

Falls die Memory-Datei nicht existiert:

```
[REVIEWER] stack-tester hat keinen Bericht hinterlassen — Test unvollständig.
```

Schreibe einen eigenen Fehler-Memory-Eintrag:
`/home/ubhp-nova/.claude/projects/-home-ubhp-nova-claude-c-pjc3/memory/test_stack_YYYY-MM-DD.md`

```markdown
---
name: Stack-Test YYYY-MM-DD
description: Testergebnis pjc3-docker — ❌ Tester ohne Bericht abgebrochen
type: project
---
**Ergebnis:** ❌ Tester abgebrochen — kein Bericht
**Review:** ❌ Kein Tester-Output vorhanden
```

Danach abbrechen.

## Schritt 2: Memory-Datei lesen

Lies den Memory-Eintrag vollständig.

## Schritt 3: Unabhängige Prüfung

Prüfe jeden Punkt und notiere ✅/❌:

**Vollständigkeit:**
- [ ] Alle 3 Services getestet: caddy, vaultwarden, pihole?
- [ ] Alle 3 Ebenen abgedeckt: Config, Container, Healthcheck?
- [ ] Ebene 1 deckt: .env, YAML, Secrets, Ports, bash -n preflight.sh?

**Technische Korrektheit:**
- [ ] Caddy-Erwartung ist `308` (nicht 200)?
- [ ] Vaultwarden-Endpunkt ist `/api/alive` (nicht `/alive`)?
- [ ] Pi-hole-Query geht an `$LAN_IP` (nicht localhost)?

**Cleanup:**
- [ ] Wurde TEST-Stack bereinigt? Prüfe aktiv:
```bash
docker compose -p "TEST-pjc3docker" ps 2>/dev/null | grep -c "Up" || echo "0 Container laufen — OK"
```

**Widersprüche:**
- [ ] Gibt es Widersprüche im Bericht (z.B. "alle OK" aber Fehler aufgelistet)?

## Schritt 4: Memory ergänzen

Füge am Ende des Memory-Eintrags hinzu:

```markdown
**Review:** ✅ vollständig — alle Services + Ebenen + Erwartungen korrekt
```

ODER bei Lücken:

```markdown
**Review:** ❌ Lücken gefunden:
- [Punkt 1]
- [Punkt 2]
```

## Schritt 5: Terminal-Ausgabe

```
=== Review-Ergebnis ===
Vollständigkeit: ✅/❌
Technische Korrektheit: ✅/❌
Cleanup: ✅/❌
Gesamtergebnis: ✅ Approved / ❌ [Lücken]
```
```

- [ ] **Step 2: Syntax prüfen**

```bash
head -5 /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents/stack-reviewer.md
```

Erwartung: Frontmatter mit `name: stack-reviewer`

- [ ] **Step 3: Commit**

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker && git add .claude/agents/stack-reviewer.md && git commit -m "feat: add stack-reviewer agent (independent test report review)"
```

---

## Chunk 3: /test-stack Command + Makefile

### Task 3: `.claude/commands/test-stack.md` erstellen

**Files:**
- Create: `.claude/commands/test-stack.md`

- [ ] **Step 1: Verzeichnis anlegen**

```bash
mkdir -p /home/ubhp-nova/claude-c/pjc3-docker/.claude/commands
```

- [ ] **Step 2: Command-Datei schreiben**

Exakter Inhalt `.claude/commands/test-stack.md`:

```markdown
---
description: Testet den pjc3-docker Stack vollständig mit zwei unabhängigen Subagenten (stack-tester + stack-reviewer). Schreibt strukturierten Memory-Eintrag.
---

Führe den vollständigen Stack-Test durch. Arbeitsverzeichnis: `/home/ubhp-nova/claude-c/pjc3-docker/`

## Ablauf

### Präkondition: Caddy-Image bauen

Caddy nutzt `Dockerfile.caddy` (Custom-Build mit Cloudflare DNS-Plugin). Das Image muss vor dem Test vorhanden sein:

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker
source .env 2>/dev/null || true
AGENT_NAMESPACE=TEST AGENT_UID=$(id -u) AGENT_GID=$(id -g) \
    docker compose build caddy 2>&1
```

Falls `.env` fehlt: Stoppe und melde "Bitte zuerst `make preflight` ausführen — .env fehlt".

### Phase 1: stack-tester

Dispatche den `stack-tester` Subagenten mit folgendem Kontext:

**Repo-Pfad:** `/home/ubhp-nova/claude-c/pjc3-docker`

Warte auf Abschluss. Der Tester schreibt seinen Memory-Eintrag nach:
`/home/ubhp-nova/.claude/projects/-home-ubhp-nova-claude-c-pjc3/memory/test_stack_YYYY-MM-DD.md`
(heutiges Datum)

### Phase 2: stack-reviewer

Dispatche den `stack-reviewer` Subagenten mit:
- **Repo-Pfad:** `/home/ubhp-nova/claude-c/pjc3-docker`
- **Memory-Pfad:** Pfad zur Datei die der Tester geschrieben hat

### Abschluss

Zeige den vollständigen Memory-Eintrag im Terminal.
Gib eine finale Zeile aus:
```
Test abgeschlossen. Memory: ~/.claude/.../memory/test_stack_DATUM.md
```
```

- [ ] **Step 3: Syntax prüfen**

```bash
head -5 /home/ubhp-nova/claude-c/pjc3-docker/.claude/commands/test-stack.md
```

Erwartung: Frontmatter mit `description:`

- [ ] **Step 4: Commit**

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker && git add .claude/commands/test-stack.md && git commit -m "feat: add /test-stack slash command"
```

---

### Task 4: Makefile — `make test` Hinweis-Target

**Files:**
- Modify: `Makefile`

- [ ] **Step 1: Makefile lesen**

```bash
cat /home/ubhp-nova/claude-c/pjc3-docker/Makefile
```

- [ ] **Step 2: `.PHONY` + `test` Target einfügen**

`.PHONY` Zeile erweitern:
```makefile
.PHONY: up up-monitor down ps logs guard backup preflight test
```

Nach `preflight:` Block einfügen:
```makefile
test:
	@echo "[$(AGENT_NS)/$(PROJ_ID)] Stack-Test via Claude Code starten:"
	@echo "  1. Öffne Claude Code im Verzeichnis: $(CURDIR)"
	@echo "  2. Führe aus: /test-stack"
```

- [ ] **Step 3: Syntax-Check**

```bash
make --dry-run AGENT_NAMESPACE=TEST test 2>&1 | head -5
```

Erwartung: Kein `missing separator` Fehler.

- [ ] **Step 4: Commit**

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker && git add Makefile && git commit -m "feat: add make test hint target"
```

---

## Chunk 4: CLAUDE.md — direkte Verlinkung

### Task 5: CLAUDE.md Test-System-Abschnitt + Verlinkung

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: CLAUDE.md lesen**

```bash
cat /home/ubhp-nova/claude-c/pjc3-docker/CLAUDE.md
```

- [ ] **Step 2: Befehle-Abschnitt erweitern**

Im Abschnitt `## Befehle` nach `AGENT_NAMESPACE=CLAUDE make preflight` einfügen:

```bash
# Stack testen (Claude Code Session erforderlich):
/test-stack                            # Slash-Command innerhalb Claude Code
AGENT_NAMESPACE=CLAUDE make test       # Zeigt Anleitung für /test-stack
```

- [ ] **Step 3: Neuen Abschnitt `## Test-System` einfügen**

Nach dem Abschnitt `## Befehle`, vor `## Host-Setup`:

```markdown
## Test-System

Zwei unabhängige Claude Code Subagenten testen den Stack vollständig.

**Aufruf:** `/test-stack` in einer Claude Code Session im Repo-Verzeichnis

**Agenten:**
- `.claude/agents/stack-tester.md` — liest Repo zero-knowledge, testet 3 Ebenen
- `.claude/agents/stack-reviewer.md` — prüft Bericht unabhängig, meldet Lücken

**Testablauf:**
1. Präkondition: Caddy-Image bauen (`docker compose build caddy`)
2. Ebene 1 — Konfiguration: `.env`, YAML, Secrets, Ports, `bash -n preflight.sh`
3. Ebene 2 — Container: `docker compose -p TEST-pjc3docker up -d` → alle `running`
4. Ebene 3 — Healthchecks (Netzwerk-Stolpersteine):
   - Caddy: `curl http://127.0.0.1` → `308` (HTTP→HTTPS Redirect = gesund, nicht 200!)
   - Vaultwarden: `curl -H "Host: vault.$HOME_DOMAIN" http://127.0.0.1/api/alive` → `200` (Host-Header + /api/alive Pflicht)
   - Pi-hole: `dig @$LAN_IP google.com` → Antwort ohne SERVFAIL (Port 53 an LAN_IP gebunden, nicht localhost)
5. Cleanup: TEST-Stack immer bereinigt (`docker compose ... down`)
6. Memory-Eintrag: `~/.claude/projects/-home-ubhp-nova-claude-c-pjc3/memory/test_stack_YYYY-MM-DD.md`
7. MEMORY.md wird vom stack-tester automatisch mit neuem Eintrag aktualisiert

**Out of Scope:**
- TLS-Validierung (braucht echte Domain + Cloudflare)
- Monitoring-Stack (`docker-compose.monitor.yml`)
- Automatisches Fixen von Fehlern
```

- [ ] **Step 4: Commit**

```bash
cd /home/ubhp-nova/claude-c/pjc3-docker && git add CLAUDE.md && git commit -m "docs: add test system section and /test-stack links to CLAUDE.md"
```

---

## Chunk 5: Verifikation

### Task 6: Smoke-Test aller neuen Dateien

**Kein Code — nur Verifikation.**

- [ ] **Step 1: Alle Dateien vorhanden?**

```bash
ls -la /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents/
ls -la /home/ubhp-nova/claude-c/pjc3-docker/.claude/commands/
```

Erwartung:
```
.claude/agents/stack-tester.md
.claude/agents/stack-reviewer.md
.claude/commands/test-stack.md
```

- [ ] **Step 2: Frontmatter korrekt?**

```bash
for f in \
    /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents/stack-tester.md \
    /home/ubhp-nova/claude-c/pjc3-docker/.claude/agents/stack-reviewer.md \
    /home/ubhp-nova/claude-c/pjc3-docker/.claude/commands/test-stack.md; do
    echo "=== $f ==="
    head -4 "$f"
done
```

Erwartung: Jede Datei beginnt mit `---` und hat `name:` oder `description:`.

- [ ] **Step 3: Git-Log prüfen**

```bash
git -C /home/ubhp-nova/claude-c/pjc3-docker log --oneline -6
```

Erwartung: 5 neue Commits (Tasks 1–5) sichtbar.

- [ ] **Step 4: CLAUDE.md Test-System-Abschnitt vorhanden?**

```bash
grep -n "Test-System\|test-stack\|stack-tester" /home/ubhp-nova/claude-c/pjc3-docker/CLAUDE.md
```

Erwartung: Mindestens 3 Treffer.

- [ ] **Step 5: Kein leerer Commit nötig — fertig**

```bash
git -C /home/ubhp-nova/claude-c/pjc3-docker status
```

Erwartung: `nothing to commit, working tree clean`

---

## Ergebnis

Nach allen Tasks:
- `/test-stack` in Claude Code startet vollständigen Stack-Test
- `stack-tester` testet zero-knowledge: Config → Container → Healthchecks (Caddy 308, Vaultwarden /api/alive, Pi-hole LAN_IP)
- `stack-reviewer` prüft Bericht unabhängig auf Vollständigkeit
- Memory-Eintrag dokumentiert Ergebnis dauerhaft
- `CLAUDE.md` verlinkt direkt auf Agenten + erklärt Testablauf
