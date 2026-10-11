# scripts/ci/ — CI-Tooling & lokale Development-Skripte

Nachhaltigkeitsprinzip: **Pipeline-Logik lebt in Scripts, nicht im Workflow-YAML.**
Workflows (.github/workflows/) sind nur noch dünne Trigger-Shell — die eigentliche
Logik ist hier, läuft identisch in CI und lokal reproduzierbar, und ist ohne
GitHub-Kontext testbar.

## Übersicht

| Script | Zweck | genutzt von |
|---|---|---|
| `resolve_source.py` | Projektquelle auflösen (Repo-Root vs. zip/game.zip je nach Trigger-Commit) | `build-apk.yml` (resolve-source Job) |
| `bump_version.py` | APK versionCode/versionName aus Run-Nummer in export_presets.cfg schreiben | `build-apk.yml` (build-android Job) |
| `wildgrove-ci.sh` | CLI-Wrapper: build/restore/sync/status/logs/open | Mensch & Claude Code (gh CLI) |
| `di_test_overview.py` | DI-Überblick & Testabdeckung (JSON + Markdown) | `build-apk.yml` (di-test-overview Job) |
| `di_query.py` | JSON-Ausgabe von di_test_overview navigieren | lokales Tooling |
| `lint_servicenode.sh` | Lint: ServiceNode-Pattern einhalten | `build-apk.yml` (Optional) |
| `lint_services_access.sh` | Lint: Services-Zugriffsmuster | `build-apk.yml` (Optional) |
| `udp_latency_proxy.py` | UDP-Latenz simulieren (Netzwerk-Tests) | lokal / IT-Szenarien |

## WildGrove-Workflow (Claude-Chat-ZIP-Parallel-Workflow)

Das Projekt nutzt zwei parallele Quellen der Wahrheit:

- **zip/game.zip** — Arbeitskanal für Claude Chat (Free-Version): Der Stand wird
  in der ZIP bearbeitet und als neue game.zip ins Repo gepusht.
- **Repo-Root** — kanonischer Stand, in den ZIP-Inhalte periodig via
  `restore-from-zip.yml` (vorsichtiges Merge, kein Löschen) überführt werden.

`resolve_source.py` koppelt beide Welten an die CI: Baut der Trigger-Commit
das ZIP (Claude-Workflow), wird es entpackt und als Quelle genutzt; sonst baut
die Pipeline gegen das Repo-Root (normale Commits, z.B. nach restore). Ein
versehentliches Testen gegen einen veralteten ZIP-Stand ist dadurch ausgeschlossen
— das war vorher der Fall und hat dazu geführt, dass die Ticker-Fixes zunächst
gegen den alten Stand gebaut wurden (siehe Workflow-Kommentar FIX 2026-10-11).

### Gegenstück-Workflow (Repo → ZIP)

`sync-to-zip.yml` packt den Repo-Stand in zip/game.zip (Trigger: Commit-Marker
`[sync-zip]` oder manuell). Damit arbeitet Claude Chat nach jedem Repo-Fix
automatisch mit dem aktuellen Stand — der Roundtrip zwischen den Agenten
läuft komplett über GitHub, ohne manuellen Download.

## Test-Philosophie in CI (kurz)

- **Unit-Tests** (tests/unit/, GUT): reine Logik, headless, kein Orchard.
- **Integration zwei-Peer** (tests/integration/, ADR-025/026): echte
  ENetMultiplayerPeer-Loopback-Verbindung im selben Prozess.
- **IT-03** (scripts/testing/IT03Harness.gd): zwei GENUINE Godot-Prozesse
  (Host + Client über echten Port), Movement-Round-Trip ohne UI-Klicks.

Details: docs/ci-pipeline.md (dort steht auch: Pipeline-Änderungen erfordern
ein Gespräch mit dem Project-Owner).
