# WildGrove — Workflow & Session-Protokoll

> **Vorgänger:** `scripts/debug/workflow.md` — diese Datei ersetzt sie  
> **Zweck:** Reproduzierbarer Workflow für AI-assisted Development ohne Live-Editor

---

## 1. Standard Session-Start

Vor jeder Coding-Session:

1. **ZIP hochladen** — aktueller Stand aller `.gd`, `.tres`, `.md` Dateien
2. **Log aus letzter Session posten** — Terminal-Output oder `wildgrove.log`
3. **Status nennen:** Was war das Ziel? Was ist fehlgeschlagen? Was wurde zuletzt geändert?
4. **`docs/review.md` lesen** — aktuelle offene Findings und Prioritäten

Der AI-Assistent liest zuerst `docs/architecture.md`, `docs/principles.md` und alle relevanten Service-Dateien, bevor er Code schreibt.

---

## 2. Fehler-Report Protokoll

Vollständige Information beim ersten Post — kein mehrstufiges Nachfragen:

```
FEHLER:       [Vollständiger Stack-Trace aus Terminal/Log]
ZIEL:         Was sollte passieren? ("Spieler sollte Item aufheben")
LETZTE ÄNDERUNG: Welche Datei wurde zuletzt geändert?
LOG-SNIPPET:  Die 20 Zeilen vor dem Fehler aus wildgrove.log
BOOT-STATUS:  War ╚══ BOOT FERTIG ══╝ im Log sichtbar?
```

**Was der AI-Assistent dann tut:**
1. Alle relevanten Dateien aus ZIP lesen
2. Cross-Check gegen `docs/principles.md` und `docs/architecture.md`
3. Fix liefern + betroffene Docs aktualisieren

---

## 3. Mandatory Log-Checks nach jeder Änderung

Im SimpleTerminal:
```
> status          → alle Services grün?
> errors          → neue Fehler seit letztem Check?
> stats           → ERROR-Count im Vergleich?
```

Im Log-File suchen:
```
╔══ BOOT START ══╗     → Boot hat begonnen
╚══ BOOT FERTIG  ══╝   → Boot erfolgreich + Dauer
[ERROR]                → Kritische Fehler → sofort untersuchen
boot_failed            → Boot-Abbruch → Phase und Reason lesen
```

---

## 4. Change-Impact vor jeder Änderung

Vor dem Schreiben: "Was ist die Auswirkung dieser Änderung?"

| Datei | Auswirkung |
|-------|-----------|
| `BootstrapConfig.tres` | Boot-Reihenfolge + alle Service-Instanziierungen |
| `Services.gd` | Alle `Services.xyz`-Aufrufe im Projekt |
| `EventBus.gd` / `*Events.gd` | Alle Signal-Connections |
| `Logger.gd` | Jede einzelne Log-Zeile |
| `ServiceOrchestrator.gd` | Komplettes Boot-Verhalten |
| `SaveSystem.gd` | Alle Save-Provider + gespeicherte Spielstände |
| `SaveMigrationService.gd` | Alle gespeicherten Spielstände |
| `EntityContext.gd` | Alle Entities mit `on_spawn(config, ctx)` |

---

## 5. Neue Datei anlegen — Ablauf

```
1. Suffix wählen       → CONTRIBUTING.md Abschnitt 3.3
2. Basisklasse wählen  → Node wenn SceneTree nötig, RefCounted sonst
3. Ordner prüfen       → docs/architecture.md Abschnitt 4 (Ordnerstruktur)
4. LOG_CAT definieren  → const LOG_CAT := "ClassName"
5. Lifecycle impl.     → configure(), on_ready(), on_cleanup() (auch wenn leer)
6. Docs aktualisieren  → docs/services.md bei Service/Signal
7. Checkliste          → CONTRIBUTING.md Abschnitt 2 durchgehen
```

---

## 6. Docs-Sync Protokoll

Die Markdown-Dateien sind aktiver Teil des Projekts:

| Event | Welche Docs aktualisieren |
|-------|--------------------------|
| Neuer Service | `docs/services.md` (Service-Tabelle) + `BootstrapConfig.tres` |
| Neues Signal | `docs/services.md` (EventBus-Sektion) |
| Neuer Save-Provider | `docs/services.md` (Save-Provider-Tabelle) |
| Bug gefunden + gehoben | `docs/review.md` (Finding mit Status ✅) |
| Architektur-Entscheidung | `docs/adr/NNN-titel.md` anlegen + `docs/adr/000-index.md` aktualisieren |
| Neue Coding-Regel | `docs/principles.md` |
| Neuer Tech Debt | `docs/review.md` + `docs/architecture.md` Abschnitt 9 |

**Faustregel:** Wenn du Code schreibst und einen Kommentar schreibst der erklärt *warum* du es so machst → das gehört als ADR oder in `principles.md`, nicht als Inline-Kommentar.

---

## 7. Session Summary Format

Am Ende jeder Session im Commit-Message oder als Post:

```
SESSION v[X] SUMMARY
────────────────────
BEHOBEN:
  - [C-XX] Kurzbeschreibung des Fixes
  - [A-XX] Kurzbeschreibung des Fixes

NEU:
  - FeatureName: was wurde implementiert
  - docs/adr/NNN-titel.md angelegt

OFFEN:
  - [A-XX] Was noch zu tun ist
  - [A-XX] Was noch zu tun ist

NÄCHSTE SESSION:
  - Empfohlener erster Schritt
  - Empfohlener zweiter Schritt
```

---

## 8. Multiplayer-Readiness Check (Quick)

Bei jeder neuen Funktion die State ändert, drei Fragen:

1. Darf ein Client das direkt auslösen? → wenn nein: `request_`-Pattern
2. Kann ein manipulierter Client den Wert auf etwas Ungültiges setzen? → Validation im `on_*_confirmed`
3. Würde der Server dasselbe tun wenn er diese Funktion aufruft? → wenn ja: korrekt

```gdscript
## AUTHORITY: server | client
## CHEAT-RISK: hoch | mittel | keines
```

Dieser Kommentar-Block ist Pflicht für neue State-Mutationen in server-autoritativen Systemen.

---

## 9. CI/CD Pipeline — GitHub Actions

Die Pipeline liegt in `.github/workflows/build-android.yml` und hat drei Jobs.

**Trigger:** Push/PR auf `main`/`develop` wenn die Commit-Message das Wort `App` enthält, oder manueller Start via `workflow_dispatch` in der GitHub-UI.

**Job 1 — `resolve-source`:** Prüft ob `zip/game.zip` im Repo existiert. Wenn ja: entpackt es und sucht `project.godot`. Wenn nein: nutzt das Repo-Root direkt. Das aufgelöste Projekt wird als GitHub-Artefakt `resolved-project` weitergegeben — beide folgenden Jobs laden es herunter.

**Job 2 — `test-logic`:** Läuft parallel zum Build. Installiert GUT v9.3.0, lädt Godot herunter, führt `gdformat --check` aus und startet GUT mit `-gdir=res://tests`. Ergebnis wird als JUnit-Report publiziert.

> **Aktueller Stand:** Der `test-logic`-Job ist in der Pipeline vorhanden, aber `res://tests/` enthält nur `IntegrationTest.gd` (extends Node, kein echtes GUT). Die Pipeline läuft durch (`|| true` fängt den Exit-Code ab), produziert aber kein `results.xml`. → Tech Debt TD-12.

**Job 3 — `build-android`:** Installiert Java 17, Android SDK, NDK 23.2, lädt Godot + Export-Templates. Generiert ein Debug-Keystore, erstellt `export_presets.cfg` wenn keins existiert, setzt den Version-Code aus der Git-Commit-Anzahl, und exportiert das APK. Das APK wird als Artefakt `WildGrove-debug-APK` (14 Tage) hochgeladen.

**Job 4 — `release`:** Läuft nur bei Tag-Push (`refs/tags/v*`). Erstellt einen GitHub Release mit dem APK als Anhang.

### Neuen Test hinzufügen

1. Datei in `res://tests/test_*.gd` anlegen (GUT-Konvention: Prefix `test_`)
2. `extends GutTest` (nach GUT-Installation: `extends "res://addons/gut/test.gd"`)
3. Methoden mit `test_`-Prefix — GUT erkennt sie automatisch
4. Commit-Message mit `App` → Pipeline läuft automatisch

### Manueller Pipeline-Start

GitHub → Repository → Actions → "Build Android APK" → "Run workflow" → Branch wählen → Start. Kein Commit nötig, kein `App`-Keyword nötig.

### APK herunterladen

Nach erfolgreichem Build: Actions → letzter Run → Artifacts → `WildGrove-debug-APK`.
