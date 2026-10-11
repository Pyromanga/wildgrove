#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# wildgrove-ci.sh — CLI-Wrapper für die WildGrove-GitHub-Workflows.
#
# Voraussetzung: GitHub CLI (`gh`) installiert und authentifiziert
# (`gh auth login`), Schreibrechte auf Pyromanga/wildgrove.
#
# Sub-Kommandos:
#   build            — APK-Build + Tests triggern (workflow_dispatch auf
#                      build-apk.yml; gleiche Pipeline wie "App"-Commits)
#   restore          — zip/game.zip ins Repo mergen (restore-from-zip.yml;
#                      vorsichtig: ergänzt/überschreibt, löscht nichts)
#   sync             — Repo-Stand in zip/game.zip packen (sync-to-zip.yml;
#                      Gegenstück zum Claude-Chat-Workflow)
#   status [n]       — letzte n Workflow-Runs anzeigen (Default 10)
#   logs <run-id>    — Logs eines Runs lokal herunterladen und öffnen
#   open             — Actions-Tab im Browser öffnen
#   help             — diese Hilfe
#
# Beispiele:
#   ./scripts/ci/wildgrove-ci.sh build
#   ./scripts/ci/wildgrove-ci.sh status 5
#   ./scripts/ci/wildgrove-ci.sh logs 38157688136
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO="Pyromanga/wildgrove"
CMD="${1:-help}"

require_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    echo "❌ GitHub CLI (gh) nicht gefunden — https://cli.github.com/ installieren und 'gh auth login' ausführen."
    exit 1
  fi
}

case "$CMD" in
  build)
    require_gh
    echo "🔨 Triggere APK-Build + Tests (build-apk.yml) ..."
    gh workflow run build-apk.yml --repo "$REPO" --ref main
    echo "✅ Getriggert. Status: ./scripts/ci/wildgrove-ci.sh status"
    ;;
  restore)
    require_gh
    echo "📥 Triggere Restore (zip/game.zip → Repo-Root, merge-only, kein Löschen) ..."
    gh workflow run restore-from-zip.yml --repo "$REPO" --ref main
    echo "✅ Getriggert. Der Bot committet nach Fertiglauf selbst."
    ;;
  sync)
    require_gh
    echo "📦 Triggere Sync (Repo-Stand → zip/game.zip) ..."
    gh workflow run sync-to-zip.yml --repo "$REPO" --ref main
    echo "✅ Getriggert. Danach arbeitet Claude Chat mit dem aktuellen Stand."
    ;;
  status)
    require_gh
    N="${2:-10}"
    echo "📊 Letzte $N Workflow-Runs:"
    gh run list --repo "$REPO" --limit "$N"
    ;;
  logs)
    require_gh
    RUN_ID="${2:?Usage: wildgrove-ci.sh logs <run-id>}"
    echo "📄 Lade Logs für Run $RUN_ID ..."
    gh run view "$RUN_ID" --repo "$REPO" --log-failed 2>/dev/null || gh run view "$RUN_ID" --repo "$REPO" --log
    ;;
  open)
    gh browse --repo "$REPO" actions
    ;;
  help|*)
    sed -n '2,32p' "$0" | sed 's/^# \?//'
    ;;
esac
