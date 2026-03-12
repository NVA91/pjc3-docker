#!/usr/bin/env python3
"""
mcp_docker_agent.py — FastMCP Agenten-Verwalter für pjc3-docker Stack.
Stellt Claude Tools zur Stack-Verwaltung bereit.
"""
import sys
import subprocess
import json
import re
import secrets as secrets_module
from pathlib import Path
from dotenv import load_dotenv
from fastmcp import FastMCP

load_dotenv()

PROJECT_DIR = Path(__file__).parent.resolve()
AGENT_NAMESPACE = "CLAUDE"
AGENT_UID = "1001"
AGENT_GID = "1001"

mcp = FastMCP("docker-stack-manager")


def _run_make(target: str, extra_env: dict | None = None) -> str:
    """Führt ein Makefile-Target sicher aus (keine shell=True)."""
    env = {
        "AGENT_NAMESPACE": AGENT_NAMESPACE,
        "AGENT_UID": AGENT_UID,
        "AGENT_GID": AGENT_GID,
        "PATH": "/usr/bin:/bin:/usr/local/bin",
    }
    if extra_env:
        env.update(extra_env)
    result = subprocess.run(
        ["make", target],
        cwd=str(PROJECT_DIR),
        capture_output=True,
        text=True,
        timeout=30,
        env=env,
    )
    output = result.stdout + result.stderr
    return output.strip() or "(kein Output)"


@mcp.tool()
def stack_status() -> str:
    """Gibt den aktuellen Status aller Container im pjc3-docker Stack zurück."""
    return _run_make("ps")


@mcp.tool()
def stack_start(profile: str = "core") -> str:
    """
    Startet den Docker-Stack.

    Args:
        profile: 'core' für Caddy+Vaultwarden+Pi-hole, 'monitor' für + Prometheus/Grafana/Loki
    """
    if profile not in ("core", "monitor"):
        return "Fehler: profile muss 'core' oder 'monitor' sein."
    target = "up" if profile == "core" else "up-monitor"
    return _run_make(target)


@mcp.tool()
def stack_logs(service: str = "", lines: int = 50) -> str:
    """
    Gibt Container-Logs zurück.

    Args:
        service: Service-Name (leer = alle Services)
        lines: Anzahl der letzten Log-Zeilen (max 200)
    """
    lines = min(lines, 200)
    cmd = [
        "docker", "compose",
        "-p", f"{AGENT_NAMESPACE}-pjc3docker",
        "logs", f"--tail={lines}",
    ]
    if service:
        allowed = {"caddy", "vaultwarden", "pihole", "prometheus", "grafana", "loki", "node-exporter"}
        if service not in allowed:
            return f"Fehler: unbekannter Service '{service}'. Erlaubt: {allowed}"
        cmd.append(service)
    result = subprocess.run(
        cmd, cwd=str(PROJECT_DIR), capture_output=True, text=True, timeout=15,
    )
    return (result.stdout + result.stderr).strip() or "(keine Logs)"


@mcp.tool()
def stack_info() -> str:
    """Gibt Informationen über die Stack-Konfiguration zurück."""
    return f"""pjc3-docker Stack-Info:
Projektverzeichnis: {PROJECT_DIR}
AGENT_NAMESPACE: {AGENT_NAMESPACE}
Compose-Projekt: {AGENT_NAMESPACE}-pjc3docker
Core-Services: caddy, vaultwarden, pihole
Monitor-Services: prometheus, grafana, loki (opt-in)
Erweiterter Monitor: node-exporter (profile: extended)

MCP-Tools:
  stack_status()             → Container-Status
  stack_start('core')        → Core Stack starten
  stack_start('monitor')     → Core + Monitoring starten
  stack_logs('grafana', 100) → Grafana Logs
  system_wizard()            → Systemreport (Ports, Container, Secrets, Routes)
  create_secret('name')      → Sicheres Zufalls-Passwort in ./secrets/ schreiben
"""


@mcp.tool()
def system_wizard() -> str:
    """
    Maschinenlesbarer Systemreport (JSON) für den Agenten.

    Liefert:
    - used_ports: Alle belegten TCP/UDP-Ports auf dem Host
    - containers: Laufende pjc3docker-Container mit State
    - secrets_present: Dateinamen in ./secrets/ (kein Inhalt!)
    - caddy_routes: Im Caddyfile vergebene Domains/Subdomains
    - warnings: Fehlende Konfiguration oder Probleme
    """
    report: dict = {
        "used_ports": [],
        "containers": [],
        "secrets_present": [],
        "caddy_routes": [],
        "warnings": [],
    }

    # 1. Belegte Ports (TCP + UDP)
    for flag in ("-tlnp", "-ulnp"):
        result = subprocess.run(
            ["ss", flag],
            capture_output=True, text=True, timeout=10,
        )
        for line in result.stdout.splitlines()[1:]:
            parts = line.split()
            if len(parts) < 5:
                continue
            addr = parts[4]
            port_str = addr.rsplit(":", 1)[-1]
            if port_str.isdigit():
                port = int(port_str)
                if port not in report["used_ports"]:
                    report["used_ports"].append(port)
    report["used_ports"].sort()

    # 2. Laufende Container im pjc3docker-Stack
    result = subprocess.run(
        ["docker", "compose", "-p", f"{AGENT_NAMESPACE}-pjc3docker", "ps", "--format", "json"],
        cwd=str(PROJECT_DIR),
        capture_output=True, text=True, timeout=15,
    )
    for line in result.stdout.splitlines():
        try:
            c = json.loads(line)
            report["containers"].append({
                "name":    c.get("Name", ""),
                "service": c.get("Service", ""),
                "state":   c.get("State", ""),
                "status":  c.get("Status", ""),
            })
        except (json.JSONDecodeError, KeyError):
            pass

    # 3. Secrets-Verzeichnis (nur Dateinamen, nie Inhalt lesen)
    secrets_dir = PROJECT_DIR / "secrets"
    if secrets_dir.exists():
        report["secrets_present"] = sorted(
            f.name for f in secrets_dir.iterdir()
            if f.is_file() and f.name != ".gitkeep"
        )
    else:
        report["warnings"].append("secrets/-Verzeichnis fehlt — bitte anlegen")

    # 4. Caddyfile-Routen (vergebene Domains)
    caddyfile = PROJECT_DIR / "Caddyfile"
    if caddyfile.exists():
        content = caddyfile.read_text(encoding="utf-8")
        raw_matches = re.findall(
            r"^([\w\.\*\-]+|\*\.\{[^\}]+\}|\{[^\}]+\})\s*\{",
            content,
            re.MULTILINE,
        )
        _caddy_keywords = {
            "handle", "tls", "header", "route", "encode", "respond",
            "basicauth", "file_server", "redir", "rewrite", "log",
        }
        report["caddy_routes"] = [
            r for r in raw_matches if r.lower() not in _caddy_keywords
        ]
    else:
        report["warnings"].append("Caddyfile nicht gefunden")

    return json.dumps(report, indent=2, ensure_ascii=False)


@mcp.tool()
def create_secret(name: str) -> str:
    """
    Erzeugt ein kryptografisch sicheres Zufalls-Passwort und
    schreibt es als Secret-Datei in ./secrets/<name>.

    Args:
        name: Dateiname (nur a-z, A-Z, 0-9, _, - erlaubt; max 64 Zeichen)

    Returns:
        JSON mit {"created": "<name>", "path": "..."} — NIEMALS den Wert selbst.
    """
    if not re.fullmatch(r"[a-zA-Z0-9_\-]{1,64}", name):
        return json.dumps({
            "error": f"Ungültiger Name '{name}'. Erlaubt: a-z, A-Z, 0-9, _ und - (max 64 Zeichen)."
        })

    secrets_dir = PROJECT_DIR / "secrets"
    secrets_dir.mkdir(exist_ok=True)
    target = secrets_dir / name

    if target.exists():
        return json.dumps({
            "error": f"Secret '{name}' existiert bereits. Manuell löschen zum Ersetzen."
        })

    password = secrets_module.token_urlsafe(32)
    target.write_text(password, encoding="utf-8")

    return json.dumps({
        "created": name,
        "path": f"./secrets/{name}",
        "note": "Passwort gesetzt. Inhalt NICHT geloggt. Mit system_wizard() verifizieren."
    })


if __name__ == "__main__":
    mcp.run()
