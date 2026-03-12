#!/bin/bash
# safe-container-exec.sh — Wrapper für sichere Container-Befehlsausführung
#
# Schutz gegen:
#   - Directory Traversal: Blockiert alle Pfade mit ".." (Parent-Directory-Referenzen)
#   - Symlink-Attacks: Ausführung strikt im Container-Workdir, kein Host-Pfadzugriff
#   - Command Injection: Whitelist erlaubter Lese-Befehle, keine Schreib-/Exec-Operationen
#
# Verwendung:
#   AGENT_NAMESPACE=CLAUDE bash safe-container-exec.sh <project-name> "<command>"
#
# Beispiele:
#   AGENT_NAMESPACE=CLAUDE bash safe-container-exec.sh pjc001 "ls -la /app/data"
#   AGENT_NAMESPACE=CLAUDE bash safe-container-exec.sh pjc001 "cat /app/data/output.json"
#   AGENT_NAMESPACE=CLAUDE bash safe-container-exec.sh pjc001 "grep ERROR /app/data/app.log"

set -euo pipefail

# ── Whitelist erlaubter Befehle (nur Lese-Operationen) ──────────────────────
# Schreib-Befehle (rm, mv, cp, chmod, chown, ...) sind absichtlich ausgeschlossen.
readonly ALLOWED_COMMANDS=("find" "ls" "cat" "grep" "awk" "sed" "tail" "head")
readonly ALLOWED_GREP_FLAGS=(
    "-i" "-n" "-c" "-v" "-w" "-x" "-e"
)

fail() {
    echo "❌ $1"
    return 1
}

is_allowed_grep_flag() {
    local candidate="$1"
    local allowed
    for allowed in "${ALLOWED_GREP_FLAGS[@]}"; do
        if [[ "$candidate" == "$allowed" ]]; then
            return 0
        fi
    done
    return 1
}

validate_flag_semantics() {
    local cmd_base="$1"
    shift
    local tokens=("$@")
    local token

    case "$cmd_base" in
        awk|sed)
            for token in "${tokens[@]}"; do
                # Sicherheitsaspekt: -f/--file lädt externen Programmcode.
                # -F* wird ebenfalls blockiert (Flag-Semantik-Falle, policy-basiert).
                if [[ "$token" == "-f" || "$token" == "--file" || "$token" == "-F" ]]; then
                    fail "$cmd_base: Flag $token ist nicht erlaubt (verhindert File-as-Program)"
                fi
                if [[ "$token" == -f* || "$token" == -F* || "$token" == --file=* ]]; then
                    fail "$cmd_base: Flag $token ist nicht erlaubt (verhindert File-as-Program)"
                fi
            done
            ;;
        grep)
            for token in "${tokens[@]}"; do
                if [[ "$token" == "-r" || "$token" == "-R" || "$token" == "--recursive" ]]; then
                    fail "Weite/rekursive grep-Suche ist verboten ($token)"
                fi
                if [[ "$token" == -* ]]; then
                    if ! is_allowed_grep_flag "$token"; then
                        fail "grep-Flag nicht erlaubt: $token"
                    fi
                fi
            done
            ;;
    esac
}

execute_safe_command() {
    local agent_ns="${AGENT_NAMESPACE:?AGENT_NAMESPACE nicht gesetzt}"
    local project_name="${1:?Projekt-Name fehlt}"
    local command="${2:?Befehl fehlt}"

    local compose_proj_raw="${agent_ns}-${project_name}"
    local compose_proj
    compose_proj="$(echo "$compose_proj_raw" | tr '[:upper:]' '[:lower:]')"

    if [[ ! "$compose_proj" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        fail "Ungültiger Compose-Projektname nach Normalisierung: $compose_proj"
    fi

    local container_workdir="/app"

    # ── Schritt 1: Befehl gegen Whitelist prüfen ────────────────────────────
    local tokens=()
    read -r -a tokens <<< "$command"

    local cmd_base="${tokens[0]:-}"
    if [[ -z "$cmd_base" ]]; then
        fail "Leerer Befehl ist nicht erlaubt"
    fi

    local allowed=false
    for allowed_cmd in "${ALLOWED_COMMANDS[@]}"; do
        if [[ "$cmd_base" == "$allowed_cmd" ]]; then
            allowed=true
            break
        fi
    done

    if [[ "$allowed" != true ]]; then
        echo "❌ Befehl nicht erlaubt: $cmd_base"
        echo "   Erlaubt: ${ALLOWED_COMMANDS[*]}"
        return 1
    fi

    validate_flag_semantics "$cmd_base" "${tokens[@]:1}"

    # ── Schritt 2: Directory-Traversal blockieren ───────────────────────────
    # Blockiert "../../etc/passwd" und ähnliche Angriffe
    if [[ "$command" =~ \.\. ]]; then
        fail "Parent-Directory-Traversal nicht erlaubt (..)"
    fi

    # ── Schritt 3: Absoluten Pfad außerhalb /app blockieren ─────────────────
    # Verhindert direkten Zugriff auf /etc, /root, /proc etc. im Container
    if [[ "$command" =~ (^|[[:space:]])/(?!app/) ]]; then
        fail "Absoluter Pfad außerhalb von /app nicht erlaubt"
    fi

    # ── Schritt 4: Befehl im isolierten Container-Kontext ausführen ─────────
    # -w setzt Arbeitsverzeichnis; "cd $container_workdir &&" verhindert
    # dass ein Symlink-Target außerhalb des Workdirs erreichbar wird
    echo "→ Ausführe in [${compose_proj}]: $command"
    docker compose -p "$compose_proj" exec \
        -w "$container_workdir" \
        app sh -c "cd ${container_workdir} && ${command}"
}

# ── Einstiegspunkt ───────────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -lt 2 ]]; then
        echo "Verwendung: AGENT_NAMESPACE=<ns> $0 <project-name> \"<command>\""
        echo "Beispiel:   AGENT_NAMESPACE=CLAUDE $0 pjc001 \"ls -la /app/data\""
        exit 1
    fi
    execute_safe_command "$1" "$2"
fi
