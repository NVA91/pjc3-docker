# pjc3-docker

Home-Infrastruktur Stack: Caddy (wildcard SSL via DNS-01), Pi-hole (DNS + Ad-Blocking),
Vaultwarden, Prometheus, Grafana, Loki. Proxmox-ready. Sicherheitsgehärtet. MCP-verbunden.

## Schnellstart

```bash
# 1. .env vorbereiten
cp .env.example .env
# .env editieren: AGENT_UID, AGENT_GID, HOME_DOMAIN, LAN_IP, CLOUDFLARE_API_TOKEN

# 2. Host-Setup (einmalig, als root)
sudo systemctl disable --now systemd-resolved
sudo rm /etc/resolv.conf && echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf

# 3. Caddy custom build
docker build -f Dockerfile.caddy -t caddy-cloudflare:local .

# 4. Core starten
AGENT_NAMESPACE=CLAUDE make up

# 5. Mit Monitoring
AGENT_NAMESPACE=CLAUDE make up-monitor

# 6. MCP-Agenten-Verwalter
python3 mcp_docker_agent.py
```

## Services

| Service | URL |
|---------|-----|
| Vaultwarden | https://vault.HOME_DOMAIN |
| Pi-hole Admin | https://pihole.HOME_DOMAIN |
| Grafana | https://grafana.HOME_DOMAIN |

## Sicherheit

Alle Volume-Mounts sind read-only/rprivate, non-root. Pi-hole ist dokumentierte
Ausnahme (dnsmasq benötigt root). Details: CLAUDE.md.

## Dokumentation

Siehe `CLAUDE.md` für vollständige Projektregeln und `docs/` für Implementierungspläne.
