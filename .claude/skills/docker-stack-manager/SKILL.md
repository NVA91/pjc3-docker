---
name: docker-stack-manager
description: >
  This skill should be used when the user asks to "start the stack", "stop the stack",
  "check container status", "add a new service", "get logs", "check security rules",
  "run system_wizard", "create a secret", or works on the pjc3-docker
  home infrastructure (Caddy, Vaultwarden, Pi-hole, Prometheus, Grafana, Loki).
version: "1.1"
---

# Docker Stack Manager Skill

## Stack-Übersicht

Projekt: `/home/ubhp-nova/claude-c/pjc3-docker`
Namespace: `CLAUDE` (UID 1001:1001)
Compose-Projekt: `CLAUDE-pjc3docker`
GitHub: `git@github.com:NVA91/pjc3-docker.git`

| Service        | Image                       | Profil    | URL                         |
|----------------|-----------------------------|-----------|-----------------------------|
| caddy          | caddy-cloudflare:local      | core      | Reverse Proxy (wildcard SSL)|
| vaultwarden    | vaultwarden/server:latest   | core      | https://vault.HOME_DOMAIN   |
| pihole         | pihole/pihole:latest        | core      | https://pihole.HOME_DOMAIN  |
| prometheus     | prom/prometheus:latest      | monitor   | (intern)                    |
| grafana        | grafana/grafana:latest      | monitor   | https://grafana.HOME_DOMAIN |
| loki           | grafana/loki:3.1.1          | monitor   | (intern)                    |
| node-exporter  | prom/node-exporter:latest   | extended  | (intern, opt-in)            |

## MCP-Tools

| Tool | Beschreibung |
|------|-------------|
| `stack_status()` | Container-Status |
| `stack_start('core')` | Core starten |
| `stack_start('monitor')` | Core + Monitoring starten |
| `stack_logs('service', lines)` | Logs abrufen |
| `stack_info()` | Konfigurationsinfo |
| `system_wizard()` | Systemreport: Ports, Container, Secrets, Caddy-Routes |
| `create_secret('name')` | Sicheres Passwort in ./secrets/ schreiben |

## Ohne MCP: Makefile-Befehle

```bash
AGENT_NAMESPACE=CLAUDE make up          # Core starten
AGENT_NAMESPACE=CLAUDE make up-monitor  # + Monitoring
AGENT_NAMESPACE=CLAUDE make ps          # Status
AGENT_NAMESPACE=CLAUDE make logs        # Logs
AGENT_NAMESPACE=CLAUDE make down        # Stoppen (fragt)
```

## Sicherheitsregeln

1. Keine absoluten Pfade als Volume-Source
2. Kein /var/run/docker.sock-Mount — NIEMALS
3. `propagation: rprivate` bei allen Bind-Mounts
4. `read_only: true` für config/ und secrets/
5. `user: "${AGENT_UID}:${AGENT_GID}"` — niemals root
6. Volume-Namen: `${AGENT_NAMESPACE}-pjc3docker-vol-<zweck>`
7. Ausnahmen dokumentiert: Pi-hole (root, Port 53), node-exporter (/proc, /sys)

## Agent-Workflow: Neuen Service hinzufügen

1. `system_wizard()` → Port frei? Secret vorhanden? Route frei?
2. Falls Secret fehlt: `create_secret("secret_name")`
3. `system_wizard()` erneut → Verifikation
4. Service in `docker-compose.override.yml` einfügen (Vorlage: override.example.yml)
5. Subdomain in Caddyfile ergänzen
6. `stack_start('core')` → neu starten
7. `stack_status()` → Container läuft?
