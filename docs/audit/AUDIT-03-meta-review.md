# AUDIT-03 — Meta-Review (Round 14 / Current State)

**Scope:** Vollständige Codebasis, round14-ZIP  
**Methode:** Code ist Wahrheit. Jeder Befund zitiert Datei + Symptom.  
**Datum:** 2026-06  

---

## Legende

| Symbol | Bedeutung |
|--------|-----------|
| 🔴 P0 | Datenverlust / Crash in Release / Security |
| 🟠 P1 | Stille Fehler / Contract-Verletzung / falsche Architektur |
| 🟡 P2 | Fehlende Tests / unfertige Muster / Tech Debt mit Regressionsrisiko |
| 🔵 P3 | Naming / Docs / Minor |
| ✅ | Erledigt |

---

## Status: Erledigte P0s

Alle P0s aus früheren Rounds sind behoben:

- **A-01** ✅ EquipmentService Save-Failure (5 Bugs, Round 1)
- **A-02** ✅ SaveSystem kein .bak-Recovery (Round 1)
- **C-01** ✅ `roll_critical()` assert tot in Release (Round 1)

---

## SEKTION I — Unfertige Muster ("angefangen aber nicht fertig")

Das sind die ehrlichsten Probleme: Die Architektur ist korrekt entworfen, aber an mindestens einer Stelle fehlt der letzte Schritt. Solche Halbfertigkeiten sind gefährlicher als fehlendes Feature, weil sie Sicherheit suggerieren die nicht existiert.

---

### I-01 ✅ — `request_/on_*_confirmed` Pattern: Zwei Implementierungsstile koexistieren

**Behoben in Round 15.**

`_on_quest_start_confirmed(payload: Dictionary)` und `_on_quest_complete_confirmed()` in `QuestService` sowie `_on_xp_add_confirmed()` in `SkillSystem` sind jetzt vollständig public mit typisierten Parametern:

- `QuestService.on_quest_start_confirmed(quest_id: String, player_id: int = 1)` — public, Authority Guard eingebaut
- `QuestService.on_quest_complete_confirmed(quest_id: String, player_id: int = 1)` — public, Authority Guard eingebaut
- `SkillSystem.on_xp_add_confirmed(skill_name: String, amount: int, player_id: int = 1)` — public, Authority Guard eingebaut

Die `receive_*_from_network()`-Wrapper-Schicht ist vollständig entfernt. `NetworkBridge._rpc_*()` und `send_*()` rufen direkt `on_*_confirmed()` auf — exakt wie `InventorySystem` und `EquipmentService` (nun konsistent über alle 4 Services).

`test_network_bridge_contract.gd` vollständig neu geschrieben: prüft jetzt `on_*_confirmed()`-Sichtbarkeit, State-Äquivalenz zu `request_*()`, player_id-Routing, Tier-1-Routing via Bridge, und explizit dass die alten `receive_*`-Wrapper entfernt sind.

**Problem:**  
ADR-004 definiert `on_*_confirmed()` als die kanonische Server-Handler-Methode — public, direkt aufrufbar via RPC. In der Praxis gibt es zwei Stile:

- `InventorySystem` und `EquipmentService`: korrekt — `on_item_add_confirmed()` / `on_equip_confirmed()` sind **public** und direkt in `NetworkBridge` verdrahtet.
- `QuestService` und `SkillSystem`: falsch — die eigentliche Mutation liegt in **privaten** `_on_quest_start_confirmed(payload: Dictionary)` / `_on_xp_add_confirmed(payload: Dictionary)`. Die public-Seite (`receive_start_quest_from_network()`) ist ein extra Wrapper-Layer der auf dieses private Dict-Interface weiterleitet.

Das ist ein Problem wenn RPC kommt: `NetworkBridge._rpc_quest_start()` soll `_on_quest_start_confirmed()` aufrufen — aber das ist private. Der Wrapper `receive_start_quest_from_network()` hat eine andere Signatur als erwartet und ein Dictionary-Interface statt typed Parameters.

**Wo:** `scripts/services/QuestService.gd:196`, `scripts/services/SkillSystem.gd:134`

**Fix:** `_on_*_confirmed(payload: Dictionary)` auflösen. Die Handler direkt als `on_*_confirmed(typed, params)` exposen — wie in `InventorySystem` / `EquipmentService`. `receive_*_from_network()` wird dann zum Thin Authority-Guard + Delegat, nicht zu einer Wrapper-API.

---

### I-02 ✅ — EventBus: Injectable IEventBus in Services, aber Singleton-Zugriff in UI

**Behoben in Round 16.**

`IUIContext` hat jetzt einen fünften Accessor neben `get_quest()`/`get_skill_system()`/`get_inventory()`/`get_equipment()`/`get_data()`:

- `IUIContext.bus() -> IEventBus` — Basis-Vertrag gibt `null` zurück, exakt wie die anderen Getter.
- `UIContext.from_registry()` löst ihn aus `registry.get_service(ServiceKeys.EVENT_BUS)` auf — demselben Registry-Key, den Services via `deps.require(EVENT_BUS)` nutzen. Kein zweiter Adapter.
- `UIContext.for_test()` lässt `_bus` wie alle anderen Felder `null`, bis ein Test `ctx._bus = MockEventBus.new()` setzt (gleiche Konvention wie `EntityContext.for_test()`).

Alle 10 betroffenen Controller (`ContextButtonController`, `ContextMenuController`, `EquipmentUIController`, `FloatingTextController`, `InteractionButtonController`, `NotificationController`, `PauseMenuController`, `PlayerHPController`, `QuestPanelController`, `SkillPanelController`) nehmen jetzt ausschließlich `ctx: IUIContext` entgegen und lesen Events über `_ctx.bus().<namespace>()`. Wo zuvor ein roher Namespace-Parameter (`UIEvents`, `PlayerEvents`, untypisiertes `Object`) daneben existierte, ist er entfernt — ein Injektionspunkt statt zwei. `HUDBuilder.build_all()` und 7 `*Component.build()`-Fabriken geben `ctx` jetzt entsprechend weiter.

Architektur-Entscheidung in [ADR-012](../adr/012-ui-eventbus-injection.md) dokumentiert (schließt die UI-Hälfte von H-07/ADR-011 ab). Neuer Review-Blocker in `CONTRIBUTING.md` 2.1 + 7.8.

**Bewusst unverändert (kein I-02-Befund):**
- `InteractionComponent`/`JoystickComponent`/`InteractionUIController`/`InventoryUIController`/`JumpButtonComponent`/`JoystickController` — nehmen Events bereits als injizierten Parameter entgegen, kein `EventBus.*` im Controller-Code selbst.
- `HUDManager.gd`/`HUDBuilder.gd` (eigener Lifecycle, siehe II-03), `World.gd`, `scripts/ui/MainMenuController.gd` (liegt außerhalb `scripts/ui/controllers/`, kein Session-Registry-Zugriff vor Boot) — gleiches Muster, aber außerhalb des Scopes dieses Fixes.
- `IEntityContext.get_event_bus() -> Node: return EventBus` — strukturell verwandter, aber separater Befund: unbenutzt im Produktionscode, `Node`-Rückgabetyp verhindert echtes Mocking trotz Docstring-Behauptung der Testbarkeit. Nicht in diesem Round behoben — siehe Empfehlung für neuen P2-Befund unten.

`tests/unit/test_ui_context.gd` (neu, 8 Tests) deckt `bus()` auf Interface- und Produktions-Ebene ab. `test_notification_controller.gd`, `test_player_hp_controller.gd`, `test_skill_panel_controller.gd` (je neu, 3-4 Tests) beweisen den Mechanismus für die drei strukturellen Fälle (RefCounted-neu, Node-neu, Node-bereits-ctx) inklusive des Gegenbeweises, dass der echte `EventBus`-AutoLoad die Controller nicht mehr erreicht. Volle Testabdeckung für die übrigen 7 Controller bleibt IV-03 (separat, unverändert offen).

**Problem (historisch):**  
H-07 (ADR-011) war bewusst out-of-scope: Services injizieren `IEventBus` korrekt via `deps.require(ServiceKeys.EVENT_BUS)`. Aber alle UI-Controller griffen direkt auf den AutoLoad-Singleton `EventBus.ui.*` / `EventBus.player.*` zu:

```gdscript
# scripts/ui/controllers/SkillPanelController.gd:11
EventBus.player.xp_gained.connect(_on_xp_gained)

# scripts/ui/controllers/EquipmentUIController.gd:338
EventBus.ui.emit_floating_text("...")
```

Das bedeutet: UI-Controller waren nicht isoliert testbar. Ein Test der `SkillPanelController` prüfen will musste den echten `EventBus`-AutoLoad im SceneTree haben. Die Services konnten gegen `IEventBus`-Mocks getestet werden — die UI nicht.

Für ein Enterprise-Projekt auf 20-Jahr-Horizont war das die Hälfte der Wahrheit: der schwierigere Teil (Service-DI) war gelöst, der einfachere (UI-DI) war stehen geblieben.

**War:** Alle `scripts/ui/controllers/*.gd` — ~10 Dateien, ~30 direkte `EventBus.*`-Aufrufe

---

### I-02b ✅ P2 — `IEntityContext.get_event_bus()` → IEventBus (Round 18)

**Problem:**  
`IEntityContext.get_event_bus() -> Node: return EventBus` hat denselben Anspruch wie `IUIContext.bus()` ("explizit für Testbarkeit, Mock-EventBus möglich" laut Docstring), löst ihn aber nicht ein: Rückgabetyp ist `Node`, nicht `IEventBus` — ein `MockEventBus` (`extends RefCounted`) ist damit nicht typkompatibel ohne den Vertrag zu brechen. `EntityContext` überschreibt die Methode nicht; `grep` zeigt keinen einzigen Aufrufer im Produktionscode außerhalb des einen Tests, der nur bestätigt dass die Basis-Implementierung den AutoLoad zurückgibt (`test_entity_context.gd:112`).

**Wo:** `scripts/interfaces/core/IEntityContext.gd:38`

**Fix (Vorschlag, nicht Teil von I-02):** Entweder Rückgabetyp auf `IEventBus` ändern und `EntityContext` analog zu `UIContext.bus()` verdrahten (falls ein Entity-Anwendungsfall dafür entsteht), oder die Methode entfernen falls sie dauerhaft unbenutzt bleibt. Klein genug für einen eigenen Single-Bug-Round.

---

### I-03 ✅ P1 — Status-Effekte: Infrastruktur verdrahtet (Round 17)

**Problem (historisch):**  
`CombatSystem` hatte vollständige Status-Effekt-Infrastruktur (`apply_poison()`, `apply_burn()`, `_active_effects`, `on_tick()`), aber kein Weapon, kein Skill, keine Enemy-Attack rief sie auf. `PoisonDagger.tres` existierte als Item-Definition — der Code, der beim Treffer Gift-Stacks anwendet, fehlte.

**Fix (Round 17):**
- `apply_weapon_on_hit()` in `CombatSystem.gd` — war bereits vorhanden und in `EnemyNPC._on_interacted()` eingehängt, aber nur für POISON hardcodiert.
- `apply_weapon_on_hit()` jetzt als `match` auf `weapon.on_hit_effect` (StatusEffect.Kind): POISON, BURN, unbekannte Werte mit Log-Warn. Kein hardcoded `apply_poison()` mehr.
- `test_equipment_ui.gd` vollständig überarbeitet: `MockEventBus` in `before_each()` injiziert (verhindert `_bus.ui()` Crash im Positiv-Pfad); 5 neue Tests für `apply_weapon_on_hit()`: Positiv-Pfad Gift, Tick-Schaden Assertion (exakt 5 HP TRUE-Damage), BURN-Waffe, Kein-Stacking-Garantie, Negativ-Pfad (Waffe ohne Effekt, Combat ohne Equipment).

**Verbleibt offen:**
- Debuff-Skills (Skills die apply_poison/apply_burn direkt aufrufen) — kein Skill-System-Hook vorhanden, separater Fund falls Skill-System erweitert wird.

---

### I-04 🟡 P2 — Multi-Tenancy Phase 2 und 3 fehlen

**Problem:**  
MIGRATION-010 Phase 1 (Multi-Tenant State-Strukturen in Services) ist erledigt — `_players: Dictionary` mit `peer_id`-Key existiert in `InventorySystem`, `QuestService`, `SkillSystem`, `EquipmentService`, `PlayerStateService`.

Phase 2 (RPC-Verdrahtung: `NetworkBridge` sendet State-Updates an alle Peers) und Phase 3 (Equipment-Sync) sind nicht implementiert. Konkret:

- `NetworkBridge` hat keine `send_*`-Methode für Quest-Updates, Skill-XP, oder Equipment-Änderungen an andere Peers
- `NetworkBridge` hat keine `_rpc_*`-Empfangsmethode die serverseitig State ändert
- Ein zweiter Spieler der einer Session beitritt würde einen leeren State sehen — kein Sync

Das ist der kritischste "angefangen aber nicht fertig"-Punkt: Die Multi-Tenant-Strukturen geben das Versprechen, dass Multiplayer funktioniert. Es funktioniert nicht.

**Wo:** `scripts/services/NetworkBridge.gd` — Inventory/Quest/Skill-RPCs fehlen vollständig

**Fix:** MIGRATION-010.md Phasen 2+3 konkret umsetzen. Priorität: vor jeder echten Multiplayer-Demo.

---

### I-05 🟡 P2 — `on_*_confirmed()` Authority Guards: Inkonsistentes Pattern

**Problem:**  
C-02 (Round 13) hat Authority Guards in alle Services eingefügt. Das Guard-Pattern ist:

```gdscript
if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
    Logger.log_error("...: Aufruf auf Nicht-Autorität — verweigert.", LOG_CAT)
    return
```

Korrekt — aber nur in `receive_*_from_network()`-Methoden. Die eigentlichen `on_*_confirmed()`-Methoden in `InventorySystem` und `EquipmentService` haben **keinen** Authority Guard. Das ist inkonsistent:

- `NetworkBridge._rpc_item_add()` → ruft `_inventory.on_item_add_confirmed()` auf — kein Guard auf `on_item_add_confirmed()`
- Ein kompromittierter Client der `on_item_add_confirmed()` direkt aufruft (z.B. via Reflection oder wenn NetworkBridge umgangen wird) hat freien Zugang

Das ist nicht kritisch solange `on_*_confirmed()` nicht direkt per RPC exposed ist (es ist ein `Service extends RefCounted`, kein `@rpc`-Node). Aber die Verteidigung hängt an einer impliziten Annahme.

**Wo:** `scripts/services/InventorySystem.gd:178`, `scripts/services/EquipmentService.gd:265`

---

## SEKTION II — Architektur-Painpoints

---

### II-01 🟠 P1 — `Services`-Singleton ist gleichzeitig DI-Container und globaler Accessor

**Problem:**  
`Services.gd` erfüllt zwei verschiedene Rollen:

1. **DI-Container**: `populate_global()` / `populate_session()` / `clear_session()` — wird von `ServiceOrchestrator` gesteuert, ist der offizielle Befüll-Pfad
2. **Globaler Accessor**: `Services.inventory.request_add_item(...)` — jeder Code im Projekt kann zu jeder Zeit auf jeden Service zugreifen

Das Hybrid ist bewusst (ADR-001, Option C) und für die aktuelle Projektgröße pragmatisch. Aber es hat einen strukturellen Defekt: es gibt keine erzwungene Schichtengrenze. Ein UI-Controller kann `Services.combat.player_melee_damage()` aufrufen — syntaktisch legal, semantisch falsch.

Die Konvention ist in `CONTRIBUTING.md` dokumentiert. Konventionen ohne technische Erzwingung erodierten in jedem Langzeit-Projekt.

**Konsequenz auf 20-Jahr-Horizont:**  
Wenn das Team wächst oder die Codebase verzweigt, ist `Services.xyz` der Weg des geringsten Widerstands. ADR-001 selbst nennt "zukünftig: statischer Analyzer oder GDScript-Linter-Plugin" als Mitigation — aber dieser Linter existiert nicht. Der ADR-003-Lint (`lint_servicenode.sh`) zeigt dass automatisierte Checks machbar sind; das gleiche Pattern für `Services.xyz`-Zugriffe in Entity/UI-Schichten wäre der logische nächste Schritt.

**Empfehlung:** Ein `scripts/ci/lint_services_access.sh` das `Services.xyz` in `scripts/ui/` und `scripts/entities/` findet und bei direkten Service-Calls (außer erlaubten Ausnahmen) auf Exit 1 geht. Die `UIContext` + `IEntityContext`-Pattern sind die Erlaubnis-Whitelist.

---

### II-02 🟠 P1 — `CombatSystem.player_melee_damage()` nimmt `SkillSystem` als Parameter, nicht als Dep

**Problem:**  
D-01 aus der alten Review: `player_melee_damage(skill_system: SkillSystem, player_id: String)` nimmt `SkillSystem` als Funktionsparameter. Das ist inkonsistent: `_equipment` ist eine injizierte Dep (H-04 fix), `_stat_modifiers` ist eine injizierte Dep — aber `SkillSystem` wird bei jedem Aufruf durchgereicht.

Der Grund war wahrscheinlich Vorsicht (SkillSystem ist Session-scoped, Combat könnte vor der Session aufgerufen werden). Aber `CombatSystem` ist selbst Session-scoped — die Rechtfertigung hält nicht.

**Wo:** `scripts/services/CombatSystem.gd:214`

**Fix:** `_skill_system: SkillSystem` als optionale injizierte Dep in `configure()`, wie `_stat_modifiers` und `_equipment`.

---

### II-03 🟡 P2 — `HUDManager` ist außerhalb des Service-Containers, aber mit Service-Lifecycle gekoppelt

**Problem:**  
`HUDManager` lebt nicht im `Services`-Container (korrekt dokumentiert in `Services.gd`: "Lifecycle-Mismatch, ADR-003/TD-05"). Aber `ServiceOrchestrator.boot_session()` greift via `get_node_or_null("/root/HUDManager")` auf `HUDManager` zu um die `_ui_context_factory` zu setzen.

Das ist ein Kompromiss der funktioniert — aber der `ServiceOrchestrator` kennt jetzt einen hardcodierten AutoLoad-Pfad. Wenn `HUDManager` umbenannt oder in die Session-Szene verschoben wird, bricht das lautlos.

**Empfehlung:** Entweder `HUDManager` als `ServiceNode` in die Global-Registry aufnehmen (womit der "Lifecycle-Mismatch" ehrlich gelöst wird), oder `EventBus.system.session_ready` als Trigger für HUDManager nutzen statt direkter Orchestrator-Verdrahtung.

---

### II-04 🟡 P2 — `DataService` hat kein definiertes `request_/on_*_confirmed`-Pattern

**Problem:**  
`DataService` ist Global-Service und rein lesend — das macht das request/confirmed-Pattern irrelevant für ihn (keine State-Mutation). Aber: `DataService.get_player_data()` wird in `InventorySystem.configure()` aufgerufen um max_slots/max_weight für Player 1 zu setzen. Das ist ein Side-Effect beim Service-Boot.

Wenn der Spieler im Spiel PlayerData-Werte ändert (z.B. Perks die max_carry_weight erhöhen), gibt es keinen Mechanismus um diese Änderung zu propagieren — `InventorySystem` liest einmalig beim Configure.

Das ist kein Bug heute (es gibt keine Perks die PlayerData mutieren). Aber das Muster ist fragil: die Annahme "PlayerData ist immutable nach Boot" ist nirgendwo explizit dokumentiert.

---

## SEKTION III — ADR-Qualität

---

### III-01 🔵 P3 — ADR-007 kann vollständig gelöscht werden

**Status:** ADR-007 ist "Abgelöst von ADR-010". `INetworkAdapter.gd` / `LocalNetworkAdapter.gd` sind nach MIGRATION-010 entfernt. ADR-007 hat keinen eigenständigen Wert mehr — er ist nur noch historische Fußnote die Verwirrung stiftet wenn jemand den ADR-Index liest und fragt "was ist ein INetworkAdapter?".

**Empfehlung:** ADR-007 löschen. Im ADR-010 einen einzeiligen Verweis: "Löst ADR-007 (INetworkAdapter) vollständig ab — der frühere Stub-Adapter ist entfernt."

---

### III-02 ✅ P3 — ADR-004 Tech Debt aktualisiert (Round 23)

I-01 (Round 15) hat `on_quest_start_confirmed()` und `on_xp_add_confirmed()` public gemacht. ADR-004 ist jetzt nachgeführt: Entscheidungstabelle, Negativ/Risiken, und Offener-Tech-Debt-Abschnitt alle auf ✅-Stand.

---

### III-03 ✅ P3 — ADR-001 Ablösungsbedingung bereits korrekt formuliert

ADR-001 wurde bereits vorab aktualisiert: die Ablösungsbedingung lautet "ServiceFactory kann ohne `add_child()` aufbauen UND Services ohne SceneTree-Zustand konfigurierbar" — nicht mehr "wenn GDScript Constructor-Parameter bekommt". III-03 ist obsolet.

---

## SEKTION IV — Was fehlt bei der Testabdeckung

---

### IV-01 🟡 P2 — Save Round-Trip Tests für Inventory, Quest, Skill fehlen noch

Nur EquipmentService hat vollständige Round-Trip-Tests (A-01-Fix). `InventorySystem`, `QuestService`, `SkillSystem` haben Unit-Tests für Logik, aber kein Test prüft: "Speichere State X, lade State X, verifiziere dass der rekonstruierte State === X ist."

Das ist das riskanteste Gap: Save-Bugs manifestieren sich erst nach App-Neustart und sind schwer zu reproduzieren.

**Dateien die Round-Trip-Tests brauchen:**
- `tests/unit/test_inventory_system.gd` — Round-Trip fehlt
- `tests/unit/test_quest_service.gd` — Round-Trip fehlt  
- `tests/unit/test_skill_system.gd` (existiert diese Datei?) — prüfen

---

### IV-02 🟡 P2 — NetworkBridge: keine Tests für Tier-1/Tier-2 Übergang

`test_network_bridge.gd` und `test_network_bridge_contract.gd` existieren. Aber: kein Test prüft den Tier-1→Tier-2-Übergang (Peer gesetzt → RPCs werden tatsächlich ausgeführt statt lokaler Call). Das ist der Core-Vertrag des gesamten Multi-Player-Designs.

---

### IV-03 🟡 P2 — UI-Layer hat keine Tests

Alle `scripts/ui/controllers/` und `scripts/ui/visuals/` sind nicht getestet. Das ist teilweise unvermeidbar (Scene-abhängig), aber die Controller-Logik (Businesslogik in `EquipmentUIController`, Zustandsmaschine in `ContextMenuController`) wäre mit `IUIContext`-Mocks testbar.

**Update (I-02):** Seit I-02 ist das nicht mehr nur "wäre testbar" — `IUIContext.bus()` macht es konkret möglich, ohne laufenden `EventBus`-AutoLoad. 3 von 10 jetzt umgestellten Controllern haben bereits Beispiel-Tests (`test_notification_controller.gd`, `test_player_hp_controller.gd`, `test_skill_panel_controller.gd`); die übrigen 7 (`ContextButtonController`, `ContextMenuController`, `EquipmentUIController`, `FloatingTextController`, `InteractionButtonController`, `PauseMenuController`, `QuestPanelController`) plus `scripts/ui/visuals/` bleiben offen für diesen Backlog-Punkt.

---

## Nächste Sprints — Reihenfolge

---

### SPRINT A — Legacy-Cleanup (vor Multiplayer ausführen)

Das Spiel ist nicht live. Es gibt keine Nutzer die auf Kompatibilität angewiesen sind. Fallbacks, `@deprecated`-Wrapper und Migrations-Kommentare sind technische Schulden die jetzt billiger zu tilgen sind als nach dem Multiplayer-Sprint, weil jede Multiplayer-Änderung dieselben Dateien anfasst.

**Was konkret zu löschen/bereinigen ist:**

| Ziel | Was | Warum |
|------|-----|-------|
| `Services`-Autoload | Kompletten `Services.gd`-Singleton löschen | `lint_services_access.sh` bestätigt: keine Live-Calls mehr. Der Autoload ist leere Hülle. |
| `from_services()`-Stubs | In `UIContext`, `EntityContext` und allen Services die `push_error()+return empty` stubs haben | Tote Methoden die nur Verwirrung stiften. Löschen, nicht `@deprecated` markieren. |
| `receive_*_from_network()`-Wrapper | In `QuestService`, `SkillSystem` — kollabieren oder löschen | Seit I-01 (Round 15) delegieren sie nur noch an `on_*_confirmed()`. Entweder direkt aufrufen oder den Wrapper als echten Authority-Guard umbauen — keinen Zwischenschritt behalten. |
| `# MIGRATION-010:` Kommentare | Alle Kommentare die eine vergangene Migration erklären | Erklären was *war*, nicht was *ist*. Löschen. |
| `# TD-NN:`, `# H-0N:`, `# BUG-NN:` Kommentare | Alle Ticket-Referenz-Kommentare im Code | Gehören ins Git-Log, nicht in den Code. Löschen. |
| `# justified:` Pflicht-Kommentare in `lint_servicenode.sh` | Ersetzen durch echte ADR-Verweise im Code | Das aktuelle Muster zwingt zu Copy-Paste-Boilerplate. Ein Link auf ADR-003 reicht. |
| `@deprecated`-Annotationen | Keine neuen `@deprecated` hinzufügen; bestehende durch Löschen ersetzen | Pre-launch: deprecated bedeutet gelöscht, nicht markiert. |

---

### SPRINT B — `@rpc`-Annotationen + SessionManager

Die beiden gehören zusammen: RPCs ohne Session sind nicht testbar, Session ohne RPCs ist sinnlos.

**Was zu tun ist:**
1. Alle `_rpc_*`-Methoden in `NetworkBridge` mit `@rpc("any_peer", "call_remote", "reliable")` annotieren
2. `SessionManager`-Service: `create_server()` / `join_server()`, `peer_connected` / `peer_disconnected` Handling, Player-Slot-Registry (peer_id → player-Bucket)
3. Host/Join-UI (minimal — IP + Port reicht für jetzt)
4. `NetworkBridge.send_*()` Methoden für Quest, Inventory, Equipment ergänzen (analog zu `send_add_xp()`)

**Tests:** Tier-2-Tests aus Round 23 als Vorlage — `MockNetworkBridgeAsPeer` bereits vorhanden.

---

### SPRINT C — World Authority + EnemyAI-Gate

**Was zu tun ist:**
1. `set_multiplayer_authority(1)` auf alle Welt-Entities (`EnemyNPC`, `IronOre`, `OakTree`, Spawner)
2. `EnemyAI._process()` / `_physics_process()` hinter `if not is_multiplayer_authority(): return` gate
3. `EnemySpawner` nur auf Autorität spawnen lassen

Das ist das größte Desync-Risiko. Eine Ein-Zeilen-Fix pro Datei, aber ohne Sprint B nutzlos.

---

### SPRINT D — State Sync on Join + Position Sync

**Was zu tun ist:**
1. Initial-Snapshot: `GameSaveService.get_full_state()` an neue Peers senden wenn sie joinen
2. `MultiplayerSynchronizer`-Node in Player-Scene für Positions-Sync (Godot-built-in, kaum Code)
3. `EnemyNPC`-Position-Sync für sichtbare Gegner (entweder `MultiplayerSynchronizer` oder manuelles RPC im AI-Tick)

---

## Gesamtbild: Wo steht die Architektur?

**Was gut ist:**
- Service-Lifecycle (configure/on_ready/on_cleanup/on_tick) konsistent durch alle Services
- Zwei-Registry-Modell (Global vs. Session) löst Character-Switch sauber
- `ServiceDeps` mit `require()` vs `get_optional()` — richtiger Ansatz
- `request_*/on_*_confirmed()`-Pattern konsistent in allen 4 server-autoritativen Services
- DI-Graph ist sauber genug dass Multiplayer-Features ohne Service-Rewrites eingebaut werden können
- CI-Lint (`lint_servicenode.sh`, `lint_services_access.sh`) verhindert Regression

**Was noch fehlt:**
- Legacy-Ballast (Sprint A) — nicht gefährlich, aber teurer je länger man wartet
- `@rpc`-Annotationen fehlen → Multiplayer ist strukturell vorbereitet aber funktional inert
- Kein `SessionManager` → kein echter Peer-Aufbau möglich
- World-Authority nicht gesetzt → bei zwei Clients simuliert jeder alles selbst
- Kein State-Sync on Join → Player 2 startet in leerem Zustand

Schätzung: Sprint A (1–2 Tage) + Sprint B (3–5 Tage) + Sprint C (1 Tag) + Sprint D (2–3 Tage) = funktionierendes Two-Player-Coop.
