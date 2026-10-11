> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-045: Telemetrie/Crash-Reporting

**Status:** Angenommen — umgesetzt (Round 101)
**Datum:** 2026-07
**Kontext:** Seit ADR-018 (Round 53) als fehlend dokumentiert. Zusätzlicher
Anlass: seit Round 89 endet praktisch jede Runde mit "kein Godot-Editor/
Headless-Runner verfügbar, nur strukturell geprüft" — inzwischen über ein
Dutzend neue/geänderte Systeme, die nie tatsächlich liefen. Crash-Reporting
ist das Werkzeug, das beim ersten echten Testlauf zeigt, wo es kracht.

## Entscheidung

Zwei Hälften, beide bauen bewusst auf der bestehenden `AppLogger`-
Infrastruktur auf (Godot-Autoload, `scripts/logger/Logger.gd`) statt sie
zu duplizieren:

### 1. Crash-Reporting (in `AppLogger` selbst)

`AppLogger.build_crash_report(reason: String) -> Dictionary` — reine
Dictionary-Konstruktion (Grund, Zeitstempel, Godot-Version, Plattform,
`log_summary()`, `get_log_stats()`, `get_errors()`, kompletter
Ring-Puffer `peek_log_buffer()`), **kein Datei-I/O**. Getrennt von
`write_crash_report(reason) -> String`, das den Report als JSON neben die
Log-Datei schreibt (dieselbe Downloads-Ordner-Degradationskette wie
`_resolve_log_file_path()`/`request_log_export()` — kein drittes
Pfad-Schema im Projekt) und den geschriebenen Pfad zurückgibt.

Aufgerufen von zwei bestehenden Stellen:
- `fatal()` — vor dem bereits vorhandenen synchronen Flush.
- `_notification(NOTIFICATION_CRASH)` — als eigener, neuer Zweig, bewusst
  **nicht** im bestehenden gemeinsamen Flush-Block (`WM_CLOSE_REQUEST`/
  `CRASH`/`PREDELETE`), weil die anderen beiden normale Beendigungen sind,
  kein Absturz — ein Crash-Report bei jedem normalen Fenster-Schließen wäre
  irreführend.

**Warum in `AppLogger` selbst statt als eigener Service?** `AppLogger` ist
AutoLoad #1 ("keine Abhängigkeiten, existiert für die gesamte Laufzeit",
siehe dortiger Klassenkommentar) und hat bereits alles, was ein
Crash-Report braucht (Ring-Puffer, Fehler-Zähler, Datei-Pfad-Auflösung).
Ein Absturz kann in jeder Boot-Phase passieren, auch bevor der
`ServiceRegistry` überhaupt existiert — ein `Service` (der über die
Registry läuft) wäre für einen frühen Boot-Crash schlicht noch nicht da.

### 2. Telemetrie (`TelemetryService`, `scripts/telemetry/`)

`record_event(event_name: String, properties: Dictionary = {})` — ein
dünner Wrapper um `AppLogger.log_trace(event_name, properties,
"Telemetry")`. **Kein eigenes File-I/O, kein eigener Ring-Puffer, kein
eigener Thread** — `AppLogger` hat das alles bereits (NDJSON-Format,
Hintergrund-Schreib-Thread, Kategorie-basiertes Stummschalten via
`AppLogger.mute_category("Telemetry")`), ein zweites System nur für
Telemetrie-Events wäre reine Dopplung.

Was `TelemetryService` zusätzlich liefert, was `AppLogger` NICHT hat:
pro-Event-Name aggregierte Zähler für die laufende Sitzung
(`get_event_counts()`/`get_event_count()`) — für eine künftige Debug-/
Status-Anzeige, ohne den kompletten Log-Ringpuffer durchsuchen zu müssen.
Bewusst **nicht persistiert** — Session-only, analog Chat (ADR-043); die
zugrundeliegenden Rohdaten (die einzelnen `log_trace()`-Aufrufe)
überleben dagegen in der Log-Datei, nur die Aggregation hier ist
transient.

Zwei automatische Beispiel-Events (`session_start` in `configure()`,
`session_end` mit `duration_sec` in `on_cleanup()`) sind bewusst mit
eingebaut, statt die neue Infrastruktur mit null tatsächlichen Aufrufern
auszuliefern.

**Kein Netzwerk-Upload/Endpunkt** — es gibt (noch) keinen
Telemetrie-Server im Projekt. Events landen ausschließlich lokal in der
bestehenden Log-Datei, filterbar/ingestierbar mit denselben Werkzeugen
wie der Rest des Logs (Loki/Datadog/ELK), sobald ein Upload-Pfad gebraucht
wird. Entsprechend auch **keine** `NetworkBridge`-Injektion in
`BootPipeline.gd`s Liste — im Unterschied zu `chat`/`report` braucht
`TelemetryService` kein Netzwerk.

## Optionen (verworfen)

- **Ein zweites, eigenständiges Datei-I/O-System für Telemetrie** (eigene
  Datei, eigener Schreib-Thread) — verworfen: reine Dopplung von etwas,
  das `AppLogger` bereits robust löst (Thread-Sicherheit, NDJSON,
  Batching). Der einzige echte Mehrwert eines eigenen Service ist die
  Zähler-Aggregation, nicht die Persistenz selbst.
- **Crash-Report als eigener `Service`** — verworfen, siehe "Warum in
  `AppLogger` selbst" oben: ein Service über die Registry existiert erst
  nach erfolgreichem Boot, ein früher Boot-Crash bräuchte den
  Report-Mechanismus aber schon vorher.
- **Telemetrie-Events auch bei `NOTIFICATION_WM_CLOSE_REQUEST` als
  zusätzlicher automatischer `app_closed`-Event** — verworfen für diese
  Runde: `session_end` in `TelemetryService.on_cleanup()` deckt den
  Normalfall bereits ab; ein zusätzlicher, redundanter Event direkt in
  `AppLogger._notification()` hätte die Trennung zwischen "AppLogger kennt
  keine Services" (siehe AutoLoad-#1-Prinzip) unnötig aufgeweicht.

## Konsequenzen

### Positiv
- Beide Hälften bauen auf bewährter, bereits gut getesteter Infrastruktur
  auf (`AppLogger` existiert seit vielen Runden) statt neue
  Fehlerquellen (Thread-Handling, Datei-I/O) einzuführen.
- Crash-Reports sind ab sofort für JEDEN künftigen `fatal()`-Aufruf und
  jeden echten Engine-Crash verfügbar — kein Nachrüsten pro Aufrufer
  nötig, da zentral in `AppLogger` verankert.
- `record_event()` ist so leichtgewichtig, dass es ohne Bedenken an vielen
  Stellen im Projekt ergänzt werden kann, sobald konkrete Events gewünscht
  sind (siehe "Bewusst nicht Teil dieser Runde").

### Negativ / Risiken
- `write_crash_report()` ist best-effort (Schreibfehler werden nur
  gewarnt) — in einer Umgebung ohne Schreibrechte auf Downloads UND
  `user://` ginge ein Crash-Report komplett verloren, es gäbe dann nur
  noch den (ebenfalls best-effort) regulären Log-Flush.
- Keine Deduplizierung/Rate-Limiting bei Telemetrie-Events — ein Aufrufer,
  der `record_event()` in einer engen Schleife aufruft, würde die Log-Datei
  fluten. Kein eingebauter Schutz in dieser Runde (siehe unten).

## Bewusst nicht Teil dieser Runde

- Kein Netzwerk-Upload/Telemetrie-Server (siehe "Entscheidung" oben).
- Kein Opt-out/Datenschutz-Einstellung — bislang rein lokal, kein
  Datenabfluss; sobald ein Upload-Pfad existiert, wird das relevant und
  muss dann nachgezogen werden.
- Kein Rate-Limiting/Deduplizierung in `record_event()` — Aufrufer müssen
  selbst verantwortungsvoll damit umgehen (kein Aufruf in Hot-Loops ohne
  eigene Drosselung).
- Kein Dashboard/UI für Telemetrie-Daten oder Crash-Reports, kein
  `UIContext`-Eintrag.
- Keine konkreten Gameplay-Telemetrie-Events über `session_start`/
  `session_end` hinaus — das ist bewusst den jeweiligen Feature-Services
  überlassen (z. B. könnte `AuctionHouseService` künftig
  `record_event("auction_listing_created", ...)` ergänzen), nicht Teil
  dieses Infrastruktur-ADRs.

**Ehrlich offen:** wie in jeder Runde seit 89 — kein Godot-Editor/
Headless-Runner in dieser Entwicklungsumgebung verfügbar, nur strukturell
geprüft. `write_crash_report()` wurde zwar mit echtem Datei-I/O getestet
(nicht nur die reine Datenkonstruktion), aber `fatal()`/
`NOTIFICATION_CRASH` selbst (die tatsächlichen Aufrufer) konnten aus
naheliegenden Gründen nicht end-to-end ausgelöst werden (`fatal()` beendet
den Prozess).
