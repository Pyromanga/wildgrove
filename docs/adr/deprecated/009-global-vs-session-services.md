> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-009: App-/Character-/World-Scope — Charakter- und Welt-Wechsel ohne App-Neustart

**Status:** Akzeptiert
**Datum:** 2026-06
**Kontext:** ServiceOrchestrator, BootPipeline, BootstrapConfig, SaveSystem, MainMenu, World.tscn

---

## Problem

Der `ServiceOrchestrator` bootet beim App-Start alle Services ein einziges Mal und reißt sie erst beim App-Exit wieder ab. Das ist für `SceneManager`, `DataService` oder `GameManager` korrekt — diese Services halten keinen Charakter-spezifischen State. Aber `InventorySystem`, `SkillSystem`, `QuestService`, `PlayerStateService`, `WorldService` u.a. laden ihre Daten aus dem Save-Slot des aktiven Charakters. Wenn man den Charakter wechseln möchte (über das Hauptmenü), müsste man derzeit die App neu starten.

Zusätzlich gibt es einen dritten Lebenszyklus: `WorldService` selbst ist charakter-gebunden (Save-Slot), aber die konkrete Welt-*Szene* (`World.tscn`, ihr Root-Node, der Mesh-Cache) hat einen eigenen, kürzeren Lebenszyklus innerhalb einer Session — sie entsteht erst wenn die 3D-Szene geladen ist, und muss beim Szenenwechsel (z.B. zurück ins Hauptmenü, ohne die Session zu beenden) unabhängig ab- und wieder aufgebaut werden können.

---

## Optionen

### Option A: App-Neustart bei Charakter-Wechsel
Charakter-Wechsel bedeutet vollständiger Neustart. Session-Daten per URL-Parameter oder Datei übergeben.
- ✅ Kein Infrastruktur-Overhead
- ❌ Inakzeptable UX für jedes Spiel mit Character-Select
- ❌ Godot Mobile unterstützt keinen App-Neustart als Game-Flow

### Option B: Zwei Registries — Global und Session
`BootstrapConfig.tres` deklariert `global_services` und `session_services` als getrennte Arrays. `ServiceOrchestrator` hält `_global_registry` (bootet in `_ready()`) und `_session_registry` (bootet bei Charakter-Wechsel, wird bei Abmeldung vollständig abgerissen).
- ✅ Explizite Trennung global vs. charakter-gebunden
- ❌ Kein eigener Lebenszyklus für die Welt-*Szene* selbst — `WorldService.on_world_scene_ready()`/Mesh-Cache-Aufbau müsste ad-hoc in den Session-Boot gequetscht werden, obwohl die Szene später und unabhängiger endet als die Session
- ❌ `ServiceOrchestrator` wird zum God Object: er hält zwei Registries *und* orchestriert ihre Teardown-Reihenfolge *und* kennt Boot-Details beider Ebenen

### Option C: Drei verschachtelte Scopes — App / Character / World (gewählt)
Drei eigenständige `RefCounted`-Klassen (`AppScope`, `CharacterScope`, `WorldScope`), jede mit eigener `ServiceRegistry` und eigenem Lebenszyklus. Jeder Scope kennt nur den Scope über sich, nie den unter sich:

```
AppScope        (App-Lifetime)
  └─ CharacterScope   (Charakter-Lifetime, erzeugt von AppScope)
       └─ WorldScope       (Welt-Szenen-Lifetime, erzeugt von CharacterScope)
```

Boot- und Teardown-Logik lebt vollständig in `BootPipeline` (`boot_app()`/`boot_character()`/`boot_world()` + passende `teardown_*()`-Methoden), nicht in den Scopes selbst und nicht im `ServiceOrchestrator`. `BootstrapConfig.tres` behält die zwei Service-Definitionslisten `global_services` (→ `AppScope`) und `session_services` (→ `CharacterScope`) — `WorldScope` bekommt keine eigene Definitionsliste, weil World keine neuen `ServiceDefinition`-Services bootet, sondern den bereits existierenden `WorldService` aus der Character-Registry mit der geladenen 3D-Szene verdrahtet (`on_world_scene_ready()`, `warmup_mesh_cache()`).

- ✅ Explizite, dokumentierte Trennung: App-, Charakter- und Welt-Szenen-Lifetime sind drei verschiedene Dinge, nicht zwei
- ✅ `ServiceOrchestrator` ist eine dünne Lifecycle-Shell (`_ready()`, Signal-Handler) — keine Boot-Logik, keine Registry-Verwaltung
- ✅ Jeder Scope kennt nur nach oben, nie nach unten (`AppScope` kennt `CharacterScope` nicht direkt — er erzeugt ihn und lässt ihn dann laufen), Cross-Scope-Zugriff nach unten läuft explizit über `get_character_service()`/`get_app_service()` auf `WorldScope`
- ✅ `teardown_all()` läuft die drei Scopes in der richtigen Reihenfolge ab (World → Character → App) ohne dass der Orchestrator das wissen muss
- ✅ Session-Services können in `configure(deps)` auf Global-Services zeigen (SaveSystem, DataService) — `CharacterScope.app_registry` als Fallback-Registry
- ✅ `SaveSystem` bleibt global → `list_local_saves()` im Hauptmenü ohne aktive Session nutzbar

---

## Entscheidung

**Option C.** Drei verschachtelte Scopes, jeder mit eigener `ServiceRegistry`.

**App-Scope** (`AppScope`, app-lifetime, `global_services` in BootstrapConfig):
`ticker`, `scenemanager`, `data`, `savesystem`, `gamemanager`, `session_manager` — keine Charakter-spezifischen State, laufen von `_ready()` bis App-Exit.

**Character-Scope** (`CharacterScope`, charakter-lifetime, `session_services` in BootstrapConfig):
`playerstates`, `stat_modifiers`, `combat`, `equipment`, `skill_system`, `inventory`, `network_bridge`, `reward_dispatcher`, `interaction_executor`, `gamesave`, `world_gen`, `world`, `respawn`, `quest` — laden ihre Daten aus dem Save-Slot des aktiven Charakters, werden bei Charakter-Wechsel vollständig neu gebootet.

**World-Scope** (`WorldScope`, welt-szenen-lifetime, kein eigenes Service-Definitionsset):
Kein neuer Service wird hier instanziiert. `BootPipeline.boot_world()` holt den bereits laufenden `WorldService` aus der Character-Registry, verdrahtet ihn mit dem `World.tscn`-Root-Node (`on_world_scene_ready()`) und baut den Mesh-Cache auf (`warmup_mesh_cache()`). Getriggert nicht durch Pull, sondern durch ein Signal von `WorldScopeInitializer`, sobald die Szene im SceneTree bereit ist.

**Boot-Flow:**
1. App-Start → `ServiceOrchestrator._ready()` → `_pipeline.boot_app(_app_scope, self)` → `GameManager.start_game()` → State: MAIN_MENU
2. Spieler wählt Charakter → `EventBus.system.session_requested(player_id)` → `ServiceOrchestrator._on_session_requested()`:
   - `_app_scope.create_character_scope(player_id, self)`
   - `_pipeline.boot_character(char_scope, self)`: `SaveSystem.begin_session(player_id)` lädt den Save, Character-Services booten mit Zugriff auf App-Services als Deps, HUD wird verdrahtet (`_wire_hud()`)
3. `World.tscn` wird geladen → `WorldScopeInitializer` signalisiert Bereitschaft → `ServiceOrchestrator._on_world_initializer_ready()`:
   - `char_scope.create_world_scope(world_root, self)`
   - `_pipeline.boot_world(world_scope, self)`

**Teardown-Flow:**
- `GameManager.change_state(MAIN_MENU)` während aktiver Session → `ServiceOrchestrator._on_state_changed()` → `_app_scope.destroy_character_scope()`
- `AppScope.destroy_character_scope()` → `CharacterScope.destroy()` → zerstört zuerst einen aktiven `WorldScope` (falls vorhanden), dann sich selbst über `BootPipeline.teardown_character()`/`teardown_world()`
- `App-Exit` (`NOTIFICATION_WM_CLOSE_REQUEST`/`NOTIFICATION_CRASH`) → `_pipeline.teardown_all(_app_scope)` läuft World → Character → App in dieser Reihenfolge ab

---

## Konsequenzen

### Positiv
- Charakter-Wechsel ist ein vollständig unterstützter Game-Flow, keine App-Restart-Anforderung
- Welt-Szenen-Wechsel (z.B. zurück ins Hauptmenü ohne Logout) hat einen eigenen, unabhängigen Lifecycle statt in den Session-Boot gequetscht zu werden
- Session- und Welt-Services sind nach Teardown vollständig bereinigt — keine stale References
- `SaveSystem` als App-Service: `list_local_saves()` und `has_save_for()` sind immer nutzbar, unabhängig von einer aktiven Session
- `ServiceOrchestrator` bleibt eine dünne Shell — Boot-/Teardown-Logik ist testbar in `BootPipeline`, unabhängig vom SceneTree-Lifecycle

### Negativ / Risiken
- Drei Scope-Klassen statt zwei Registry-Felder — etwas mehr Indirektion beim Nachvollziehen, welcher Service in welchem Scope lebt
- Contributor-Entscheidung bei neuen Services: App, Character, oder gehört es eigentlich zum World-Scope-Wiring? → CONTRIBUTING.md dokumentiert den Entscheidungsbaum
- Services die irrtümlich als App-Service definiert werden: kein Charakter-Wechsel mehr ohne Workaround → Code-Review muss diesen Aspekt prüfen

### Mitigationen
- `BootstrapConfig.tres` ist weiterhin die Single Source of Truth für App- vs. Character-Zuordnung: `global_services` vs. `session_services`, explizit in einer Datei sichtbar
- Kommentar-Block über beiden Arrays in `BootstrapConfig.gd` erklärt die Unterscheidung
- CONTRIBUTING.md: Entscheidungsbaum — „Hält dieser Service Charakter-spezifischen State oder lädt er Daten aus dem Save?" → ja = Character-Scope, nein = App-Scope. World-Scope ist kein Ziel für neue `ServiceDefinition`-Einträge, sondern ausschließlich für Szenen-Wiring bestehender Character-Services.

---

## Ablösung

Dieser ADR wird durch einen Account-ADR abgelöst wenn ein Server-seitiges Account-System implementiert wird. Zu diesem Zeitpunkt:
- `create_character_scope(player_id, parent)` bekommt einen Token-Parameter vom Server statt einer lokalen Player-ID
- Character-Teardown informiert ggf. den Server
- Der Drei-Scope-Split (App/Character/World) bleibt bestehen; nur der Auth-Flow beim Character-Boot ändert sich
