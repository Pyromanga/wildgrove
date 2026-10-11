# Makefile — deterministischer Einstiegspunkt für das Projekt.
#
# Ziel (docs/manager/MANAGER.md §8): irgendwann läuft jede Änderung über
# ein Target hier. Aktuell (Round 110) sind das die Targets, die es schon
# gibt — Godot-Build/-Test-Targets sind Platzhalter, weil diese Sandbox
# kein Godot-Binary und kein Netzwerk hat (siehe `make godot-check`).
#
# Neue Session? Erst: make brief

.PHONY: help brief stats graph overview eventbus-check rawstrings-check emit-wrapper-check \
        signal-categorize signal-migration-status todo decide metric godot-check test-gd build reindex \
        health-contract-check pet-range-check terrain-material-check world-persistence-check

help:
	@echo "Verfügbare Targets:"
	@echo "  make brief             - Manager-Kurzbrief (IMMER zuerst in neuer Session)"
	@echo "  make stats             - Metrik-Auswertung (metrik-master)"
	@echo "  make graph             - service_graph.py (statische Architektur-Analyse)"
	@echo "  make overview          - architecture_overview.py (Services/Entities/EventBus/ADRs im Überblick, statt einzeln nachzulesen)"
	@echo "  make overview-full     - wie 'overview', zusätzlich EventBus-Namespaces + ADRs, und als Report gespeichert"
	@echo "  make method-coverage   - method_reference_coverage.py (statische Methoden-Referenz-Näherung mit Call-Graph, KEINE echte Line-Coverage — siehe Skript-Kopf)"
	@echo "                           nutzt echten GDScript-AST wenn 'pip install -r scripts/agent/requirements.txt' gelaufen ist, sonst Regex-Fallback"
	@echo "  make eventbus-check    - service_build.py eventbus-direct (Dry-Run)"
	@echo "  make rawstrings-check  - service_build.py raw-strings (Dry-Run)"
	@echo "  make signal-categorize - analyze_native_signals.py (TODO Punkt 5, Report unter docs/manager/reports/)"
	@echo "  make signal-migration-status - service_graph.py --native-signals (ADR-050 Phase 4, Regressionsschutz)"
	@echo "  make todo              - TODO-offene-probleme.md via todo_tool.py anzeigen"
	@echo "  make adr-list          - Alle ADRs mit live berechnetem Status (adr_tool.py)"
	@echo "  make adr-audit         - ADR-Audit, geloggt als Metrik (code-tester)"
	@echo "  make reindex           - Decision-Index neu generieren"
	@echo "  make health-contract-check - HealthComponent.max_health-Kontrakt: Struktur-Check + Godot-freier Verhaltens-Selbsttest"
	@echo "  make pet-range-check   - Pet-Reichweiten-Fix (actor_uuid): Struktur-Check + Godot-freier Verhaltens-Selbsttest"
	@echo "  make terrain-material-check - Bodenmaterial-System (Sand/Kies/Erde): Struktur-Check + Godot-freier Verhaltens-Selbsttest"
	@echo "  make world-persistence-check - world_seed-JSON-Fix + Farm-Plot-Persistenz: Struktur-Check + Godot-freier Verhaltens-Selbsttest"
	@echo "  make godot-check       - prüfen ob ein Godot-Binary verfügbar ist"
	@echo "  make test-gd           - GDScript-Tests (siehe roles/code-tester.md: Runner fehlt aktuell)"
	@echo ""
	@echo "  make decide TITLE=... CHOSEN=... RATIONALE=...   - Decision loggen (siehe MANAGER.md §4)"
	@echo "  make metric AGENT=... TASK=... DURATION=... SUCCESS=1  - Metrik loggen (siehe MANAGER.md §5)"

brief:
	@python3 scripts/agent/manager/session_brief.py

stats:
	@python3 scripts/agent/manager/session_brief.py --stats

graph:
	@python3 scripts/agent/service_graph.py

overview:
	@python3 scripts/agent/architecture_overview.py

overview-full:
	@python3 scripts/agent/architecture_overview.py --full --write-report

method-coverage:
	@python3 scripts/agent/method_reference_coverage.py

eventbus-check:
	@python3 scripts/agent/service_build.py eventbus-direct

rawstrings-check:
	@python3 scripts/agent/service_build.py raw-strings

emit-wrapper-check:
	@python3 scripts/agent/service_build.py emit-wrapper-names

signal-categorize:
	@python3 scripts/agent/analyze_native_signals.py --pretty --write-report

signal-migration-status:
	@python3 scripts/agent/service_graph.py --native-signals --pretty

todo:
	@python3 scripts/agent/todo_tool.py list

adr-list:
	@python3 scripts/agent/adr_tool.py list

adr-audit:
	@python3 scripts/agent/adr_tool.py audit --log-metric

reindex:
	@python3 scripts/agent/manager/log_decision.py --reindex-only

# --- Beispiel-Aufruf, echte Werte per Variablen übergeben:
#   make decide TITLE="Foo" CHOSEN="Bar" RATIONALE="Baz" ALT="Option A"
decide:
	@python3 scripts/agent/manager/log_decision.py \
		--title "$(TITLE)" --chosen "$(CHOSEN)" --rationale "$(RATIONALE)" \
		$(if $(ALT),--alt "$(ALT)",) $(if $(ROLE),--role "$(ROLE)",)

metric:
	@python3 scripts/agent/manager/log_metric.py \
		--agent "$(AGENT)" --task "$(TASK)" --duration "$(DURATION)" \
		$(if $(SUCCESS),--success,--fail) $(if $(NOTES),--notes "$(NOTES)",)

health-contract-check:
	@python3 scripts/agent/health_contract_check.py

pet-range-check:
	@python3 scripts/agent/pet_range_check.py

terrain-material-check:
	@python3 scripts/agent/terrain_material_check.py

world-persistence-check:
	@python3 scripts/agent/world_persistence_check.py

# --- Godot-Targets: Platzhalter, siehe docs/manager/ROADMAP.md Phase 3.
# Diese Sandbox hat kein Godot-Binary/Netzwerk. Lokal: GODOT_BIN setzen.
GODOT_BIN ?= godot4

godot-check:
	@command -v $(GODOT_BIN) >/dev/null 2>&1 && echo "✓ $(GODOT_BIN) gefunden" || \
		echo "✗ $(GODOT_BIN) nicht gefunden — Godot-Targets laufen hier nicht (siehe ROADMAP.md Phase 3)"

test-gd: godot-check
	@echo "Kein Test-Runner-Addon installiert (kein GUT/gdUnit4) — siehe"
	@echo "docs/manager/roles/code-tester.md und Decision 0005."
	@echo "tests/unit/*.gd und tests/integration/*.gd existieren als Spezifikation,"
	@echo "sind aber nicht automatisiert ausführbar. Bis Phase 3: manuell in Godot-Editor laufen lassen."

build:
	@echo "Kein Godot-Export-Preset-Build-Target definiert — export_presets.cfg existiert,"
	@echo "aber kein automatisierter Aufruf. Kandidat für den nächsten code-builder-Durchgang."
