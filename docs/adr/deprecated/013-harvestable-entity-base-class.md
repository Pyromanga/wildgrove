> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-013: HarvestableEntity als Basisklasse für abbaubare Welt-Objekte

**Status:** Akzeptiert  
**Datum:** 2026-06  
**Kontext:** `scripts/world/objects/` — OakTree, IronOre und alle zukünftigen Ressourcen-Typen

---

## Problem

`OakTree.gd` und `IronOre.gd` waren strukturell identisch: gleiche Variablen (`_interactable_comp`, `_ctx`), gleiche Methoden-Signaturen (`on_spawn`, `on_despawn`, `_on_interacted`, `_setup_interactable`, `_setup_visuals`), gleiche EntityOrchestrator-Konvention. Der einzige Unterschied war der Interactable-Data-Block und das Visual-Mesh.

Mit `LogMaple`, `LogWillow`, `CopperOre` bereits in `DataManifest` war absehbar dass ein dritter, vierter, fünfter Typ dazukommt — ohne Basisklasse wäre jeder Bug im Lifecycle-Code mehrfach zu fixen gewesen.

---

## Entscheidung

`HarvestableEntity` als gemeinsame Basisklasse (`extends Node3D`). Subklassen implementieren drei Methoden:

```gdscript
func _get_entity_type_id() -> String       # EntityRegistry-Key
func _build_interactable_data() -> InteractableData  # Typ-spezifisch
func _build_visuals() -> void              # Typ-spezifische 3D-Darstellung
```

Die Basisklasse übernimmt: `_ready()`, `on_spawn()`, `on_despawn()`, `_setup_interactable()`, `_on_interacted()`, Harvest-State via `WorldService.mark_harvested(type_id, pos)`.

Neue Typen: nur Subklasse anlegen + in `WorldEntityRegistry.register_all()` eintragen. Kein Lifecycle-Code mehr kopieren.

---

## Konsequenzen

### Positiv
- OakTree, IronOre, WillowTree, MapleTree, CopperOre teilen sich denselben Lifecycle-Code
- Bugs in `on_despawn` oder `_setup_interactable` werden einmal gefixt, gelten für alle
- Neuer Typ: ~20 Zeilen statt ~120

### Negativ / Risiken
- Subklassen können `_ready()` und `on_spawn()` nicht mehr frei überschreiben — Erweiterungspunkt via `_on_spawn_extended(config)` Hook falls nötig
- `_build_visuals()` hat Zugriff auf `_ctx` — Subklassen müssen wissen dass `_ctx` zur Aufrufzeit bereits gesetzt ist (Dokumentiert in Basisklasse)

### Mitigationen
- `push_error()` in allen drei abstrakten Methoden — fehlende Implementierung ist zur Laufzeit sofort sichtbar
- `_on_spawn_extended()` Hook für Sonderfälle
