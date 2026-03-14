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

main() {
    echo ""
    info "=== pjc3-docker Pre-Flight Check ==="
    info "Namespace: ${AGENT_NAMESPACE}"
    echo ""

    phase1_syntax
    echo ""
    ok "=== Phase 1 abgeschlossen ==="
    echo ""
    info "Nächste Schritte: Phase 3 (Dry-Run) und Phase 4 (Test-Namespace) — coming soon."
    info "Für jetzt: 'AGENT_NAMESPACE=CLAUDE make up' manuell starten."
}

main "$@"
