# 📑 WildGrove — Workflow, Debugging & Session-Protokoll

---

## 1. Standard Session-Start

Vor jeder Coding-Session:

1. **ZIP hochladen** — aktueller Stand aller `.gd` und `.md` Dateien
2. **Log aus letzter Session posten** — Terminal-Output oder `wildgrove.log`
3. **Status-Check:** Was wolltest du testen? Was ist fehlgeschlagen?
4. **Aktuelle TODOs aus `review.md` lesen** — Kontext wiederherstellen

---

## 2. Fehler-Report Protokoll

```
FEHLER: [Vollständiger Stack-Trace aus Terminal/Log]
KONTEXT: Was war das Ziel? (z.B. "Spieler sollte Item aufheben")
LETZTE ÄNDERUNG: Welche Datei wurde zuletzt geändert?
LOG-SNIPPET: Die 10 Zeilen vor dem Fehler aus wildgrove.log
```

**Was die KI dann tut:**
1. Alle relevanten Dateien anfordern (oder aus ZIP lesen)
2. Cross-Check gegen diese Principles
3. Fix liefern + `review.md` aktualisieren

---

## 3. Change-Impact-Analyse

Bevor eine Datei geändert wird:

| Datei | Betrifft |
|-------|---------|
| `BootstrapConfig.tres` | Boot-Reihenfolge, alle Services |
| `Services.gd` | Alle Stellen die `Services.xyz` aufrufen |
| `EventBus.gd` / `*Events.gd` | Alle Signal-Connections im Projekt |
| `Logger.gd` | Jede einzelne Log-Zeile im Projekt |
| `ServiceOrchestrator.gd` | Das komplette Boot-Verhalten |
| `SaveSystem.gd` | Alle Save-Provider |

---

## 4. Mandatory Log-Checks nach Änderung

Nach jeder Änderung im SimpleTerminal prüfen:

```
> status          → alle Services grün?
> errors          → neue Fehler?
> stats           → ERROR-Count gestiegen?
```

Im Log-File suchen:
```
╔══ BOOT START ══╗    → Boot hat begonnen
╚══ BOOT FERTIG  ══╝  → Boot erfolgreich (wie lange?)
[ERROR]               → Kritische Fehler
boot_failed           → Boot-Abbruch
```

---

## 5. Datei-Sync Protokoll

Die Markdown-Dateien sind **aktiver Teil des Projekts**, keine statische Doku.

| Event | Welche MD aktualisieren |
|-------|------------------------|
| Neuer Service | `services.md` + `architecture.md` |
| Bug gefunden+gehoben | `review.md` |
| Neue Architektur-Entscheidung | `architecture.md` |
| Neue Coding-Regel | `principles.md` |
| Neues Signal | `services.md` (EventBus-Sektion) |
| Neuer Terminal-Befehl | `architecture.md` (Debugging-Sektion) |

---

## 6. File-Naming & Pfad-Regeln

```
scripts/
  core/          → Boot-Infrastruktur (Orchestratoren, Registry, Factory, ...)
  debug/         → Developer-Tools (Logger, SimpleTerminal, Docs)
  events/        → EventBus-Namespaces (*Events.gd)
  interfaces/    → Interface-Definitionen (I*.gd)
  logger/        → Logger.gd
  player/        → Player-spezifische Scripts (Player.gd, PlayerMover.gd, ...)
  quest/         → Quest-Ressourcen (QuestDefinition.gd, ...)
  resources/     → Shared-Ressourcen (ItemDefinition.gd, ...)
  services/      → Service-Implementierungen (InventorySystem, SaveSystem, ...)
  ui/            → UI-Code (HUDManager, HUDBuilder, components/, controllers/, ...)
  world/         → Welt-Code (WorldService, WorldFactory, objects/, ...)
```

**Regel:** Service-Implementierungen die Entities in der Welt *verwalten* (`WorldService`)
gehören in `world/`, nicht in `services/`. Services die reine Logik sind
(`InventorySystem`) gehören in `services/`.

---

## 7. Multiplayer-Readiness Check

Bei jeder neuen Funktion fragen:

1. **Wer besitzt diese Daten?** (Client-Vorhersage vs. Server-Authorität)
2. **Kann ein manipulierter Client diese Funktion missbrauchen?**
3. **Ist das ein Request (Client→Server) oder eine Mutation (Server→alle)?**

```gdscript
# ❌ Unsicher — Client kann beliebig Gold setzen
func set_gold(amount: int) -> void:
    _gold = amount

# ✅ Request-Pattern — Server validiert
func request_gold_change(delta: int, source: String) -> void:
    if not _auth.is_server():
        EventBus.system.emit_gold_change_requested(delta, source)
        return
    # Server-Logik:
    if _validate_gold_change(delta, source):
        _gold = clampi(_gold + delta, 0, MAX_GOLD)
        EventBus.system.emit_gold_changed(_gold)
```

---

## 8. KI-Session Zusammenfassung Format

Am Ende jeder Session:
```
SESSION SUMMARY:
- Behoben: [Liste der Fixes]
- Neu: [Liste neuer Features/Files]
- Offen: [Was noch zu tun ist]
- Nächste Session: [Empfohlener nächster Schritt]
```
