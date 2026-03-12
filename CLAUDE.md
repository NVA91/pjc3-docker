# CLAUDE.md — Projekt pjc3-docker

## Zweck
Home-Infrastruktur Stack: Caddy (Reverse Proxy), Prometheus/Grafana (Monitoring),
Loki (Logs), Vaultwarden (Passwörter), Pi-hole (DNS + Ad-Blocking) — Proxmox-ready, MCP-verbunden.

## Verzeichnis
/home/ubhp-nova/claude-c/pjc3-docker/   ← gleiches Level wie pjc3

## Umgebung
- `python3` direkt (kein venv erforderlich — FastMCP systemweit installiert)
- Docker + Docker Compose v2 (`docker compose` ohne Bindestrich)
- API-Key: ANTHROPIC_API_KEY in `.env`

## Sicherheitsregeln (STRIKT)
- Kein absoluter Host-Pfad als Volume-Source (außer explizit dokumentierte Ausnahmen)
- Kein /var/run/docker.sock-Mount — NIEMALS
- Alle Bind-Mounts mit propagation: rprivate
- config/ und secrets/ immer read_only: true
- user: "${AGENT_UID}:${AGENT_GID}" — niemals root
- Namespace-Prefix: AGENT_NAMESPACE=CLAUDE, CLAUDE-pjc3docker-vol-*

## Dokumentierte Sicherheits-Ausnahmen
- Pi-hole: kein `user:` gesetzt (dnsmasq-Daemon benötigt intern root) — kompensiert durch no-new-privileges + kein docker.sock-Mount
- Pi-hole: Port 53 auf LAN_IP gebunden (DNS muss lokal erreichbar sein)
- node-exporter: /proc + /sys Mounts (profiles: [extended], opt-in)

## Befehle
```bash
# Stack starten:
AGENT_NAMESPACE=CLAUDE make up

# Mit Monitoring:
AGENT_NAMESPACE=CLAUDE make up-monitor

# MCP-Agenten-Verwalter starten:
python3 mcp_docker_agent.py

# Status:
AGENT_NAMESPACE=CLAUDE make ps
```

## Host-Setup (einmalig — als root auf dem Docker-Host)

1. systemd-resolved deaktivieren (Port 53 freigeben für Pi-hole):
   ```bash
   sudo systemctl disable --now systemd-resolved
   sudo rm /etc/resolv.conf
   echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" | sudo tee /etc/resolv.conf
   ```

2. Cloudflare API-Token in .env:
   ```
   CLOUDFLARE_API_TOKEN=...   (Edit zone DNS Berechtigung)
   HOME_DOMAIN=home.example.com
   LAN_IP=192.168.178.100     (IP des Docker-Hosts im LAN)
   ```

3. Cloudflare Dashboard → My Profile → API Tokens → Create Token
   → Template: "Edit zone DNS" → Zone: deine Domain

## Agent-Workflow: Neuen Service hinzufügen

1. `system_wizard()` aufrufen → Port-Check, Secret-Check, Route-Check
2. Falls Secret fehlt: `create_secret("mein_secret_name")` aufrufen
3. `system_wizard()` wiederholen → Verifikation
4. `docker-compose.override.example.yml` als Vorlage: Service-Block in
   `docker-compose.override.yml` einfügen
5. Subdomain in `Caddyfile` hinzufügen (Agent zeigt Snippet)
6. `stack_start('core')` → Stack neu starten
7. `stack_status()` → Läuft der neue Container?
