> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-016: Domain-first Ordnerstruktur statt Layer-first

**Status:** Umgesetzt
**Datum:** 2026-07-04
**Kontext:** Betrifft die gesamte `scripts/`-Struktur. Ergänzt (löst nicht ab) das
Schichtenmodell aus `docs/architecture.md` Abschnitt 1 und die Suffix-Konventionen
Abschnitt 3.

---

## Problem

`scripts/services/` enthielt 18 Dateien aus sieben fachlich unabhängigen
Bereichen (Inventory, Quest, Skill, Combat, Save, Equipment, Networking) —
zusammengehalten nur durch das gemeinsame Suffix, nicht durch fachlichen
Zusammenhang. Wer an Quest arbeitete, änderte typischerweise
`QuestService.gd` (`scripts/services/`), `QuestPanelController.gd`
(`scripts/ui/controllers/`), `QuestDefinition.gd` (`scripts/quest/`) und
`QuestNPC.gd` (`scripts/world/npc/`) — vier Ordner für eine Änderungseinheit.

## Entscheidung

Der Ordnerbaum ist jetzt **domain-first**: `<domain>/<optionaler Layer-Unterordner>`,
z. B. `scripts/progression/quests/`, `scripts/progression/quests/ui/`,
`scripts/economy/inventory/`. Das bestehende Schichtenmodell
(Presentation → Entity → Service → Infrastructure) bleibt als
**Abhängigkeitsrichtungs-Regel** vollständig in Kraft — es ist nur kein
Ordner-Kriterium mehr, sondern ein Kommentar-/Lint-Kriterium.

Domänenlose Infrastruktur (kein fachlicher Bezug, wird von allen Domains
genutzt) bleibt eigener Top-Level-Ordner: `platform/`, `networking/`,
`eventbus/`, `logger/`, `persistence/`, `session/`, `debug/`, generisches
`ui/` (nur domänenlose Widgets wie Joystick, PauseMenu, ContextMenu).

**Neue Top-Level-Domains:** `entities/` (player, animals, npc, combat),
`economy/` (inventory, equipment, rewards), `progression/` (quests, skills),
`world/` (terrain, chunks, water, weather_time, objects, respawn, core),
`interaction/` (bleibt eigene Domain, cross-cutting Mechanismus).

## Konsequenzen

### Positiv
- Eine fachliche Änderung berührt i. d. R. einen Ordner, nicht vier.
- `docs/services.md`-Tabellen und Onboarding werden kürzer navigierbar.

### Negativ / Risiken
- `scripts/ci/lint_services_access.sh` (`SCOPED_DIRS`) und
  `scripts/ci/lint_servicenode.sh` (`JUSTIFIED_FILES`) mussten auf die neuen
  Pfade angepasst werden — beide wurden nach der Migration erneut ausgeführt
  und sind grün (0 Verletzungen).
- Ältere ADRs (002–015) und Audits referenzieren teils die alten Pfade
  (`scripts/core/`, `scripts/services/`, ...). Sie werden **nicht**
  rückwirkend umgeschrieben — sie sind Zeitdokumente. Bei Pfad-Verwirrung:
  dieser ADR sticht für "wo liegt was heute".
- `docs/architecture.md` Abschnitt 1 (Schichtendiagramm) beschreibt weiterhin
  korrekt die Abhängigkeitsrichtung, nennt aber keine Pfade — bleibt gültig.
- Ohne lokale Godot-Instanz bei dieser Migration nicht verifizierbar: ob
  Szenen im Editor sauber laden (Pfade in `.tscn`/`.tres` wurden per Skript
  ersetzt und stichprobenartig gegengeprüft, aber nicht in der Engine
  geöffnet). **Vor dem nächsten Commit: einmal in Godot öffnen und
  durchklicken.**

### Mitigationen
- Migration erfolgte Datei-für-Datei nach fester Zuordnungstabelle (kein
  Freihand-Verschieben), dokumentiert in dieser ADR-Historie.
- Beide CI-Lint-Guards laufen nach der Migration grün.
- 191 von 198 Skripten nutzen `class_name` (globale Registrierung) — Pfad-
  Änderungen betreffen daher primär `.tscn`/`.tres`-`ext_resource`-Einträge
  und `project.godot`-Autoloads, nicht Skript-zu-Skript-Referenzen.

## Ablösung

Leer — aktueller Stand.
