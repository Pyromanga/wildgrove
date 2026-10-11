> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-005: ISaveProvider-Interface statt zentraler Save-Logik

**Status:** Akzeptiert  
**Datum:** 2026-06  
**Kontext:** SaveSystem, alle save-relevanten Services

---

## Problem

Mehrere Services haben persistenten State (Inventar, Skills, Quests, World-State). Die Frage ist: wer ist verantwortlich für das Serialisieren dieses States?

---

## Optionen

### Option A: SaveSystem kennt alle Services explizit
`SaveSystem.save()` fragt `Services.inventory`, `Services.skill_system`, etc. direkt ab.
- ✅ Zentralisiert, einfach zu debuggen  
- ❌ SaveSystem muss bei jedem neuen save-relevanten Service geändert werden  
- ❌ Harte Kopplung — SaveSystem kennt jeden einzelnen Service  
- ❌ Reihenfolge und Vollständigkeit sind implizit

### Option B: Jeder Service schreibt selbst auf Disk
`InventorySystem.save()` öffnet seine eigene Datei.
- ✅ Vollständige Autonomie  
- ❌ Kein atomares Save mehr — Spielstand ist nach einem Crash inkonsistent  
- ❌ Kein zentrales Migration-System möglich

### Option C: Provider-Pattern — Service registriert sich beim SaveSystem (gewählt)
`ISaveProvider`-Interface: `get_save_key()` + `get_save_data()`.  
SaveSystem sammelt von allen registrierten Providern und schreibt atomar als ein Blob.

---

## Entscheidung

**Option C.** Jeder save-relevante Service implementiert `ISaveProvider` und registriert sich in `configure()` beim SaveSystem. SaveSystem ist ein dummer Aggregator — er weiß nicht *was* gespeichert wird, nur *dass* jeder Provider gefragt werden muss.

---

## Konsequenzen

### Positiv
- Neuer save-relevanter Service = zwei Methoden implementieren + eine Zeile in `configure()` — kein Änderung am SaveSystem
- SaveMigrationService kann alle Provider-Daten zentral migrieren
- Interface erzwingt zur Compile-Zeit korrekte Implementierung (statt Duck-Typing)

### Negativ / Risiken
- SaveSystem schreibt aktuell alles in eine einzige JSON-Datei — kein Slot-System, kein partielles Save
- Kein Atomic Write (Crash während `file.store_string()` = korrupter Spielstand)

### Bekannter Tech Debt
- **Atomic Write** fehlt: schreibe in `savegame.tmp`, dann atomares Rename zu `savegame.json`
- **Rotating Backup** fehlt: `savegame.bak` als Fallback bei Korruption
- **Save-Slots** fehlen: `SaveSystem.save_slot(slot_id)` statt einem einzigen `savegame.json`
- **Partielles Save** fehlt: `save_partial(["inventory", "skills"])` für Server-seitige Systeme

Diese Erweiterungen sind abwärtskompatibel — das Provider-Pattern bleibt unverändert.

---

# ADR-006: EntityContext-Injection statt direktem Services-Zugriff in Entities

**Status:** Akzeptiert  
**Datum:** 2026-06  
**Kontext:** Alle World-Entities (OakTree, IronOre, EnemyNPC, AnimalBase, QuestNPC, ...)

---

## Problem

Entities brauchen Services (Inventory für Loot, SkillSystem für XP, etc.). Die naive Lösung — ein globaler Service-Locator-Zugriff direkt aus der Entity — verletzt die Schichtentrennung und macht Entities in Tests von einem globalen State-Container abhängig.

---

## Optionen

### Option A: Entities rufen einen globalen Service-Locator direkt auf
- ✅ Einfach, null Infrastruktur  
- ❌ Entities kennen den globalen Container — Schichtverletzung  
- ❌ Tests für Entities erfordern den echten Container  
- ❌ Jede Entity ist implizit von jeder Service-Änderung betroffen

### Option B: Services werden als Konstruktor-Parameter übergeben
- ✅ Explizit  
- ❌ Entities werden via SceneTree instantiiert — keine Konstruktor-Injection möglich (GDScript `_init()` hat zu diesem Zeitpunkt keinen SceneTree-Zugriff)

### Option C: EntityContext als schmale Service-Fassade via on_spawn() (gewählt)
`EntityOrchestrator.spawn_entity()` injiziert `EntityContext.from_services()` in jeden `on_spawn(config, ctx)`-Aufruf. EntityContext ist eine schmale Wrapper-Klasse die nur die Services exponiert die Entities tatsächlich brauchen.

Für Tests: `EntityContext.for_test()` liefert eine Instanz mit Mock-Objekten — keine globalen AutoLoads nötig.

---

## Entscheidung

**Option C.** EntityContext als verpflichtetes Injection-Pattern für alle Entities.

**Interface (Auszug, siehe `IEntityContext.gd` für die vollständige Liste):**
```gdscript
# IEntityContext.gd
func get_inventory() -> InventorySystem
func get_skill_system() -> SkillSystem
func get_combat_system() -> CombatSystem
func get_event_bus() -> IEventBus
# ... nur was Entities tatsächlich brauchen
```

**Entity-Konvention:**
```gdscript
func on_spawn(config: Dictionary, ctx: IEntityContext) -> void:
    _ctx = ctx  # gespeichert, kein globaler Service-Zugriff
    _ctx.get_inventory().request_add_item(...)  # korrekt
```

---

## Konsequenzen

### Positiv
- Entities sind testbar ohne globalen State
- Klare Grenze: was Entities von Services brauchen, ist in `IEntityContext` sichtbar
- `EntityContext.for_test()` ermöglicht schnelle Unit-Tests für Entities

### Negativ / Risiken
- `on_spawn(config, ctx)` Signatur ist verbindlich — bestehende Entities ohne diesen Aufruf müssen migriert werden
