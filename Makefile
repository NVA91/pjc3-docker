# Makefile — Namespace-isolierte Docker-Operationen
# Verwendung: AGENT_NAMESPACE=CLAUDE make up

ifndef AGENT_NAMESPACE
$(error AGENT_NAMESPACE ist nicht gesetzt. Aufruf: AGENT_NAMESPACE=CLAUDE make <target>)
endif

AGENT_NS      := $(AGENT_NAMESPACE)
PROJ_ID       := pjc3docker
COMPOSE_PROJ  := $(AGENT_NS)-$(PROJ_ID)
COMPOSE       := docker compose -p $(COMPOSE_PROJ)

.PHONY: up up-monitor down ps logs guard

up:
	@echo "[$(AGENT_NS)/$(PROJ_ID)] Stack starten..."
	$(COMPOSE) up -d
	@echo "[$(AGENT_NS)/$(PROJ_ID)] Laeuft."

up-monitor:
	@echo "[$(AGENT_NS)/$(PROJ_ID)] Core + Monitoring starten..."
	$(COMPOSE) -f docker-compose.yml -f docker-compose.monitor.yml up -d

down:
	@printf "Stack '%s' stoppen? [j/N] " "$(COMPOSE_PROJ)"; \
	read ans; \
	[ "$$ans" = "j" ] && $(COMPOSE) down || echo "Abgebrochen."

ps:
	$(COMPOSE) ps

logs:
	$(COMPOSE) logs --tail=50 --follow

guard:
ifndef CMD
	$(error CMD nicht gesetzt. Aufruf: make guard CMD='cat /app/data/foo.json')
endif
	@bash safe-container-exec.sh $(PROJ_ID) "$(CMD)"
