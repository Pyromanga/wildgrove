# WildGrove — CI/CD Pipeline Reference

**Status: authoritative, settled reference.** This document exists specifically to remove
doubt about whether a CI/CD pipeline exists for this project. It does. The workflow below
was provided directly by the project owner and is reproduced here verbatim, in full, so
nobody — human or agent — needs to ask again.

> **Governance note for any agent (including future instances of Claude) working on this
> repository:** This file documents an existing, owner-provided CI workflow. **Do not modify
> the pipeline's behavior, thresholds, or gating logic without first discussing the change
> with the project owner directly.** If you believe the pipeline needs to change — including
> changes recommended elsewhere in `docs/audit/` — raise it as a proposal, don't silently
> edit `.github/workflows/build-apk.yml`. This applies even if a change seems obviously
> correct (e.g. removing an `|| true`); the owner may have context (cost, noisiness, an
ongoing migration) that isn't visible from the workflow file alone.

---

## What it does, in plain terms

1. **Triggers** on push to `main`/`develop`, on PRs targeting `main`, or manually via
   `workflow_dispatch`. Tests, IT-03, and the DI overview run on every such trigger. Only the
   Android build (`build-android`, and transitively `release`) is additionally gated on the
   commit message or PR title containing the word "App" — see "Änderungen" below for why this
   moved from the whole pipeline to just that job.
2. **Resolves the project source** — either a `zip/game.zip` in the repo (if present and
   containing a `project.godot`) or the repo root itself.
3. **Runs unit tests** via GUT (`addons/gut`, v9.6.0 — see "Änderungen" below for why the
   version matters), after a headless asset-import pass, plus a separate step for the
   integration tests under `tests/integration/`: two-peer network tests (IT-01/IT-02,
   loopback, same process) AND, as of this revision, service-integration tests that drive a
   real (self-booted) PLAYING session via `tests/helpers/SceneLifecycleHarness.gd` — Quest
   rewards (`test_quest_reward_chain.gd`), PvP death-loss/item-protection
   (`test_pvp_death_loss_protections.gd`), and character-switch/save-load round trip
   (`test_session_lifecycle.gd`, the highest-value case: the harness exists specifically to
   make this testable, see "Änderungen"). No new CI wiring needed for these; they run in the
   same step as IT-01/IT-02.
4. **Runs IT-03**, a genuine two-process end-to-end test (`integration-two-process` job):
   two real `godot --headless` processes — one host, one client — connected over a real UDP
   port on `127.0.0.1`, running the actual app boot path (`ServiceOrchestrator`, `EventBus`,
   `WorldService`, `NetworkBridge`, `Player` — no mocks). As of this revision, the connection
   runs through `scripts/ci/udp_latency_proxy.py`, so it exercises artificial latency/jitter/
   packet loss instead of idealized loopback conditions. See "Änderungen" below.
5. **Runs a DI/test-coverage overview** (`di-test-overview` job) via
   `scripts/ci/di_test_overview.py` — static analysis of `config/BootstrapConfig.tres`,
   reporting-only (does not gate the pipeline).
6. **Builds two Android debug APKs** (Host + Guest, distinct `package/unique_name` so both
   can be installed side by side on one device) via Godot's headless export.
7. **Uploads artifacts**: both APKs, full source snapshot, GUT logs, IT-03 logs (host/proxy/
   client).
8. **Creates a GitHub Release** with both APKs attached, but only when the trigger is a `v*`
   tag push.

## Where it lives

The workflow file is checked into this repository at `.github/workflows/build-apk.yml`. It
was originally provided out-of-band by the project owner (see "Änderungen" below for that
history) and has since been committed alongside the rest of the project — if you're reading
this from a project snapshot that predates that commit, check with the project owner for the
current file before assuming it's missing.

## Full workflow source (aktueller Stand)

````yaml
name: Build Android APK

# ─────────────────────────────────────────────────────────────────────────────
# Trigger: Nur bei Push/PR wenn die Commit-Message das Wort "App" enthält.
# workflow_dispatch erlaubt manuellen Start über die GitHub-UI (kein Commit nötig).
# ─────────────────────────────────────────────────────────────────────────────
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]
  workflow_dispatch:

env:
  GODOT_VERSION: "4.6.3"
  EXPORT_NAME: "WildGrove"

# ─────────────────────────────────────────────────────────────────────────────
# Kein globaler Trigger-Gate mehr auf Job-Ebene hier — siehe "build-android"
# weiter unten für die "App"-Wort-Bedingung. FIX: Der Gate saß vorher auf
# resolve-source, wovon ALLE anderen Jobs per `needs:` abhängen — ein Skip
# von resolve-source (kein "App" im Commit/PR-Titel) hat dadurch auch
# test-logic, integration-two-process und di-test-overview übersprungen.
# Unit-Tests/IT-03/DI-Überblick sind aber die güntigen Korrektheits-Checks,
# die bei JEDEM Push/PR laufen sollen — nur der teure Android-Build (NDK,
# SDK, Gradle) soll ans "App"-Schlagwort gebunden bleiben. Siehe
# docs/ci-pipeline.md "Änderungen" für die vorherige Fassung.
# ─────────────────────────────────────────────────────────────────────────────
jobs:

  # ─── Gemeinsame Vorarbeit: Projektquelle auflösen ───────────────────────────
  # Wenn zip/game.zip im Repo existiert und im letzten Commit geändert wurde
  # (oder beim manuellen Trigger vorhanden ist), wird es entpackt und als
  # Projektverzeichnis genutzt. Sonst: normales Repo-Root.
  # Ergebnis wird als Output weitergegeben damit test- und build-Job
  # dasselbe PROJECT_PATH nutzen.
  resolve-source:
    name: Resolve Project Source
    runs-on: ubuntu-22.04
    outputs:
      project_path: ${{ steps.detect.outputs.project_path }}
      used_zip: ${{ steps.detect.outputs.used_zip }}

    steps:
      - name: Checkout repository
        uses: actions/checkout@v4
        with:
          lfs: true

      - name: Detect source (zip vs. repo)
        id: detect
        run: |
          ZIP="zip/game.zip"

          if [ -f "$ZIP" ]; then
            echo "📦 zip/game.zip gefunden — entpacke als Projektquelle."
            mkdir -p _project_from_zip
            unzip -q "$ZIP" -d _project_from_zip

            # Godot-Projekt suchen: Verzeichnis das project.godot enthält
            PROJECT_GODOT=$(find _project_from_zip -name "project.godot" -maxdepth 4 | head -1)
            if [ -z "$PROJECT_GODOT" ]; then
              echo "❌ Kein project.godot in game.zip gefunden!"
              exit 1
            fi
            PROJECT_DIR=$(dirname "$PROJECT_GODOT")
            echo "✅ Projekt in ZIP gefunden: $PROJECT_DIR"
            echo "project_path=$PROJECT_DIR" >> "$GITHUB_OUTPUT"
            echo "used_zip=true"             >> "$GITHUB_OUTPUT"
          else
            echo "📁 Kein zip/game.zip — nutze Repo-Root als Projektquelle."
            echo "project_path=."  >> "$GITHUB_OUTPUT"
            echo "used_zip=false"  >> "$GITHUB_OUTPUT"
          fi

      # Den aufgelösten Projektstand als Artefakt zwischenspeichern damit
      # test- und build-Job nicht beide das ZIP entpacken müssen.
      - name: Upload resolved project
        uses: actions/upload-artifact@v4
        with:
          name: resolved-project
          path: |
            ${{ steps.detect.outputs.project_path == '.' && '.' || steps.detect.outputs.project_path }}
            !.git/
            !zip/
          retention-days: 1

  # ─── Unit Tests ─────────────────────────────────────────────────────────────
  test-logic:
    name: Run Unit Tests
    runs-on: ubuntu-22.04
    needs: resolve-source
    # Ohne das hier: "Resource not accessible by integration" beim Erstellen
    # des Checks-Eintrags — der Default-GITHUB_TOKEN hat sonst kein checks:write.
    permissions:
      checks: write
      pull-requests: write
      contents: read

    steps:
      - name: Download resolved project
        uses: actions/download-artifact@v4
        with:
          name: resolved-project
          path: project

      # Eigener, zweiter Checkout NUR für Git-Historie — die "resolved-project"-
      # Artifact-Kopie oben enthält bewusst kein .git/ (siehe "Upload resolved
      # project" in resolve-source), ein `git diff` bräuchte das aber. Separater
      # Schritt statt den Artifact-Flow anzufassen, um den Rest der Pipeline
      # (Android-Build, Release) unangetastet zu lassen.
      - name: Checkout repository (nur für Diff, nicht als Projektquelle)
        uses: actions/checkout@v4
        with:
          fetch-depth: 0
          path: _git_history_only

      - name: Determine changed .gd files (Format-Check-Ratchet)
        run: |
          cd _git_history_only
          if [ "${{ github.event_name }}" = "pull_request" ]; then
            git fetch origin "${{ github.base_ref }}" --depth=1 2>/dev/null || true
            CHANGED=$(git diff --name-only "origin/${{ github.base_ref }}...HEAD" -- '*.gd' 2>/dev/null | grep -v '^addons/' || true)
          elif [ "${{ github.event_name }}" = "push" ]; then
            BEFORE="${{ github.event.before }}"
            if [ -z "$BEFORE" ] || [ "$BEFORE" = "0000000000000000000000000000000000000000" ]; then
              # Erster Push auf einen neuen Branch — kein "vorher" zum
              # Diffen vorhanden, Fallback auf den letzten Commit allein.
              CHANGED=$(git diff --name-only HEAD~1 HEAD -- '*.gd' 2>/dev/null | grep -v '^addons/' || true)
            else
              CHANGED=$(git diff --name-only "$BEFORE" HEAD -- '*.gd' 2>/dev/null | grep -v '^addons/' || true)
            fi
          else
            # workflow_dispatch: kein sinnvoller "vorher"-Zustand (manueller
            # Trigger, kein Push-Event) — Ratchet greift hier nicht, also
            # ALLE .gd-Dateien prüfen. Seltener Fall, akzeptabler Mehraufwand.
            CHANGED=$(find . -name "*.gd" -not -path "./addons/*" | sed 's|^\./||')
          fi
          echo "$CHANGED" | grep -v '^$' > /tmp/changed_gd_files.txt || true
          echo "$(wc -l < /tmp/changed_gd_files.txt) geänderte .gd-Datei(en) erkannt."
          cd ..
          rm -rf _git_history_only

      - name: Install GUT Addon
        # v9.3.0 hatte einen globalen "Logger"-Klassennamen, der ab Godot 4.5
        # mit der neuen nativen Engine-Klasse "Logger" kollidiert
        # (SCRIPT ERROR: "The member 'Logger' shadows a native class.").
        # Dadurch schlug addons/gut/utils.gd beim Parsen fehl und GUT lief in
        # einer Dauerschleife/Endlosschleife fest, statt sauber zu terminieren.
        # Fix: bitwes/Gut#715 (behoben ab v9.4.0). v9.6.0 ist die für
        # Godot 4.6 freigegebene Version (unser GODOT_VERSION oben).
        run: |
          mkdir -p project/addons
          wget -q https://github.com/bitwes/Gut/archive/refs/tags/v9.6.0.zip -O gut.zip
          unzip -q gut.zip
          mv Gut-9.6.0/addons/gut project/addons/
          rm -rf gut.zip Gut-9.6.0

      - name: Download Godot ${{ env.GODOT_VERSION }}
        run: |
          wget -q "https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-stable/Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64.zip" -O godot.zip
          unzip -q godot.zip
          mv "Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64" /usr/local/bin/godot
          chmod +x /usr/local/bin/godot

      - name: Format check (gdformat) — nur geänderte Dateien
        # FIX: vorher `|| true` über ALLE .gd-Dateien im Projekt (>700
        # Dateien) — das prüft nichts wirklich, jeder Formatierungsfehler
        # wird stillschweigend verschluckt. Blindes Entfernen von `|| true`
        # wäre riskant: der aktuelle gdformat-Konformitätsstand des gesamten
        # Bestands ist in dieser Sandbox nicht prüfbar (kein Netzwerk, kein
        # gdtoolkit installierbar) — ein hartes Gate über ALLE Dateien könnte
        # beim ersten echten Lauf sofort wegen unbekannter Alt-Verstöße rot
        # werden, ohne dass hier jemand das vorher hätte sehen können.
        # RATCHET STATT BIG-BANG: nur .gd-Dateien prüfen, die in diesem
        # Push/PR tatsächlich geändert wurden — neue/geänderte Dateien müssen
        # ab jetzt konform sein, unberührter Altbestand blockiert nichts.
        # Bekannte Grenze: funktioniert sauber nur wenn used_zip=false (Repo-
        # Root als Projektquelle, aktuell der Fall) — bei zip/game.zip als
        # Quelle stimmen die Diff-Pfade (repo-relativ) nicht 1:1 mit den
        # Pfaden im entpackten Projektordner überein; dieser Fall müsste bei
        # Bedarf gesondert um den project_path-Präfix bereinigt werden.
        run: |
          pip install --quiet gdtoolkit
          if [ ! -s /tmp/changed_gd_files.txt ]; then
            echo "Keine geänderten .gd-Dateien in diesem Push/PR — Format-Check übersprungen."
            exit 0
          fi
          echo "Geprüfte Dateien (nur diese, siehe Kopfkommentar):"
          cat /tmp/changed_gd_files.txt
          FAILED=0
          while IFS= read -r f; do
            [ -z "$f" ] && continue
            if [ -f "project/$f" ]; then
              gdformat --check "project/$f" || FAILED=1
            else
              echo "  (übersprungen, nicht im aufgelösten Projekt gefunden: $f)"
            fi
          done < /tmp/changed_gd_files.txt
          if [ "$FAILED" -ne 0 ]; then
            echo "❌ Formatierungsfehler in geänderten .gd-Dateien — 'gdformat -i <datei>' lokal ausführen und committen."
            exit 1
          fi
          echo "✅ Alle geänderten .gd-Dateien sind gdformat-konform."

      - name: Force asset import
        run: |
          cd project
          godot --headless --editor --quit 2>&1 || true
          sleep 3

      # FIX 1: -gdir zeigt jetzt auf res://tests/unit statt res://tests.
      #   GUT durchsucht -gdir NICHT rekursiv. Die echten Unit-Tests liegen
      #   in tests/unit/test_*.gd — tests/ selbst enthält nur IntegrationTest.gd,
      #   das (a) nicht dem test_*.gd-Namensschema entspricht und (b) laut
      #   eigenem Header-Kommentar einen echten ServiceOrchestrator braucht,
      #   also headless ohnehin nicht laufen soll. Mit res://tests fand GUT
      #   dadurch schlicht nichts → "Nothing was run."
      # FIX 2: -gjunit_xml_file ergänzt. Ohne diesen Flag schreibt GUT gar
      #   keine results.xml — der "Publish test report"-Schritt unten hatte
      #   also so oder so nie etwas zum Lesen.
      - name: Run GUT tests
        run: |
          cd project
          godot --headless -s res://addons/gut/gut_cmdln.gd \
            -gdir=res://tests/unit \
            -gjunit_xml_file=res://results.xml \
            -gexit \
            2>&1 | tee gut-output.log

      # Zwei-Peer-Integrationstest (ADR-025/026, Connection-Ebene: IT-01/IT-02).
      # Eigener Schritt statt in -gdir=res://tests/unit mitlaufen zu lassen, weil:
      #   - tests/integration/ ist bewusst von tests/unit/ getrennt (andere
      #     Testklasse: echte ENetMultiplayerPeer/Sockets statt reiner Unit-Mocks)
      #   - ein Fehlschlag hier soll separat sichtbar sein, nicht im selben
      #     Report mit den Unit-Tests vermischt werden
      # Läuft rein auf 127.0.0.1-Loopback innerhalb des Runners (zwei
      # MultiplayerAPI-Instanzen im selben Prozess, siehe Datei-Kopfkommentar) —
      # braucht keine zwei Prozesse, keine zwei Runner, keine echten Geräte.
      # IT-03 ist bewusst `pending()` (kein vollständiger Gameplay-Round-Trip,
      # siehe Datei-Kopfkommentar) — GUT zählt pending nicht als Failure. Ein
      # echter Failure (z.B. IT-01/IT-02 bricht) soll den Job aber rot machen,
      # deshalb kein `|| true`, sondern der echte GUT-Exit-Code via PIPESTATUS.
      - name: Run GUT integration tests (two-peer, ADR-025/026)
        run: |
          cd project
          set +e
          godot --headless -s res://addons/gut/gut_cmdln.gd \
            -gdir=res://tests/integration \
            -gjunit_xml_file=res://results-integration.xml \
            -gexit \
            2>&1 | tee gut-integration-output.log
          EXIT_CODE=${PIPESTATUS[0]}
          echo "GUT integration exit code: $EXIT_CODE"
          exit $EXIT_CODE

      - name: Publish test report
        uses: mikepenz/action-junit-report@v4
        if: always()
        with:
          report_paths: 'project/results.xml,project/results-integration.xml'

      # Plain-Text-Log direkt in der Run-Summary anzeigen — kein Download nötig,
      # einfach den Actions-Run öffnen, "Summary" aufklappen, Block kopieren.
      - name: Add test log to job summary
        if: always()
        run: |
          {
            echo "## GUT Testergebnisse (Unit)"
            echo '```'
            cat project/gut-output.log
            echo '```'
            echo "## GUT Testergebnisse (Integration — Two-Peer, ADR-025/026)"
            echo '```'
            cat project/gut-integration-output.log
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

      # Zusätzlich als Datei zum Download — falls man die Rohdatei braucht.
      - name: Upload test log artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gut-test-log
          path: |
            project/gut-output.log
            project/gut-integration-output.log
          retention-days: 14
          if-no-files-found: warn

  # ─── IT-03: echter Zwei-Prozess-Movement-Round-Trip ─────────────────────────
  # Kein GUT, kein In-Process-Loopback (das deckt nur IT-01/IT-02 ab, siehe
  # test-logic-Job oben). Zwei GENUINE `godot --headless`-Prozesse auf demselben
  # Runner: ein Host (Server + Spieler 1) und ein Client, die sich über einen
  # echten Port auf 127.0.0.1 verbinden — derselbe App-Boot wie im echten Spiel
  # (ServiceOrchestrator, EventBus, WorldService, NetworkBridge, Player — keine
  # Mocks). scripts/testing/IT03Harness.gd ersetzt nur die menschlichen
  # UI-Klicks (Host starten / Beitreten), NICHT die Gameplay-Logik selbst — der
  # eigentliche Movement-Input kommt organisch aus Player._loop_free_predicted(),
  # exakt wie bei einem echten Spieler. Siehe Kopfkommentar der Datei für Details.
  integration-two-process:
    name: IT-03 — Two-Process Movement Round Trip
    runs-on: ubuntu-22.04
    needs: resolve-source
    timeout-minutes: 10

    steps:
      - name: Download resolved project
        uses: actions/download-artifact@v4
        with:
          name: resolved-project
          path: project

      - name: Download Godot ${{ env.GODOT_VERSION }}
        run: |
          wget -q "https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-stable/Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64.zip" -O godot.zip
          unzip -q godot.zip
          mv "Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64" /usr/local/bin/godot
          chmod +x /usr/local/bin/godot
          godot --version

      # Einmalig, sequenziell, VOR dem Start beider Prozesse — sonst würden
      # Host und Client gleichzeitig in denselben .godot/-Import-Cache schreiben
      # (Race Condition), siehe identisches Muster im test-logic-Job.
      - name: Force asset import
        run: |
          cd project
          godot --headless --editor --quit 2>&1 || true
          sleep 3

      # Host zuerst, im Hintergrund — braucht einen Moment Vorlauf um den
      # ENet-Server zu binden, bevor der Client sich verbindet.
      - name: Start host process (background)
        run: |
          cd project
          nohup godot --headless -- --it03-server --it03-port=38214 \
            > ../host.log 2>&1 &
          echo $! > ../host.pid
          sleep 5
          echo "Host-PID: $(cat ../host.pid)"

      # UDP-Latenz-Proxy (scripts/ci/udp_latency_proxy.py) zwischen Client und
      # Host — IT-03 lief bisher rein über 127.0.0.1-Loopback (praktisch
      # verzögerungsfrei, praktisch nie Paketverlust), was reale Mobilfunk-/
      # WLAN-Bedingungen nicht abdeckt. Der Client verbindet sich jetzt auf
      # --listen-port (38215) statt direkt auf den Host-Port (38214); der
      # Proxy relayt mit künstlicher Latenz/Jitter/Paketverlust in beide
      # Richtungen, ohne dass NetworkBridge/ENet auf GDScript-Seite davon
      # etwas mitbekommt. Profil (80ms Delay, ±20ms Jitter, 2% Loss) ist ein
      # bewusst mildes "spürbar, aber spielbar"-Mobilfunk-Szenario, kein
      # Worst-Case-Stresstest — siehe scripts/ci/udp_latency_proxy.py-
      # Kopfkommentar für strengere Profile.
      - name: Start UDP latency proxy (background)
        run: |
          cd project
          nohup python3 scripts/ci/udp_latency_proxy.py \
            --listen-port 38215 --target-host 127.0.0.1 --target-port 38214 \
            --delay-ms 80 --jitter-ms 20 --loss-pct 2 \
            > ../proxy.log 2>&1 &
          echo $! > ../proxy.pid
          sleep 2
          echo "Proxy-PID: $(cat ../proxy.pid)"

      # Client läuft im Vordergrund — sein Exit-Code IST das Testergebnis
      # (0 = PASS, 1 = FAIL/Timeout, siehe IT03Harness._fail()/quit(0)).
      # `timeout` als zusätzliches Sicherheitsnetz falls der Prozess aus
      # irgendeinem Grund trotz interner Timeouts hängen bleibt.
      # Verbindet jetzt auf den Proxy-Port (38215), nicht mehr direkt auf den
      # Host (38214) — siehe "Start UDP latency proxy" oben.
      - name: Run client process (foreground, result = exit code)
        id: client
        run: |
          cd project
          set +e
          timeout 180 godot --headless -- --it03-client --it03-connect=127.0.0.1:38215 \
            > ../client.log 2>&1
          echo "exit_code=$?" >> "$GITHUB_OUTPUT"

      - name: Stop host process
        if: always()
        run: |
          if [ -f host.pid ]; then
            kill "$(cat host.pid)" 2>/dev/null || true
          fi

      - name: Stop UDP latency proxy
        if: always()
        run: |
          if [ -f proxy.pid ]; then
            kill "$(cat proxy.pid)" 2>/dev/null || true
          fi

      - name: Add logs to job summary
        if: always()
        run: |
          {
            echo "## IT-03 Host-Log"
            echo '```'
            cat host.log 2>/dev/null || echo "(kein Host-Log)"
            echo '```'
            echo "## IT-03 Proxy-Log (UDP-Latenz/Jitter/Loss)"
            echo '```'
            cat proxy.log 2>/dev/null || echo "(kein Proxy-Log)"
            echo '```'
            echo "## IT-03 Client-Log"
            echo '```'
            cat client.log 2>/dev/null || echo "(kein Client-Log)"
            echo '```'
          } >> "$GITHUB_STEP_SUMMARY"

      - name: Upload IT-03 logs
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: it03-logs
          path: |
            host.log
            proxy.log
            client.log
          retention-days: 14
          if-no-files-found: warn

      # Client-Exit-Code entscheidet über den Job — IT03Harness gibt 0 für PASS,
      # 1 für FAIL/Timeout zurück (`timeout` selbst gibt 124 bei eigenem
      # Ablauf zurück, was ebenfalls korrekt als Fehlschlag durchfällt).
      - name: Evaluate result
        run: |
          CODE="${{ steps.client.outputs.exit_code }}"
          echo "Client-Exit-Code: $CODE"
          if [ "$CODE" != "0" ]; then
            echo "❌ IT-03 fehlgeschlagen (Exit-Code $CODE) — siehe Job-Summary/Logs."
            exit 1
          fi
          echo "✅ IT-03 bestanden."

  # ─── DI-Überblick + Testabdeckung ──────────────────────────────────────────
  # Reines Python/stdlib, statische Analyse über *.gd / BootstrapConfig.tres —
  # braucht keinen Godot-Import und läuft daher unabhängig von test-logic.
  # Reporting-only: dieser Job gated nichts (kein exit 1 bei Lücken), siehe
  # Kopfkommentar in scripts/ci/di_test_overview.py. Falls das mal zum Gate
  # werden soll: erst mit dem Projekt-Owner klären (docs/ci-pipeline.md).
  di-test-overview:
    name: DI-Überblick & Testabdeckung
    runs-on: ubuntu-22.04
    needs: resolve-source

    steps:
      - name: Download resolved project
        uses: actions/download-artifact@v4
        with:
          name: resolved-project
          path: project

      # JSON (--out) ist der primäre Output — für Agenten/Tooling gedacht
      # (siehe scripts/ci/di_query.py zum Navigieren). --markdown-out liefert
      # in demselben Lauf zusätzlich die Menschen-lesbare Fassung (u. a. für
      # die Job-Summary, die das Skript selbst über $GITHUB_STEP_SUMMARY befüllt).
      - name: Run DI/coverage overview
        run: |
          python3 project/scripts/ci/di_test_overview.py \
            --project project \
            --out di-overview.json \
            --markdown-out di-overview.md

      - name: Upload DI overview artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: di-test-overview
          path: |
            di-overview.json
            di-overview.md
          retention-days: 14
          if-no-files-found: warn

  # ─── Android Build ───────────────────────────────────────────────────────────
  build-android:
    name: Build Android APK
    runs-on: ubuntu-22.04
    needs: resolve-source
    timeout-minutes: 30
    # Der eigentlich teure Schritt (NDK/Android-SDK/Gradle/Godot-Export) —
    # hier sitzt jetzt der "App"-Wort-Gate, der vorher auf resolve-source saß
    # (siehe Kommentar oben bei "jobs:"). Bei pull_request gibt es keinen
    # head_commit → Fallback auf den PR-Titel.
    if: |
      github.event_name == 'workflow_dispatch' ||
      contains(github.event.head_commit.message, 'App') ||
      contains(github.event.pull_request.title, 'App')

    steps:
      # Aufgelöste Projektquelle (Repo-Root oder entpacktes ZIP) herunterladen
      - name: Download resolved project
        uses: actions/download-artifact@v4
        with:
          name: resolved-project
          path: project

      - name: Show source info
        run: |
          echo "Projektquelle: ${{ needs.resolve-source.outputs.project_path }}"
          echo "ZIP genutzt:   ${{ needs.resolve-source.outputs.used_zip }}"
          echo "project.godot: $(find project -name 'project.godot' | head -1)"

      - name: Set up Java 17
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17

      - name: Set up Android SDK
        uses: android-actions/setup-android@v3

      - name: Install Android build tools & NDK
        run: |
          sdkmanager \
            "platform-tools" \
            "platforms;android-34" \
            "build-tools;34.0.0" \
            "ndk;23.2.8568313"

      - name: Download Godot ${{ env.GODOT_VERSION }}
        run: |
          URL="https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-stable"
          wget -q "${URL}/Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64.zip" -O godot.zip
          unzip -q godot.zip
          mv "Godot_v${{ env.GODOT_VERSION }}-stable_linux.x86_64" /usr/local/bin/godot
          chmod +x /usr/local/bin/godot
          godot --version

      - name: Download Android export templates
        run: |
          URL="https://github.com/godotengine/godot/releases/download/${{ env.GODOT_VERSION }}-stable"
          TPL="Godot_v${{ env.GODOT_VERSION }}-stable_export_templates.tpz"
          wget -q "${URL}/${TPL}" -O templates.tpz
          mkdir -p ~/.local/share/godot/export_templates/${{ env.GODOT_VERSION }}.stable
          unzip -q templates.tpz -d /tmp/templates
          mv /tmp/templates/templates/* ~/.local/share/godot/export_templates/${{ env.GODOT_VERSION }}.stable/

      - name: Generate debug keystore
        run: |
          keytool -genkey -v \
            -keystore debug.keystore \
            -alias androiddebugkey \
            -keyalg RSA -keysize 2048 -validity 10000 \
            -storepass android -keypass android \
            -dname "CN=Debug, O=Android, C=US"

      - name: Ensure export_presets.cfg exists
        run: |
          PRESETS="project/export_presets.cfg"
          if [ ! -f "$PRESETS" ]; then
            echo "Kein export_presets.cfg — erstelle Host+Guest-Debug-Presets."
            # ZWEI Presets mit unterschiedlichem package/unique_name (= Android
            # applicationId) und package/name (= angezeigter App-Name). Android
            # erkennt zwei Apps als "dieselbe App" ausschließlich über die
            # applicationId — Signatur/Dateiname spielen dafür keine Rolle.
            # Mit identischem unique_name würde die zweite Installation die
            # erste einfach überschreiben (Update statt Nebeneinander-Install).
            cat > "$PRESETS" << 'EOF'
          [preset.0]
          name="Android-Host"
          platform="Android"
          runnable=true
          dedicated_server=false
          custom_features=""
          export_filter="all_resources"
          include_filter=""
          exclude_filter=""
          export_path="build/android/WildGrove-Host-debug.apk"
          encryption_include_filters=""
          encryption_exclude_filters=""
          encrypt_pck=false
          encrypt_directory=false

          [preset.0.options]
          gradle_build/use_gradle_build=false
          architectures/armeabi-v7a=false
          architectures/arm64-v8a=true
          architectures/x86=false
          architectures/x86_64=false
          keystore/debug="../../debug.keystore"
          keystore/debug_user="androiddebugkey"
          keystore/debug_password="android"
          keystore/release=""
          keystore/release_user=""
          keystore/release_password=""
          package/unique_name="com.yourname.wildgrove.host"
          package/name="WildGrove Host"
          package/signed=true
          package/classify_as_game=true
          screen/immersive_mode=true
          screen/orientation=6
          screen/support_small=false
          screen/support_normal=true
          screen/support_large=true
          screen/support_xlarge=true

          [preset.1]
          name="Android-Guest"
          platform="Android"
          runnable=true
          dedicated_server=false
          custom_features=""
          export_filter="all_resources"
          include_filter=""
          exclude_filter=""
          export_path="build/android/WildGrove-Guest-debug.apk"
          encryption_include_filters=""
          encryption_exclude_filters=""
          encrypt_pck=false
          encrypt_directory=false

          [preset.1.options]
          gradle_build/use_gradle_build=false
          architectures/armeabi-v7a=false
          architectures/arm64-v8a=true
          architectures/x86=false
          architectures/x86_64=false
          keystore/debug="../../debug.keystore"
          keystore/debug_user="androiddebugkey"
          keystore/debug_password="android"
          keystore/release=""
          keystore/release_user=""
          keystore/release_password=""
          package/unique_name="com.yourname.wildgrove.guest"
          package/name="WildGrove Guest"
          package/signed=true
          package/classify_as_game=true
          screen/immersive_mode=true
          screen/orientation=6
          screen/support_small=false
          screen/support_normal=true
          screen/support_large=true
          screen/support_xlarge=true
          EOF
          else
            echo "export_presets.cfg existiert bereits (kommt aus dem Repo) — wird unverändert genutzt."
            echo "Für Host+Guest brauchst du dort zwei Presets mit unterschiedlichem"
            echo "package/unique_name — siehe Kommentar in diesem Workflow-Schritt."
          fi

      # FIX (vorher: Shallow-Clone + `git rev-list --count HEAD` — mit
      # `--depth=1` bekommt der lokale Klon aber immer nur GENAU einen
      # Commit, also zählt `rev-list --count` praktisch immer "1". Der
      # Versionscode inkrementierte dadurch nie sinnvoll, siehe
      # docs/ci-pipeline.md "Known limitations" (alte Fassung).
      # `github.run_number` ist ein von GitHub selbst geführter, pro Workflow
      # monoton steigender Zähler — kein Git-Zugriff, kein Netzwerk-Call,
      # keine Race Condition zwischen Host/Klon nötig.
      - name: Set version code from GitHub run number
        run: |
          COUNT="${{ github.run_number }}"
          echo "VERSION_CODE=$COUNT" >> $GITHUB_ENV
          echo "Version code: $COUNT"
          sed -i "s/config\/version=.*/config\/version=\"0.1.${COUNT}\"/" \
            "$(find /home/runner/work -name project.godot | head -1)" 2>/dev/null || true
            "$(find /home/runner/work -name project.godot | head -1)" 2>/dev/null || true

      - name: Create output directory
        run: mkdir -p project/build/android

      # Tests und GUT-Addon aus dem Projektverzeichnis entfernen bevor Godot
      # die Assets importiert. Godot parst beim Export ALLE .gd-Dateien im
      # Projektordner — auch wenn sie per exclude_filter aus dem PCK
      # ausgeschlossen würden. Da GUT im Build-Job nicht installiert ist,
      # schlägt das Parsen von test_*.gd (extends GutTest) fehl und bricht
      # den Export ab. Lösung: Dateien vorher physisch entfernen.
      #
      # scripts/testing/ (IT03Harness) ist kein Testskript im GUT-Sinn (parst
      # ohne GUT-Addon einwandfrei), soll aber trotzdem nicht in der Produktions-
      # APK landen — es ist ein CI-only Zwei-Prozess-Treiber für IT-03, siehe
      # scripts/testing/IT03Harness.gd Kopfkommentar. Autoload-Zeile in
      # project.godot muss mitentfernt werden, sonst referenziert der Export
      # ein fehlendes Autoload-Skript.
      - name: Strip test files and GUT addon
        run: |
          echo "🧹 Entferne Test-Skripte und GUT-Addon für den Produktions-Export..."
          rm -rf project/tests/
          rm -rf project/addons/gut/
          rm -rf project/scripts/testing/
          sed -i '/^IT03Harness=/d' project/project.godot
          echo "✅ Fertig. Verbleibende Addons:"
          ls project/addons/ 2>/dev/null || echo "  (keine weiteren Addons)"

      - name: Import project assets
        run: |
          cd project
          godot --headless --editor --quit 2>&1 || true
          sleep 5

      - name: Export APK (Host)
        run: |
          cd project
          godot --headless \
            --export-debug "Android-Host" \
            "build/android/${{ env.EXPORT_NAME }}-Host-debug.apk" \
            2>&1

      - name: Export APK (Guest)
        run: |
          cd project
          godot --headless \
            --export-debug "Android-Guest" \
            "build/android/${{ env.EXPORT_NAME }}-Guest-debug.apk" \
            2>&1

      - name: Verify APKs
        run: |
          for VARIANT in Host Guest; do
            APK="project/build/android/${{ env.EXPORT_NAME }}-${VARIANT}-debug.apk"
            if [ -f "$APK" ]; then
              SIZE=$(du -sh "$APK" | cut -f1)
              echo "✅ APK erstellt: $APK ($SIZE)"
            else
              echo "❌ APK nicht gefunden: $APK"
              exit 1
            fi
          done

      - name: Upload Host APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: WildGrove-Host-debug-APK
          path: project/build/android/${{ env.EXPORT_NAME }}-Host-debug.apk
          retention-days: 14
          if-no-files-found: error

      - name: Upload Guest APK artifact
        uses: actions/upload-artifact@v4
        with:
          name: WildGrove-Guest-debug-APK
          path: project/build/android/${{ env.EXPORT_NAME }}-Guest-debug.apk
          retention-days: 14
          if-no-files-found: error

      - name: Upload full source as ZIP
        uses: actions/upload-artifact@v4
        with:
          name: WildGrove-Full-Source
          path: |
            project/
            !project/.git/
            !project/build/
          retention-days: 7

  # ─── GitHub Release (nur bei Tag-Push) ──────────────────────────────────────
  release:
    name: Create GitHub Release
    needs: build-android
    runs-on: ubuntu-22.04
    if: startsWith(github.ref, 'refs/tags/v')

    steps:
      - name: Download Host APK
        uses: actions/download-artifact@v4
        with:
          name: WildGrove-Host-debug-APK
          path: ./release

      - name: Download Guest APK
        uses: actions/download-artifact@v4
        with:
          name: WildGrove-Guest-debug-APK
          path: ./release

      - name: Create Release
        uses: softprops/action-gh-release@v2
        with:
          files: ./release/*.apk
          generate_release_notes: true
          name: "WildGrove ${{ github.ref_name }}"
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

````

---

## Änderungen — Verlauf

**Session 7 (ursprüngliche Version, siehe Git-Historie dieser Datei für den vollen Text):**
Godot 4.3, ein einzelnes Android-Preset, GUT v9.3.0, kein IT-03, kein DI-Überblick. Drei
Fixes in dieser Session: `-gdir` auf `res://tests/unit` korrigiert (GUT durchsucht nicht
rekursiv), `-gjunit_xml_file` ergänzt (sonst keine `results.xml`), ADR-003-Lint-Schritt
hinzugefügt (`scripts/ci/lint_servicenode.sh`, gated, kein `|| true`).

**Zwischenzeitlich (vor dieser Session, Autor: Project Owner):** Godot auf 4.6.3 angehoben,
GUT auf v9.6.0 (Fix für den Logger-Klassennamen-Konflikt mit Godot ≥4.5, bitwes/Gut#715).
Zweites Android-Preset (Host + Guest, getrennte `package/unique_name`) für Nebeneinander-
Installation auf einem Testgerät. Zwei-Peer-Integrationstests (`tests/integration/`,
IT-01/IT-02) als eigener Schritt. **`integration-two-process`-Job (IT-03)** neu hinzugekommen:
zwei echte `godot --headless`-Prozesse, verbunden über einen echten UDP-Port, treibt
`scripts/testing/IT03Harness.gd`. **`di-test-overview`-Job** neu hinzugekommen, referenzierte
zu diesem Zeitpunkt aber zwei Skripte, die im Projekt noch nicht existierten.

**Diese Session — drei Änderungen, alle mit dem Project Owner in diesem Gespräch
abgestimmt:**

1. **`scripts/ci/di_test_overview.py` und `scripts/ci/di_query.py` neu gebaut.** Der
   `di-test-overview`-Job rief sie bereits auf, aber beide Dateien fehlten im Projekt — der
   Job wäre beim ersten `python3`-Aufruf mit "file not found" gescheitert. `di_test_overview.py`
   liest `config/BootstrapConfig.tres` (ServiceDefinition/ResourceDefinition-Sub-Resources),
   baut den DI-Graphen, prüft auf unauflösbare Dependencies und Zyklen (Kahn's Algorithmus,
   pro Scope getrennt, Cross-Scope-Regel: session darf global referenzieren, nicht umgekehrt),
   und gleicht jeden Service gegen seine erwartete Unit-Test-Datei ab
   (`tests/unit/test_<snake_case(Skriptname)>.gd`, mit Fallback ohne `_service`-Suffix für
   Fälle wie `StatModifierService.gd` → `test_stat_modifier.gd`). Reines Reporting per Default
   (`--strict` als Opt-in für ein hartes Gate — siehe Governance-Note oben, das ist eine
   Entscheidung des Project Owners). Aktueller Stand gegen dieses Repo: 41 Services, 1
   injectable Resource, 0 Errors, 0 Warnings, 100% Unit-Test-Abdeckung.
   `scripts/ci/di_query.py` ist ein Navigator für die erzeugte `di-overview.json`
   (`deps <service>`, `dependents <service>`, `missing-tests`, `boot-order`, `errors`).

2. **`scripts/ci/udp_latency_proxy.py` in den `integration-two-process`-Job eingehängt.**
   Das Skript existierte bereits im Projekt, war aber in keinem Workflow-Job verdrahtet.
   IT-03 lief bisher rein über 127.0.0.1-Loopback (praktisch verzögerungsfrei, praktisch nie
   Paketverlust) — das deckt keine realen Mobilfunk-/WLAN-Bedingungen ab. Der Client verbindet
   sich jetzt auf Port 38215 (Proxy) statt direkt auf 38214 (Host); der Proxy relayt mit
   80ms Basis-Latenz, ±20ms Jitter, 2% Paketverlust in beide Richtungen — ein bewusst mildes
   "spürbar, aber spielbar"-Profil, kein Worst-Case-Stresstest. `NetworkBridge`/ENet auf
   GDScript-Seite bekommen davon nichts mit, aus deren Sicht ist es einfach ein Netzwerk mit
   echter Latenz. Proxy-Log wird jetzt zusätzlich zu Host-/Client-Log in der Job-Summary
   angezeigt und als Artefakt hochgeladen.

3. **Workflow-Datei ins Repo aufgenommen** (`.github/workflows/build-apk.yml`), statt nur
   hier in `docs/ci-pipeline.md` referenziert zu werden — schließt die Lücke, die zu Beginn
   dieser Session zu einer falschen Annahme führte ("Pipeline existiert nicht"), weil das ZIP
   ohne `.github/` exportiert wurde.

4. **Trigger-Logik entkoppelt.** Vorher saß der "'App' im Commit/PR-Titel"-Gate auf
   `resolve-source`, wovon ALLE anderen Jobs per `needs:` abhängen — ein Skip von
   `resolve-source` hat dadurch auch `test-logic`, `integration-two-process` und
   `di-test-overview` übersprungen. Unit-Tests/IT-03/DI-Überblick liefen damit faktisch nur,
   wenn jemand "App" ins Commit geschrieben hat, statt bei jedem Push/PR. Der Gate sitzt jetzt
   nur noch auf `build-android` (dem tatsächlich teuren Schritt: NDK/Android-SDK/Gradle) —
   Tests laufen ab jetzt bei jedem Push/PR, unabhängig vom Commit-Text. Verhalten von
   `build-android`/`release` selbst unverändert.

5. **`Set version code` repariert.** Vorher: `git init` in ein temporäres Verzeichnis,
   `git fetch --depth=1`, dann `git rev-list --count HEAD` — mit `--depth=1` bekommt der Klon
   aber immer genau einen Commit, `rev-list --count` liefert praktisch immer "1". Der
   Versionscode inkrementierte nie sinnvoll. Fix: `github.run_number` (von GitHub selbst
   geführter, pro Workflow monoton steigender Zähler) statt Git-Historie — kein Netzwerk-Call,
   keine Shallow-Clone-Fallstricke mehr.

6. **`Format check` (gdformat) von `|| true` auf ein echtes Ratchet-Gate umgestellt.** Vorher
   lief `gdformat --check` über alle >700 `.gd`-Dateien, aber `|| true` am Zeilenende
   verschluckte jedes Ergebnis — der Schritt konnte nie rot werden. Blindes Entfernen von
   `|| true` wäre riskant gewesen: der aktuelle gdformat-Konformitätsstand des GESAMTEN
   Bestands ist außerhalb einer echten CI-Umgebung nicht prüfbar (kein Netzwerk, `gdtoolkit`
   nicht installierbar in dieser Sandbox) — ein hartes Gate über alle Dateien hätte beim
   ersten echten Lauf ohne Vorwarnung wegen unbekannter Alt-Verstöße rot werden können.
   Stattdessen: ein neuer Schritt (`Determine changed .gd files`, per zusätzlichem
   `actions/checkout@v4` mit `fetch-depth: 0` — die `resolved-project`-Artifact-Kopie enthält
   bewusst kein `.git/`) ermittelt die tatsächlich geänderten `.gd`-Dateien dieses Push/PR
   (`git diff` gegen `github.event.before` bzw. den PR-Base-Branch) und `gdformat --check`
   läuft nur noch über genau diese. Unberührter Altbestand blockiert nichts mehr, aber jede
   neu geänderte Datei muss ab jetzt konform sein. `workflow_dispatch` hat kein sinnvolles
   "vorher" — dort werden alle Dateien geprüft (seltener, manueller Trigger).

7. **Zwei neue Service-Integrationstests unter `tests/integration/`** (aus der E2E-
   Testplanung dieser Session, "Ebene A" — echter ServiceOrchestrator, kein Netzwerk, kein
   neues CI-Harness nötig, laufen im bereits vorhandenen `test-logic`-Job mit):
   - `test_quest_reward_chain.gd` — Quest→Reward→Inventory/XP-Kette gegen den echten Content
     (`quest_woodcutter_intro`). Deckt den SEC-03-Guard ab (Abschluss mit unvollständigem
     Fortschritt wird verweigert UND zahlt keinen Reward aus) sowie Reward-Korrektheit und
     Non-Repeatable-Schutz gegen Reward-Dupe durch Wiederholung.
   - `test_pvp_death_loss_protections.gd` — höchstes wirtschaftliches Risiko im aktuellen
     Testplan (Item-/Gold-Dupe vs. zu Unrecht verlorene Items). `PvPDeathLossService.
     apply_death_loss()` ist vollständig deterministisch (Tier-Tabelle nach Killer-Risiko,
     keine RNG-Auswahl bei Item-Verlust), was exakte Zahlen-Asserts statt nur Stichproben
     erlaubt. Deckt ab: Verlust exakt nach Risiko-Tier, alle drei ADR-038-Schutzkategorien
     (`is_pve_death_protected`/`is_theft_protected` permanent, `is_pvp_protected` einmalig
     und danach verbraucht), sowie 100%-Verlust bei geskulltem Tod (überschreibt die
     Tier-Tabelle, permanente Schutzkategorien bleiben trotzdem wirksam).

   Beide bewusst NICHT als neues IT-0x-Zwei-Prozess-Harness gebaut — die getesteten Service-
   Methoden (`request_complete_quest()`, `apply_death_loss()`, …) prüfen bereits selbst auf
   Autorität und sind unabhängig von einer echten Netzwerkverbindung aufrufbar; ein zweiter
   Prozess hätte hier nur Overhead ohne zusätzliche Abdeckung gebracht.

8. **`tests/helpers/SceneLifecycleHarness.gd` neu gebaut** — schließt die Lücke, die
   `tests/IntegrationTest.gd` im eigenen Kopfkommentar offen benennt ("gehört in einen
   separaten IntegrationTest_SessionLifecycle.gd sobald ein Test-Runner-Harness für
   Scene-Lifecycle verfügbar ist"). Nutzt aus, dass `WorldScopeInitializer.gd` rein
   strukturell ist (braucht nur einen `Node3D`-Parent im SceneTree, siehe dortiger
   Kommentar "Kein AutoLoad-Zugriff. Kein EventBus. Kein Pull.") — ein minimaler
   synthetischer Root (`Node3D` + `WorldScopeInitializer`-Kind) durchläuft exakt denselben
   Produktionscodepfad wie die echte `World.tscn`, ohne Terrain-Generierung oder Assets.
   Treibt darüber den echten Boot-Flow: `boot_fresh_session(player_id)`,
   `reload_current_session()` (= der Produktions-"Laden"-Pfad, `EventBus.ui.
   emit_scene_reload_requested()`), `return_to_main_menu()`.

   **Zusätzlicher, wichtiger Fund dabei:** `tests/IntegrationTest.gd` UND die beiden in
   dieser Session vorher hinzugefügten Tests (`test_quest_reward_chain.gd`,
   `test_pvp_death_loss_protections.gd`) prüften bisher nur passiv
   `gamemanager.is_playing()` und übersprangen sich sonst — in der tatsächlichen CI-
   Invocation (`gut_cmdln.gd -gdir=res://tests/...`, reiner Skript-Lauf ohne UI) hätte
   NICHTS die App je von MAIN_MENU nach PLAYING getrieben. Alle drei wären also, ohne dass
   das vorher auffiel, bei jedem echten CI-Lauf permanent übersprungen worden — kein Fehler
   sichtbar, aber auch keine tatsächliche Abdeckung. `test_quest_reward_chain.gd` und
   `test_pvp_death_loss_protections.gd` wurden entsprechend umgebaut: sie booten ihre
   PLAYING-Session jetzt selbst über den Harness in `before_each()`, statt auf einen von
   außen bereits vorhandenen Zustand zu warten. `tests/IntegrationTest.gd` selbst wurde NICHT
   angefasst (vorbestehende Datei, nicht Teil dieser Session) — ließe sich mit demselben
   Muster genauso umbauen, siehe "Known limitations".

9. **`tests/integration/test_session_lifecycle.gd` neu** — die eigentliche Motivation für den
   Harness: Character-Switch (zwei unabhängige Sessions nacheinander, State-Isolation
   zwischen ihnen) und Save/Load-Round-Trip (`save_game()` vor `reload_current_session()`,
   Zustand danach muss identisch sein) plus eine Negativ-Gegenprobe (eine NICHT gespeicherte
   Änderung darf einen Reload nicht überleben — beweist, dass der Test einen echten Disk-Read
   auslöst, statt zufällig grün zu sein, weil gar nichts zurückgesetzt wird).

**Korrektur an dieser Doku selbst:** Die vorherige Fassung verwies hier auf
`docs/audit/AUDIT-01-pain-points-and-review-verification.md` für eine "vollständige Analyse"
dieser drei Punkte — diese Datei existiert im Projekt nicht (nur `AUDIT-03`, `AUDIT-04`,
`AUDIT-05` unter `docs/audit/` sind vorhanden). Der Verweis wurde unverändert aus einer
älteren Fassung übernommen, ohne geprüft zu werden, und ist mit den obigen Fixes ohnehin
gegenstandslos geworden.

## Known limitations

- `Format check` prüft nur geänderte Dateien (Ratchet, siehe Punkt 6 oben) — Alt-Verstöße im
  unberührten Bestand bleiben unentdeckt, bis die jeweilige Datei das nächste Mal angefasst
  wird. Das ist beabsichtigt (Big-Bang-Reformat hätte einen riesigen, funktional leeren Diff
  erzeugt), aber wer den gesamten Bestand einmalig durchformatieren will, muss das separat tun.
- Das Ratchet-`git diff` ist nur für `used_zip=false` (Repo-Root als Projektquelle, aktuell der
  Fall) sauber pfad-korrekt. Bei `zip/game.zip` als Quelle müssten die Diff-Pfade zusätzlich um
  den `project_path`-Präfix bereinigt werden — aktuell nicht implementiert, da nicht der
  genutzte Fall.
- `di_test_overview.py`s Testdatei-Zuordnung ist Namenskonvention + ein bekannter Fallback,
  kein Import-Graph-Scan — ein Service, dessen Test einem völlig anderen Namensschema folgt,
  würde fälschlich als "kein Unit-Test" gemeldet. Aktuell 0 solcher Fälle in diesem Repo
  (100% Abdeckung), aber bei einem echten Fund lohnt sich eine manuelle Gegenprobe, bevor ein
  Service als ungetestet behandelt wird.
- `udp_latency_proxy.py` ist für genau einen Client ausgelegt (siehe Kopfkommentar) — für
  IT-03 ausreichend, nicht für Mehrspieler-Lasttests gedacht.
- Keiner der drei Fixes in dieser Session (Trigger, Version-Code, Format-Ratchet) konnte gegen
  eine echte GitHub-Actions-Ausführung verifiziert werden (kein Netzwerk in dieser Sandbox) —
  YAML-Syntax und Job-/Step-Struktur wurden geprüft (`yaml.safe_load` + Job-Graph-Inspektion),
  das tatsächliche Laufzeitverhalten (insbesondere `git diff` gegen echte GitHub-Event-Payloads)
  nicht. Erster echter Push ist der eigentliche Test.
- `test_quest_reward_chain.gd`, `test_pvp_death_loss_protections.gd`, `test_session_lifecycle.gd`
  und `tests/helpers/SceneLifecycleHarness.gd` sind wie die vorhandenen Zwei-Peer-Tests OHNE
  laufendes Godot/GUT geschrieben — sorgfältig gegen die tatsächlichen Service-/Engine-Quellen
  konstruiert, aber nicht ausgeführt. Der Harness selbst trägt zusätzlich eine unverifizierte
  Kernannahme (siehe dessen Kopfkommentar): dass `WorldService`/`WorldGenerationService` mit
  einem NACKTEN `Node3D`-Root (keine vorbereiteten Spawn-Marker/Chunk-Container) tatsächlich
  fertig durchläuft. Schlägt `test_session_lifecycle.gd` beim ersten echten Lauf mit einem
  Timeout fehl, ist das die naheliegendste erste Vermutung, nicht ein Bug in der Save/Load-
  oder Quest-Logik selbst. Alle Testfälle haben eine eingebaute Selbstschutz-Klausel
  (`pending()`-Skip statt Falsch-Positiv bei fehlgeschlagenem Boot), aber das ersetzt keinen
  echten Lauf.
- `tests/IntegrationTest.gd` (vorbestehende Datei, nicht Teil dieser Session) prüft weiterhin
  nur passiv `is_playing()` und wurde nicht auf `SceneLifecycleHarness` umgebaut — sie würde
  in der aktuellen CI-Invocation weiterhin permanent überspringen. Ließe sich mit demselben
  Muster wie `test_quest_reward_chain.gd` nachziehen, war aber nicht Teil dieser Anfrage.
- E2E-Priorisierung: Ebene A (Service-Integration, kein Netzwerk) deckt jetzt Quest-Rewards,
  PvP-Death-Loss UND Session-Lifecycle (Character-Switch, Save/Load) ab. Noch offen:
  Trade/Auction-House-Dupe-Risiko über echte RPC-Autoritätsgrenzen (Ebene B, zwei Peers wie
  `test_network_bridge_rpc_guards_two_peer.gd`).
