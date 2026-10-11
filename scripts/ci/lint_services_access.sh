#!/usr/bin/env bash
# scripts/ci/lint_services_access.sh
#
# II-01 Regression Guard — Services.xyz Schichten-Lint
#
# Zweck:
#   Der globale `Services`-Autoload-Singleton wurde vollständig entfernt (AUDIT-03,
#   siehe "Services-Autoload" Zeile in AUDIT-03-meta-review.md) — DI läuft heute über
#   ServiceDeps (ADR-011) für Services, IUIContext (ADR-012) für UI und IEntityContext
#   (ADR-006) für Entities. Dieses Skript findet aktuell erwartungsgemäß nichts; es
#   bleibt als Regression-Guard bestehen, damit niemand versehentlich einen neuen
#   globalen Service-Locator-Zugriff in UI-Controllern oder Entity-Code einführt.
#   Diese Schichten müssen IUIContext bzw. IEntityContext nutzen — nicht einen
#   globalen Container.
#
#   Erlaubte Ausnahmen (ALLOWLIST):
#     - Kommentare (Zeilen die mit # beginnen, nach Leerzeichen normalisiert)
#     - Docstrings (## ...)
#     - Services.gd selbst (Container-Definition)
#     - BootPipeline.gd / ServiceOrchestrator.gd (Container-Befüllung, kein Auflösen)
#     - Main.gd (einmaliger Post-Boot-Existenzcheck — dokumentiert in AUDIT-03)
#     - SimpleTerminal.gd (Debug-Tool, bewusst außerhalb des DI-Graphen)
#     - IntegrationTest.gd (Testinfrastruktur, inspiziert Container von außen)
#
# Scoped Directories (werden auf direkte Service-Calls geprüft):
#   scripts/ui/             (Controller, Visuals, Builder)
#   scripts/player/         (Player.gd, TouchInput.gd)
#   scripts/world/combat/   (EnemyNPC, EnemyAI, ...)
#   scripts/world/objects/  (OakTree, IronOre, ...)
#   scripts/interaction/    (InteractableComponent, ...)
#
# CI-Aufruf:
#   bash scripts/ci/lint_services_access.sh
#
# Lokal:
#   cd wildgrove_bugfix && bash scripts/ci/lint_services_access.sh
#
# Exit 0 = OK, Exit 1 = Verletzung gefunden

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ─────────────────────────────────────────────────────────────────────────────
# Scoped directories — diese Schichten dürfen Services.xyz NICHT direkt aufrufen
# ─────────────────────────────────────────────────────────────────────────────
SCOPED_DIRS=(
    "scripts/ui"
    "scripts/entities/player"
    "scripts/entities/combat"
    "scripts/world/objects"
    "scripts/interaction"
    "scripts/economy/inventory/ui"
    "scripts/economy/equipment/ui"
    "scripts/progression/quests/ui"
    "scripts/progression/skills/ui"
)
# HINWEIS (Migration Domain-first): vorher lag alle UI zentral unter scripts/ui/*,
# jetzt liegt domain-eigene UI unter <domain>/ui/. Jeder neue <domain>/ui/-Ordner
# MUSS hier ergänzt werden, sonst verliert der Guard Abdeckung.

# ─────────────────────────────────────────────────────────────────────────────
# Erlaubte Dateien innerhalb der Scoped Dirs (vollständiger relativer Pfad)
# Diese Dateien haben einen bewusst dokumentierten Services-Zugriff.
# ─────────────────────────────────────────────────────────────────────────────
ALLOWLIST_FILES=(
    # Keine aktuellen Ausnahmen — alle Schichtverletzungen sind behoben.
    # Neue Ausnahmen hier eintragen, mit Begründungs-Kommentar im Code.
)

ERRORS=0

echo "======================================================"
echo "  Services-Access Lint — Schichtentrennung (II-01)    "
echo "======================================================"
echo ""

# ─────────────────────────────────────────────────────────────────────────────
# Hilfsfunktion: Prüft ob eine Zeile ein Live-Call ist
# (kein Kommentar, kein Docstring, kein leerer String)
# ─────────────────────────────────────────────────────────────────────────────
is_live_call() {
    local line="$1"
    # Trim leading whitespace
    local trimmed
    trimmed="$(echo "$line" | sed 's/^[[:space:]]*//')"
    # Kommentar-Zeilen ausschließen
    if [[ "$trimmed" == \#* ]]; then
        return 1   # ist Kommentar → kein live call
    fi
    # Inline-Kommentar: Services-Ref erscheint nach # auf derselben Zeile → überspringen
    # Konservativ: wenn "Services." nur nach einem # vorkommt, ist es ein Kommentar
    local before_comment
    before_comment="$(echo "$line" | sed 's/#.*//')"
    if ! echo "$before_comment" | grep -q "Services\."; then
        return 1   # Services. taucht nur im Kommentar-Teil auf
    fi
    return 0   # ist ein Live-Call
}

for dir in "${SCOPED_DIRS[@]}"; do
    full_dir="$PROJECT_ROOT/$dir"
    if [[ ! -d "$full_dir" ]]; then
        continue
    fi

    # Alle .gd-Dateien in diesem Directory (rekursiv)
    while IFS= read -r -d '' filepath; do
        relative="${filepath#$PROJECT_ROOT/}"

        # Allowlist-Check
        IS_ALLOWED=false
        for af in "${ALLOWLIST_FILES[@]}"; do
            if [[ "$relative" == "$af" ]]; then
                IS_ALLOWED=true
                break
            fi
        done
        if $IS_ALLOWED; then
            echo "OK (allowlist)  $relative"
            continue
        fi

        # Suche nach "Services." im Code (nur Live-Calls, keine Kommentare)
        VIOLATIONS=()
        while IFS= read -r match_line; do
            # match_line format: "LINENUM:CONTENT"
            linenum="${match_line%%:*}"
            content="${match_line#*:}"
            if is_live_call "$content"; then
                VIOLATIONS+=("  Zeile $linenum: $content")
            fi
        done < <(grep -n "Services\." "$filepath" 2>/dev/null || true)

        if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
            echo "FAIL: $relative"
            for v in "${VIOLATIONS[@]}"; do
                echo "$v"
            done
            echo "  --> Nutze IUIContext (UI) oder IEntityContext (Entities) statt Services.xyz"
            echo "  --> Dokumentiert in ADR-006, ADR-011, ADR-012, CONTRIBUTING.md §7.8"
            echo ""
            ERRORS=$((ERRORS + 1))
        fi

    done < <(find "$full_dir" -name "*.gd" -print0 | sort -z)
done

echo ""

if [[ $ERRORS -gt 0 ]]; then
    echo "FAIL: $ERRORS Datei(en) mit direktem Services.xyz-Zugriff in geschützten Schichten."
    echo ""
    echo "Erlaubte Alternativen:"
    echo "  UI-Layer:      _ctx.get_inventory(), _ctx.bus().ui()... (IUIContext)"
    echo "  Entity-Layer:  _ctx.get_combat_system(), _ctx.get_data()... (IEntityContext)"
    echo ""
    echo "Ausnahmen → ALLOWLIST_FILES in diesem Script eintragen + Begründung im Code."
    exit 1
fi

echo "OK  Keine direkten Services.xyz-Calls in UI/Entity-Schichten gefunden."
exit 0
