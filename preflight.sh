#!/usr/bin/env bash
# preflight.sh — Pre-Flight Stack-Start-Checkliste
# Verwendung: AGENT_NAMESPACE=CLAUDE AGENT_UID=1001 AGENT_GID=1001 bash preflight.sh
# Oder:       AGENT_NAMESPACE=CLAUDE make preflight
set -euo pipefail

# --- Farben ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

phase2_env() {
    info "Phase 2: Demo-Env aus .env.example erstellen"
    [[ -f ".env.example" ]] || fail ".env.example nicht gefunden — kann keine Demo-Env erstellen"

    cp .env.example .env
    ok ".env aus .env.example erstellt"
    echo ""
    info "Bitte jetzt die Pflichtfelder in .env anpassen:"
    info "  HOME_DOMAIN   — deine Heim-Domain (z.B. home.example.com)"
    info "  LAN_IP        — IP des Docker-Hosts im LAN (z.B. 192.168.178.100)"
    info "  CLOUDFLARE_API_TOKEN — Cloudflare API Token (Edit zone DNS)"
    echo ""
    info "Datei: $(pwd)/.env"
    echo ""
    read -r -p "$(echo -e "${YELLOW}[INFO]${NC} .env fertig ausgefüllt? Weiter mit Phase 1? [j/N] ")" ans
    [[ "$ans" == "j" ]] || { info "Abgebrochen. Bitte .env ausfüllen und preflight erneut starten."; exit 0; }
}

# --- Pflicht-Env ---
: "${AGENT_NAMESPACE:?AGENT_NAMESPACE muss gesetzt sein}"
: "${AGENT_UID:?AGENT_UID muss gesetzt sein}"
: "${AGENT_GID:?AGENT_GID muss gesetzt sein}"

phase1_syntax() {
    info "Phase 1: Syntax & Config-Validierung"

    # .env vorhanden?
    if [[ ! -f ".env" ]]; then
        info ".env fehlt — starte Phase 2 (Demo-Env erstellen)..."
        phase2_env
    fi
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

    # Ports frei? (TCP)
    for port in 53 80 443; do
        if ss -ltnup 2>/dev/null | grep -q ":${port} "; then
            fail "Port ${port}/tcp ist bereits belegt"
        fi
        ok "Port ${port}/tcp frei"
    done
    # UDP Port 53 separat
    if ss -lunp 2>/dev/null | grep -q ":53 "; then
        fail "Port 53/udp ist bereits belegt"
    fi
    ok "Port 53/udp frei"
}

phase3_dryrun() {
    info "Phase 3: Dry-Run (AGENT_NAMESPACE=TEST)"
    AGENT_NAMESPACE=TEST AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
        docker compose --dry-run up 2>&1 || fail "Dry-Run fehlgeschlagen — Stack würde nicht starten"
    ok "Dry-Run erfolgreich"
}

phase4_test_namespace() {
    info "Phase 4: Test-Namespace Start (AGENT_NAMESPACE=TEST)"

    info "Starte Stack im Test-Namespace..."
    AGENT_NAMESPACE=TEST AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
        docker compose -p "TEST-pjc3docker" up -d 2>&1 || fail "Test-Namespace Start fehlgeschlagen"
    ok "Test-Stack gestartet"

    info "Warte 5 Sekunden auf Container-Startup..."
    sleep 5

    running=$(docker compose -p "TEST-pjc3docker" ps --filter "status=running" --format "{{.Name}}" 2>/dev/null | wc -l)
    total=$(docker compose -p "TEST-pjc3docker" ps --format "{{.Name}}" 2>/dev/null | wc -l)

    if [[ "$running" -lt "$total" ]]; then
        info "Container-Status:"
        docker compose -p "TEST-pjc3docker" ps
        docker compose -p "TEST-pjc3docker" down 2>/dev/null || true
        fail "Nicht alle Container laufen ($running von $total)"
    fi
    ok "Alle ${total} Container laufen im Test-Namespace"

    info "Test-Stack wird jetzt beendet..."
    docker compose -p "TEST-pjc3docker" down 2>&1
    ok "Test-Stack entfernt"
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
    read -r -p "$(echo -e "${YELLOW}[INFO]${NC} Phase 3 (Dry-Run) starten? [j/N] ")" ans
    [[ "$ans" == "j" ]] || { info "Abgebrochen nach Phase 1."; exit 0; }

    phase3_dryrun
    echo ""
    ok "=== Phase 3 abgeschlossen ==="
    echo ""
    read -r -p "$(echo -e "${YELLOW}[INFO]${NC} Phase 4 (Test-Namespace Start) starten? [j/N] ")" ans
    [[ "$ans" == "j" ]] || { info "Abgebrochen nach Phase 3."; exit 0; }

    phase4_test_namespace
    echo ""
    ok "=== Phase 4 abgeschlossen — alle Phasen bestanden ==="
    echo ""
    info "Stack bereit. Produktionsstart:"
    info "  AGENT_NAMESPACE=CLAUDE make up"
    echo ""
    read -r -p "$(echo -e "${YELLOW}[INFO]${NC} Produktion jetzt starten? [j/N] ")" prod_ans
    if [[ "$prod_ans" == "j" ]]; then
        info "Starte Produktion..."
        AGENT_NAMESPACE="${AGENT_NAMESPACE}" AGENT_UID="${AGENT_UID}" AGENT_GID="${AGENT_GID}" \
            docker compose -p "${AGENT_NAMESPACE}-pjc3docker" up -d
        ok "Produktion gestartet."
    else
        info "Produktionsstart übersprungen. Manuell: AGENT_NAMESPACE=CLAUDE make up"
    fi
}

main "$@"
