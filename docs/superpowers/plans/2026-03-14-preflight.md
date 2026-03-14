# Pre-Flight Stack-Start-Checkliste — Implementierungsplan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `preflight.sh` — 4-phasige Validierung vor dem Start des pjc3-docker Stacks; `make preflight` als Einstiegspunkt.

**Architecture:** Ein sequenzielles Bash-Skript mit vier klar abgegrenzten Phasen (Syntax, Env-Subagent, Dry-Run, Test-Namespace). Jede Phase ist eine eigene Funktion. Das Skript stoppt hart bei Fehler (`set -euo pipefail`). Das Makefile bekommt ein `preflight`-Target das die Env-Variablen weiterreicht.

**Tech Stack:** Bash, Docker Compose v2, `docker compose config --quiet`, `caddy validate`, Makefile.

---

## Chunk 1: File-Map & Makefile-Target

### Dateien

| Aktion | Pfad | Zweck |
|--------|------|-------|
| Create | `preflight.sh` | Haupt-Skript (4 Phasen) |
| Modify | `Makefile` | + `preflight` Target |

---

### Task 1: Makefile — `preflight` Target

**Dateien:**
- Modify: `Makefile` (nach `backup:` einfügen)

- [ ] **Step 1: Makefile lesen**

```bash
cat Makefile
```

Erwartung: `backup`-Target ist der letzte Eintrag.

- [ ] **Step 2: `preflight` Target einfügen**

In `Makefile` nach `backup:` Block einfügen:

```makefile
preflight:
	@AGENT_NAMESPACE=$(AGENT_NS) AGENT_UID=$(shell id -u) AGENT_GID=$(shell id -g) bash preflight.sh
```

Auch `.PHONY` Zeile erweitern:

```makefile
.PHONY: up up-monitor down ps logs guard backup preflight
```

- [ ] **Step 3: Syntax-Check Makefile**

```bash
make --dry-run AGENT_NAMESPACE=TEST preflight 2>&1 | head -5
```

Erwartung: Kein `Makefile:XX: *** missing separator` Fehler.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "feat: add make preflight target"
```

---

## Chunk 2: preflight.sh — Grundgerüst & Phase 1

### Task 2: Grundgerüst mit Farb-Ausgabe + Phase-1-Skeleton

**Dateien:**
- Create: `preflight.sh`

- [ ] **Step 1: Datei anlegen**

```bash
touch preflight.sh && chmod +x preflight.sh
```

- [ ] **Step 2: Grundgerüst schreiben**

Inhalt `preflight.sh`:

```bash
#!/usr/bin/env bash
# preflight.sh — Pre-Flight Stack-Start-Checkliste
# Verwendung: AGENT_NAMESPACE=CLAUDE AGENT_UID=1001 AGENT_GID=1001 bash preflight.sh
# Oder:       AGENT_NAMESPACE=CLAUDE make preflight
set -euo pipefail

# --- Farben ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'  # No Color

ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

# --- Pflicht-Env ---
: "${AGENT_NAMESPACE:?AGENT_NAMESPACE muss gesetzt sein}"
: "${AGENT_UID:?AGENT_UID muss gesetzt sein}"
: "${AGENT_GID:?AGENT_GID muss gesetzt sein}"

phase1_syntax() {
    info "Phase 1: Syntax & Config-Validierung"
    # .env vorhanden?
    [[ -f ".env" ]] || fail ".env nicht gefunden. Bitte aus .env.example kopieren."
    ok ".env vorhanden"

    # Pflichtfelder in .env
    for var in HOME_DOMAIN LAN_IP CLOUDFLARE_API_TOKEN; do
        grep -q "^${var}=" .env || fail "Pflichtfeld fehlt in .env: ${var}"
        val=$(grep "^${var}=" .env | cut -d= -f2-)
        [[ -n "$val" ]] || fail "Pflichtfeld leer in .env: ${var}"
        ok ".env: ${var} gesetzt"
    done

    # YAML-Validierung
    AGENT_NAMESPACE="${AGENT_NAMESPACE}" AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
        docker compose config --quiet 2>&1 || fail "docker compose config --quiet fehlgeschlagen"
    ok "docker-compose.yml YAML-Syntax valid"

    # Caddyfile-Syntax (nur falls caddy binary vorhanden)
    if command -v caddy &>/dev/null; then
        caddy validate --config Caddyfile &>/dev/null || fail "Caddyfile-Syntax ungültig"
        ok "Caddyfile-Syntax valid"
    else
        info "caddy nicht installiert — Caddyfile-Check übersprungen"
    fi

    # Secrets vorhanden?
    for secret in secrets/pihole_webpassword secrets/vw_admin_token; do
        [[ -f "$secret" ]] || fail "Secret nicht gefunden: ${secret}"
        ok "Secret vorhanden: ${secret}"
    done

    # Ports frei?
    for port in 53 80 443; do
        if ss -ltnup 2>/dev/null | grep -q ":${port} "; then
            fail "Port ${port} ist bereits belegt"
        fi
        ok "Port ${port} frei"
    done
    # UDP Port 53 separat
    if ss -lunp 2>/dev/null | grep -q ":53 "; then
        fail "Port 53/udp ist bereits belegt"
    fi
    ok "Port 53/udp frei"
}

main() {
    echo ""
    info "=== pjc3-docker Pre-Flight Check ==="
    info "Namespace: ${AGENT_NAMESPACE}"
    echo ""

    phase1_syntax
    echo ""
    ok "=== Phase 1 abgeschlossen ==="
    echo ""
    info "Nächste Schritte: Phase 3 (Dry-Run) und Phase 4 (Test-Namespace) kommen in den nächsten Tasks."
    info "Für jetzt: 'AGENT_NAMESPACE=CLAUDE make up' manuell starten."
}

main "$@"
```

- [ ] **Step 3: Smoke-Test (ohne echte .env)**

```bash
bash preflight.sh 2>&1 | head -3
```

Erwartung: Zeile `[FAIL] AGENT_NAMESPACE muss gesetzt sein` oder ähnlich — bestätigt `set -euo pipefail` greift.

```bash
AGENT_NAMESPACE=TEST AGENT_UID=1001 AGENT_GID=1001 bash preflight.sh 2>&1 | head -5
```

Erwartung: `[FAIL] .env nicht gefunden` (korrekt, falls keine .env vorhanden).

- [ ] **Step 4: Commit**

```bash
git add preflight.sh
git commit -m "feat: add preflight.sh with phase 1 (syntax & config validation)"
```

---

## Chunk 3: Phase 3 (Dry-Run) & Phase 4 (Test-Namespace)

### Task 3: Phase 3 — Dry-Run

**Dateien:**
- Modify: `preflight.sh` (Funktion `phase3_dryrun` einfügen + `main()` erweitern)

- [ ] **Step 1: `phase3_dryrun` Funktion einfügen**

Nach `phase1_syntax()` Funktion, vor `main()`, einfügen:

```bash
phase3_dryrun() {
    info "Phase 3: Dry-Run (AGENT_NAMESPACE=TEST)"
    AGENT_NAMESPACE=TEST AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
        docker compose --dry-run up 2>&1 || fail "Dry-Run fehlgeschlagen — Stack würde nicht starten"
    ok "Dry-Run erfolgreich"
}
```

- [ ] **Step 2: `main()` erweitern**

`main()` nach `phase1_syntax` Aufruf ergänzen:

```bash
    echo ""
    read -r -p "[INFO] Phase 3 (Dry-Run) starten? [j/N] " ans
    [[ "$ans" == "j" ]] || { info "Abgebrochen nach Phase 1."; exit 0; }

    phase3_dryrun
    echo ""
    ok "=== Phase 3 abgeschlossen ==="
```

- [ ] **Step 3: Manuell testen**

```bash
AGENT_NAMESPACE=CLAUDE AGENT_UID=1001 AGENT_GID=1001 bash preflight.sh
```

Phase 1 durchlaufen lassen (oder mit echter `.env` testen), dann `j` bei Phase-3-Prompt eingeben.

Erwartung: `docker compose --dry-run up` Output erscheint, dann `[OK] Dry-Run erfolgreich`.

- [ ] **Step 4: Commit**

```bash
git add preflight.sh
git commit -m "feat: add phase 3 dry-run to preflight.sh"
```

---

### Task 4: Phase 4 — Test-Namespace Start + manuelle Bestätigung

**Dateien:**
- Modify: `preflight.sh` (Funktion `phase4_test_namespace` einfügen + `main()` erweitern)

- [ ] **Step 1: `phase4_test_namespace` Funktion einfügen**

Nach `phase3_dryrun()`, vor `main()`:

```bash
phase4_test_namespace() {
    info "Phase 4: Test-Namespace Start (AGENT_NAMESPACE=TEST)"

    info "Starte Stack im Test-Namespace..."
    AGENT_NAMESPACE=TEST AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
        docker compose -p "TEST-pjc3docker" up -d 2>&1 || fail "Test-Namespace Start fehlgeschlagen"
    ok "Test-Stack gestartet"

    # Container-Status prüfen
    info "Warte 5 Sekunden auf Container-Startup..."
    sleep 5

    not_running=$(docker compose -p "TEST-pjc3docker" ps --filter "status=running" --format "{{.Name}}" 2>/dev/null | wc -l)
    total=$(docker compose -p "TEST-pjc3docker" ps --format "{{.Name}}" 2>/dev/null | wc -l)

    if [[ "$not_running" -lt "$total" ]]; then
        info "Container-Status:"
        docker compose -p "TEST-pjc3docker" ps
        fail "Nicht alle Container laufen ($not_running von $total)"
    fi
    ok "Alle ${total} Container laufen im Test-Namespace"

    info "Test-Stack wird jetzt beendet..."
    docker compose -p "TEST-pjc3docker" down 2>&1
    ok "Test-Stack entfernt"
}
```

- [ ] **Step 2: `main()` abschliessen**

Nach Phase-3-Block in `main()`:

```bash
    echo ""
    read -r -p "[INFO] Phase 4 (Test-Namespace Start) starten? [j/N] " ans
    [[ "$ans" == "j" ]] || { info "Abgebrochen nach Phase 3."; exit 0; }

    phase4_test_namespace
    echo ""
    ok "=== Phase 4 abgeschlossen — alle Phasen bestanden ==="
    echo ""
    info "Stack bereit. Produktionsstart:"
    info "  AGENT_NAMESPACE=CLAUDE make up"
    echo ""
    read -r -p "[INFO] Produktion jetzt starten? [j/N] " prod_ans
    if [[ "$prod_ans" == "j" ]]; then
        info "Starte Produktion..."
        AGENT_NAMESPACE="${AGENT_NAMESPACE}" AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
            docker compose -p "${AGENT_NAMESPACE}-pjc3docker" up -d
        ok "Produktion gestartet."
    else
        info "Produktionsstart übersprungen. Manuell: AGENT_NAMESPACE=CLAUDE make up"
    fi
```

- [ ] **Step 3: Vollständige `main()` überprüfen**

```bash
grep -n "phase[0-9]" preflight.sh
```

Erwartung: Alle 3 Phasen-Aufrufe sichtbar (phase1, phase3, phase4) + Prompts.

- [ ] **Step 4: Commit**

```bash
git add preflight.sh
git commit -m "feat: add phase 4 test-namespace start + production confirmation to preflight.sh"
```

---

## Chunk 4: Verifikation & Dokumentation

### Task 5: End-to-End Smoke-Test (ohne laufende Docker-Dienste)

**Kein Code — nur Verifikation.**

- [ ] **Step 1: Skript auf Bash-Syntax prüfen**

```bash
bash -n preflight.sh && echo "Syntax OK"
```

Erwartung: `Syntax OK` ohne Fehler.

- [ ] **Step 2: shellcheck (falls vorhanden)**

```bash
command -v shellcheck && shellcheck preflight.sh || echo "shellcheck nicht installiert — überspringen"
```

Erwartung: Keine Fehler (Warnings SC2034 für Farb-Variablen sind akzeptabel).

- [ ] **Step 3: Fehlerpfad testen (kein .env)**

```bash
AGENT_NAMESPACE=CLAUDE AGENT_UID=1001 AGENT_GID=1001 bash preflight.sh 2>&1
```

Erwartung wenn keine `.env` existiert:
```
[INFO] === pjc3-docker Pre-Flight Check ===
[INFO] Namespace: CLAUDE

[INFO] Phase 1: Syntax & Config-Validierung
[FAIL] .env nicht gefunden. Bitte aus .env.example kopieren.
```
Exit-Code muss 1 sein: `echo $?` → `1`

- [ ] **Step 4: Commit (falls noch kein finaler Commit)**

```bash
git add preflight.sh Makefile
git commit -m "docs: verify preflight.sh end-to-end smoke test"
```

---

### Task 6: CLAUDE.md — Befehle-Abschnitt aktualisieren

**Dateien:**
- Modify: `CLAUDE.md` (Befehle-Abschnitt)

- [ ] **Step 1: `make preflight` in Befehle-Abschnitt eintragen**

Im Abschnitt `## Befehle` ergänzen:

```bash
# Pre-Flight vor Stack-Start:
AGENT_NAMESPACE=CLAUDE make preflight
```

- [ ] **Step 2: "Nächste Aufgabe"-Abschnitt bereinigen**

Den Block `## Nächste Aufgabe: Pre-Flight Checkliste implementieren` entfernen (erledigt).

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with preflight command"
```

---

## Ergebnis

Nach allen Tasks:
- `preflight.sh` läuft durch alle 4 Phasen (Phase 2 ist Out-of-Scope für diese Iteration)
- `AGENT_NAMESPACE=CLAUDE make preflight` ist der einzige Einstiegspunkt vor dem Stack-Start
- Jeder Phasenübergang erfordert manuelle Bestätigung
- Produktionsstart wird erst nach Phase 4 angeboten — niemals automatisch
