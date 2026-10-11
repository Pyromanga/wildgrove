#!/usr/bin/env bash
# scripts/ci/lint_servicenode.sh
#
# ADR-003 Enforcement — ServiceNode vs Service Lint
#
# Zweck:
#   Stellt sicher, dass kein Service "extends ServiceNode" nutzt
#   wenn er keinen SceneTree-Zugriff braucht. Jedes neue "extends ServiceNode"
#   muss entweder:
#     (a) in JUSTIFIED_FILES gelistet sein (mit Kommentar im Code),
#     oder
#     (b) einen "# justified: <grund>"-Kommentar in den ersten 15 Zeilen haben.
#
# CI-Aufruf (in build-apk.yml test-logic Job nach GUT-Tests):
#   bash scripts/ci/lint_servicenode.sh
#
# Lokal:
#   cd wildgrove_prio3 && bash scripts/ci/lint_servicenode.sh
#
# Exit 0 = OK, Exit 1 = Verletzung gefunden

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Bekannte, geprüfte ServiceNode-Services (ADR-003 Tabelle)
# Jeder Eintrag hat einen "# justified:"-Kommentar in den ersten 15 Zeilen.
# Neue Einträge hier MÜSSEN im ADR-003-Update begründet werden.
# ─────────────────────────────────────────────────────────────────────────────
JUSTIFIED_FILES=(
    "scripts/platform/GameManager.gd"
    "scripts/interaction/InteractionExecutor.gd"
    "scripts/entities/combat/CombatSystem.gd"
    "scripts/networking/NetworkBridge.gd"
    "scripts/session/SceneManager.gd"
    "scripts/session/SessionManager.gd"
    "scripts/platform/ServiceTicker.gd"
    "scripts/world/respawn/RespawnService.gd"
    "scripts/world/core/WorldGenerationService.gd"
    "scripts/world/core/WorldService.gd"
)

ERRORS=0
WARNINGS=0

echo "======================================================"
echo "  ADR-003 Lint -- ServiceNode vs Service              "
echo "======================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Alle Dateien mit "extends ServiceNode" suchen
# ─────────────────────────────────────────────────────────────────────────────
mapfile -t FOUND < <(grep -rl "extends ServiceNode" "$PROJECT_ROOT/scripts" \
    | grep "\.gd$" \
    | grep -v "addons/" \
    | sort)

if [[ ${#FOUND[@]} -eq 0 ]]; then
    echo "OK  Keine extends ServiceNode-Vorkommen gefunden."
    exit 0
fi

for filepath in "${FOUND[@]}"; do
    relative="${filepath#$PROJECT_ROOT/}"

    # Nur echte extends-Deklarationen prüfen (Zeile 1-3), nicht Docstring-Vorkommen
    if ! head -3 "$filepath" | grep -q "^extends ServiceNode"; then
        continue
    fi

    # Prüfen ob in JUSTIFIED_FILES
    IS_JUSTIFIED=false
    for jf in "${JUSTIFIED_FILES[@]}"; do
        if [[ "$relative" == "$jf" ]]; then
            IS_JUSTIFIED=true
            break
        fi
    done

    if $IS_JUSTIFIED; then
        # justified: Kommentar in ersten 15 Zeilen vorhanden?
        if head -15 "$filepath" | grep -q "# justified:"; then
            echo "OK (justified)  $relative"
        else
            echo "WARN: $relative ist in JUSTIFIED_FILES aber fehlt '# justified:' Kommentar"
            echo "   --> Ersten 15 Zeilen: fuege '# justified: <SceneTree-Nutzung>' hinzu"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        echo "FAIL: $relative"
        echo "   'extends ServiceNode' ohne ADR-003-Eintrag oder '# justified:' Kommentar."
        echo "   Optionen:"
        echo "     (a) Auf 'extends Service' migrieren (wenn kein SceneTree noetig)"
        echo "     (b) '# justified: <SceneTree-Nutzung>' in Zeile 2-3 hinzufuegen"
        echo "         UND Datei in JUSTIFIED_FILES in diesem Script eintragen"
        echo "         UND ADR-003 Backlog-Tabelle aktualisieren"
        ERRORS=$((ERRORS + 1))
    fi
done

echo ""

TOTAL=${#FOUND[@]}
echo "Geprueft: $TOTAL extends ServiceNode-Deklarationen"

if [[ $WARNINGS -gt 0 ]]; then
    echo "WARN: $WARNINGS Warnungen (fehlende justified-Kommentare)"
fi

if [[ $ERRORS -gt 0 ]]; then
    echo ""
    echo "FAIL: $ERRORS ADR-003-Verletzung(en) gefunden."
    echo "   Lies docs/adr/003-servicenode-vs-service.md fuer den Entscheidungsbaum."
    exit 1
fi

echo "OK  Alle extends ServiceNode-Deklarationen sind ADR-003-konform."
exit 0
