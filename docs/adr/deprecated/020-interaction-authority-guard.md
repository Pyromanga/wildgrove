> **DEPRECATED (2026-08-02):** Legacy-Bestand, Neuaufbau ab Decision 0010 -- kein Build-/Check-Script vorhanden.
> Kein zugehöriges Build-/Check-Script — als unverifizierte Behauptung eingestuft (siehe MANAGER.md §3). Inhalt bleibt unten als Historie erhalten, ist aber nicht mehr bindend.

# ADR-020: Server-autoritative Auflösung von Interaktions-Ereignissen

**Status:** Umgesetzt (Round 42 Transport + Round 43 Berechnung — siehe „Umsetzungsstand" unten; R-4 ist größer als ursprünglich gefasst und noch offen, siehe TODO-Dokument)
**Datum:** 2026-07
**Kontext:** `InteractionExecutor`, `EnemyAttack`/`EnemyNPC`, `AnimalBase`/`AnimalCatcher`,
`HarvestableEntity`, `WorldService`, `NetworkBridge`. Root-Cause-Familie R-1, R-2,
R-3, R-4, R-6 aus `TODO-offene-probleme.md`.

## Problem

Fünf offene Funde sind eine einzige Bug-Klasse: **das Ergebnis einer Interaktion
wird auf dem Peer berechnet, der die Interaktion ausgeführt hat, nicht auf der
Autorität.**

- R-1: `InteractionExecutor._on_tween_finished()` würfelt Loot (`loot_table.roll()`)
  und bemisst XP lokal. Der Server bekommt nur noch das *Ergebnis* über
  `_rpc_add_item`/`_rpc_add_xp` gemeldet und prüft ausschließlich `_is_authority()`,
  nie Plausibilität.
- R-2: `EnemyAttack.setup_interactable()` registriert `attack_enemy` als normale
  `InteractableData` mit `xp_amount = 5` — läuft über denselben ungeschützten Pfad
  wie R-1, komplett getrennt vom bereits korrekten autoritativen Schadenspfad in
  `EnemyNPC._on_interacted()`.
- R-3: `AnimalBase._on_interacted()` ruft `AnimalCatcher.catch_animal()` ohne
  `is_multiplayer_authority()`-Guard auf; `HarvestableEntity._on_interacted()`
  ruft `emit_entity_despawn_requested()`/`on_despawn()`/`queue_free()` ebenso
  ungeguarded auf. `EnemyNPC._on_interacted()` hat den Guard bereits — er ist
  also bekannt und einbaubar, nur nicht flächendeckend eingebaut.
- R-4: `_rpc_equip_item` löst `item_id` nur über `DataService.get_item()` auf,
  ohne je `InventorySystem.has_item()` zu prüfen — jede existierende Item-ID ist
  ausrüstbar, unabhängig vom Besitz.
- R-6: Selbst mit Guard bleibt ein Folgeproblem: `WorldService._on_entity_despawn_requested()`
  despawnt auf dem Peer, der das Signal gefeuert hat. Da `EventBus` pro Peer
  lokal instanziiert wird (siehe ADR-021), erreicht ein client-seitiger Despawn
  den Server nie — Baum/Erz bleibt auf dem Server interagierbar, obwohl er beim
  auslösenden Client visuell verschwunden ist.

Der gemeinsame Nenner: es gibt kein einheitliches Muster für „Client meldet
*Absicht*, Autorität berechnet *Ergebnis*". `on_quest_complete_confirmed()` /
`QuestObjectiveHandler` exerzieren dieses Muster für Quest-Abschluss bereits
korrekt vor — es wurde nie auf Interaktionen übertragen.

## Optionen

### Option A: Punktuelle Guards nachrüsten (`is_multiplayer_authority()` an jeder Stelle)
Fügt an jedem der fünf Fundorte den fehlenden Autoritäts-Check ein, ohne die
Berechnung selbst zu verschieben.
- ✅ Kleinster Diff, schnell umsetzbar
- ❌ Löst nicht die Root Cause: Loot/XP werden weiterhin *client-seitig berechnet
  und dann behauptet* — der Guard verhindert nur, dass ein Nicht-Autoritäts-Peer
  seine eigene Berechnung *selbst ausführt*, nicht dass ein modifizierter Client
  dem Server ein falsches Ergebnis meldet (R-1/R-2/R-4 bleiben exploitbar, weil
  `_rpc_add_item(item_id, qty)` weiterhin dem Client vertraut)
- ❌ Fünf Stellen einzeln reparieren heißt: die sechste, noch nicht gefundene
  Stelle bleibt offen. Kein struktureller Schutz gegen Wiederholung derselben
  Bug-Klasse.
- ❌ Genau die Art von „praktischem Workaround" (Symptom fixen, Root Cause
  stehen lassen), die hier explizit vermieden werden soll.

### Option B: Autorität berechnet, Client meldet nur Absicht (gewählt)
Verschiebt die Berechnung selbst auf die Autorität. Der Client löst über
`request_interact(action_id, player_id)` eine Interaktion aus; **alle**
Konsequenzen (Loot-Roll, XP-Menge, Despawn, Equip-Besitzprüfung) werden
ausschließlich auf der Autorität aus serverseitig gehaltenem State abgeleitet —
exakt das Muster, das `on_quest_complete_confirmed()` bereits nutzt:

- `InteractionExecutor` sendet nur noch `action_id` + `player_id`; `loot_table.roll()`
  und die XP-Bemessung wandern in einen serverseitigen `InteractionResolver`
  (neuer, dünner Service), der pro `action_id` weiß, welches Ergebnis erlaubt ist.
  Der Client zeigt den Tween/die Animation weiterhin lokal (Latenz-Verdeckung),
  aber das *Ergebnis* kommt erst über den Rücksync (ADR-022) zurück.
- `EnemyAttack`/`AnimalBase`/`HarvestableEntity._on_interacted()` bekommen
  denselben Guard wie `EnemyNPC` — aber der Guard ist hier kein Sicherheitsnetz
  mehr für eine sonst client-seitige Wirkung, sondern schlicht die Aussage
  „dieser Code läuft nur auf der Autorität", weil die Wirkung selbst nur dort
  ausgeführt wird.
- R-4 wird durch dieselbe Verschiebung mit gelöst: `on_equip_confirmed()` prüft
  `InventorySystem.has_item()` auf der Autorität, bevor es ausrüstet — kein
  gesonderter Patch, sondern Konsequenz derselben Regel „Autorität prüft, bevor
  sie mutiert".
- R-6 verlangt zusätzlich, dass der Despawn-*Request* selbst die Autorität
  erreicht (RPC statt lokalem Signal) — das ist der Teil, der sich mit ADR-021
  überschneidet (Ereignis muss die Autorität erreichen) und dort mitgelöst wird.
- ✅ Schließt die eigentliche Sicherheitslücke, nicht nur den beobachteten
  Cheat-Pfad
- ✅ Ein Muster für alle fünf Funde statt fünf Einzel-Patches — nächster
  ähnlicher Fund (Fishing, Crafting, …) folgt automatisch demselben Kontrakt
- ❌ Größerer Diff: `InteractionExecutor` und die Loot/XP-Bemessung müssen aus
  dem Client-Pfad heraus- und in einen serverseitigen Resolver hineingezogen
  werden
- ❌ Tween/Animation muss vom *Ergebnis* entkoppelt werden (Client zeigt „es
  passiert etwas", bekommt aber erst über den Rücksync zu sehen, *was*)

### Option C: Server-seitige Plausibilitätsprüfung der gemeldeten Werte
Client rechnet weiter lokal, Server vergleicht das gemeldete Ergebnis gegen
eine Tabelle plausibler Werte (z. B. „`qty` für `item_id X` darf nur 1–3 sein").
- ✅ Kleinerer Diff als Option B
- ❌ Verlagert nur die Angriffsfläche: die Plausibilitätstabelle muss jede
  Kombination aus Loot-Tabelle × Skill-Level × Ausrüstung abbilden und wird
  selbst zur Quelle von Bugs (falsch-positive Ablehnungen ehrlicher Ergebnisse)
- ❌ Löst R-6 nicht (Despawn hat keinen „Wert", der plausibilisiert werden könnte)
- ❌ Zwei Wahrheitsquellen für dasselbe Ergebnis (Client-Rechnung + Server-Tabelle)
  müssen dauerhaft synchron gehalten werden — genau die Art von Doppelpflege,
  die Root-Cause-Fixes vermeiden sollen

## Entscheidung

**Option B.** Server-autoritative Berechnung, Client meldet Absicht. Keine
Plausibilitätstabelle als zusätzliche Wahrheitsquelle (Option C), kein
Guard-Flicken ohne Verschiebung der Berechnung (Option A).

## Konsequenzen

### Positiv
- Loot-, XP- und Equip-Cheating über modifizierte Clients ist strukturell
  ausgeschlossen, nicht nur die aktuell bekannten Vektoren.
- Ein Kontrakt (`request_*` → Autorität berechnet → `on_*_confirmed`) für alle
  Interaktionsarten (Gathering, Combat, Taming, Equip) statt einer Sammlung von
  Einzel-Guards mit je eigener Historie.
- `EnemyNPC._on_interacted()` wird zum Referenzmuster statt zur Ausnahme.

### Negativ / Risiken
- `InteractionExecutor` verliert seine heutige Rolle als alleiniger
  Ergebnis-Ersteller — Tests, die bisher `loot_table.roll()` clientseitig direkt
  aufrufen und prüfen, müssen auf den `InteractionResolver` umgestellt werden.
  **Kein Test-Fallback, der die alte clientseitige Berechnung parallel am Leben
  hält** — das wäre derselbe Fehler nur unter Testdecke.
- Tier 1 (Solo) muss denselben Pfad durchlaufen wie Tier 2/3 (Autorität = eigener
  Prozess), nicht einen eigenen Shortcut — sonst divergiert Solo- von
  Multiplayer-Verhalten genau an der Stelle, die dieser ADR schließen soll.

### Mitigationen
- `InteractionResolver` wird als eigenständiger, ungemockter Service getestet
  (echte Loot-Tabellen, echte Skill-Level), nicht über Test-Doubles, die das
  Ergebnis vorgeben.
- Tween/Latenz-Verdeckung bleibt rein visuell (Animation läuft immer lokal ab);
  das eigentliche Ergebnis kommt ausschließlich über den in ADR-022 beschriebenen
  Rücksync — es gibt keinen zweiten, „für die Anzeige" clientseitig geschätzten
  Wert, der später stillschweigend überschrieben wird.

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]

## Umsetzungsstand (Round 42)

Dieser ADR wird in zwei unabhängig überprüfbaren Schritten umgesetzt, nicht in
einem Sprung — der Transport-Mechanismus (dieser Round) ist eine Voraussetzung
für den Resolver (nächster Round), aber nicht umgekehrt.

**Geschlossen in Round 42 — der Transport-Teil, unabhängig vom Berechnungs-Teil:**
- Neuer Kontrakt `request_entity_interaction()` (WorldService, Client-seitiger
  Einstieg) → `NetworkBridge.send_entity_interaction()`/`_rpc_request_entity_interaction()`
  → `WorldService.resolve_and_dispatch_interaction()` (Autoritäts-Seite, nutzt
  `EntityOrchestrator.resolve_for_player()` aus ADR-023). Zentral in
  `InteractableComponent._handle_completion()` verdrahtet — gilt damit
  einheitlich für Harvestables, Tiere UND Gegner, nicht als Einzel-Patch pro Typ.
- **R-3 geschlossen:** `AnimalBase._on_interacted()` und
  `HarvestableEntity._on_interacted()` haben jetzt denselben
  `is_multiplayer_authority()`-Guard wie `EnemyNPC` — UND erreichen dank des
  Transports oben die tatsächliche Autorität, nicht nur ihre eigene, evtl.
  falsche Kopie von `is_multiplayer_authority()` auf einem Nicht-Host-Peer.
- **R-6 geschlossen:** Der Despawn-Request selbst läuft jetzt nur noch auf der
  Autorität (`HarvestableEntity._on_interacted()`'s Guard), nicht mehr auf
  jedem Peer, der lokal zuerst seinen Tween beendet — das eigentliche R-6-
  Symptom (Server erfährt nie vom Despawn) ist damit strukturell ausgeschlossen,
  nicht nur maskiert.
- **R-2, Transport-Hälfte geschlossen, Berechnungs-Hälfte offen:** Der
  Schadens-Hook von `EnemyNPC._on_interacted()` erreicht jetzt auf Tier 2/3
  tatsächlich die Autorität (vorher lief er auf einem Nicht-Host-Client
  strukturell ins Leere — sein vorhandener Guard war dort niemals erreichbarer
  Code, weil der zugrundeliegende `interacted`-Emit nie über den Prozess
  hinauskam). Das war ein eigenständiger, in der ursprünglichen ADR-020-Analyse
  nicht erkannter Gameplay-Bug (kein Zwei-Peer-Integrationstest hat ihn bisher
  gefangen). Die XP-Bemessung selbst (`xp_amount = 5` aus `InteractableData`)
  läuft weiterhin unverändert im alten, client-berechneten Pfad.
- Cheat-Vektor geschlossen, der beim Entwurf dieses Mechanismus selbst entdeckt
  wurde: `max_range` für die Plausibilitätsprüfung kommt aus der servereigenen
  `InteractableComponent.detection_radius` der Entity, niemals aus einem
  RPC-Parameter — ein client-gemeldeter Wert hätte die Prüfung in
  `resolve_for_player()` wertlos gemacht. Ebenso kommt `player_id` im RPC nicht
  vom Client, sondern aus `multiplayer.get_remote_sender_id()`.

**Noch offen — Option B's eigentlicher Kern, separater Round:**
- **R-4:** `_rpc_equip_item` prüft weiterhin nicht `InventorySystem.has_item()`
  vor dem Ausrüsten — unabhängig vom Interaktions-Mechanismus hier, eigener Fund.
- Bekannte, bewusst nicht in diesem Round mitgelöste Lücken (siehe
  `TODO-offene-probleme.md`): `player.global_position` ist weiterhin
  client-reported (kein Movement-Anti-Cheat, siehe ADR-023/024/025), und die
  neuen `any_peer`-RPCs haben noch kein Rate-Limiting.

## Umsetzungsstand (Round 43 — geschlossen)

Diese Runde bringt den in Round 42 noch offen gelassenen Berechnungs-Teil.
R-1 und R-2 (Berechnungs-Hälfte) sind mit dieser Runde geschlossen.

- Neu: `scripts/interaction/InteractionResolver.gd` — zustandslose statische
  Utility (Muster identisch zu `AnimalCatcher`/`EnemyAttack`), rollt
  `InteractableData.loot_table` und emittiert `loot_collected`/`xp_gained` über
  den übergebenen `IEventBus`, attribuiert an `player_id`. Prüft selbst KEINEN
  Autoritäts-Guard — das bleibt Aufgabe des Aufrufers (siehe unten), exakt wie
  bei `AnimalCatcher.catch_animal()`.
- `InteractionExecutor._on_tween_finished()`: Loot-Roll + XP-Emission entfernt.
  Bleibt zuständig für Tween/Fortschrittsbar (rein visuell) und `inspect_text`
  (Flavortext, kein Reward). `_stat_modifiers`-Dep komplett entfernt statt nur
  ungenutzt gelassen — war ohnehin bereits vorher nie wirksam verdrahtet (siehe
  nächster Punkt).
- **Nebenbefund beim Entfernen:** `InteractionExecutor`s `StatModifierService`-Dep
  war in `BootstrapConfig.tres` nie im `deps`-Array deklariert (nur
  `["playerstates", "event_bus"]`) — die Yield-Skalierung über `yield_stat_id`
  lief in Produktion folglich IMMER ungemoddet (x1.0), unabhängig vom
  tatsächlichen Stat-Wert. Kein Bestandteil der eigentlichen R-1-Baustelle,
  aber am selben Code gefunden. Behoben als Seiteneffekt der Verschiebung:
  `InteractionResolver.resolve()` bekommt `stat_modifiers` jetzt vom
  `IEntityContext` der Entity (`HarvestableEntity._on_interacted()` →
  `_ctx.get_stat_modifiers()`), und dieser Pfad ist über `WorldService`s eigenen,
  korrekt deklarierten `stat_modifiers`-Dep tatsächlich verdrahtet.
- `HarvestableEntity._on_interacted()`: ruft `InteractionResolver.resolve()` mit
  `_interactable_comp.data` (servereigene Kopie) auf, bevor despawnt wird —
  weiterhin hinter demselben `is_multiplayer_authority()`-Guard wie zuvor.
- `EnemyNPC._on_interacted()`: ruft nach der Schadensanwendung zusätzlich
  `InteractionResolver.resolve()` für das `AttackInteractable`-Kind auf, damit
  die Interaktions-XP für den Schwung (getrennt von der Kill-XP in `_die()`)
  ebenfalls authority-seitig vergeben wird. Kein zusätzlicher Treffer-Check
  nötig — `CombatSystem` kennt keine Miss-Chance.
- `test_interaction_executor.gd`: die beiden alten Reward-Tests durch
  Regressions-Tests ersetzt, die belegen, dass `InteractionExecutor` `loot_collected`/
  `xp_gained` NICHT mehr selbst emittiert. Der alte `action.drops`-Test war
  bereits vor dieser Runde nie funktionsfähig (kein `drops`-Feld auf
  `InteractableAction`) und wurde entfernt statt migriert.

**Test-Abdeckung, mit dieser Runde ergänzt:**
- Neu: `tests/unit/test_interaction_resolver.gd` — dedizierte Unit-Tests mit
  echten `LootTable`/`LootEntry`/`StatModifierService`-Instanzen (keine Mocks
  für die Berechnung selbst, nur `MockEventBus` als reine Transport-Infrastruktur).
  Deckt: Drop-Emission, XP-Emission (inkl. `xp_type == "none"` und
  `xp_amount <= 0` als Nicht-Emit-Fälle), `player_id`-Attribution statt Default,
  Yield-Skalierung über `StatModifierService` (inkl. Skalierung PRO `player_id` —
  der konkrete Bug-Fix aus dieser Runde), sowie defensive Guards
  (`data == null`, `bus == null`) ohne Crash.
- `test_harvestable_entity.gd`: um drei Guard-Tests erweitert — Autorität löst
  über `InteractionResolver` tatsächlich XP/Loot aus, Nicht-Autorität löst gar
  nichts aus (Guard greift vor jeglicher Wirkung, nicht nur vor dem Despawn),
  und `_ctx.get_stat_modifiers()` kommt nachweislich bei der Loot-Skalierung an.
- `EnemyNPC._on_interacted()`s neuer Aufruf bleibt mangels Headless-Instanziierbarkeit
  (siehe `test_enemy_npc_pool_reuse.gd`-Kommentar) nur indirekt über die
  `InteractionResolver`-Unit-Tests verifiziert, nicht über eine eigene
  `EnemyNPC`-Instanz — das ist eine bestehende Testbarkeits-Lücke, keine neue,
  und wird hier nicht mitgelöst.
- `TODO-offene-probleme.md`: R-1/R-2 auf "geschlossen" gesetzt.

## Umsetzungsstand (Round 45 — RPC-Wert-Validierung, "Server validiert RPC-Werte nicht")

Ausgangspunkt war der eigenständige TODO-Punkt "Server validiert RPC-Werte nicht"
(`_rpc_add_item(item_id, qty)` prüft nur `_is_authority()`, nicht ob `qty` plausibel
ist). Root-Cause-Recherche vor dem Codieren (gleiche Tiefe wie R-4) ergab: der Bug
war real, aber die Prämisse dahinter nicht mehr aktuell.

**Befund:** Seit R-1/R-2 (Round 43) und R-4 (Round 44) läuft kein einziger
legitimer Spielcode-Pfad mehr über `request_add_item()`/`request_add_xp()` mit
einem client-gewählten Wert — Root-Cause-Recherche dazu fand in Round 45 statt:
- Gathering/Combat-Loot & -XP: `InteractionResolver.resolve()`, ausschließlich
  hinter `is_multiplayer_authority()`-Guards.
- Kill-Reward: `EnemyNPC._die()`, erreichbar nur über die bereits authority-
  geguardete `_on_interacted()`-Schadenskette.
- Quest-Reward: `RewardDispatcher.dispatch()`, mit Werten aus der statischen
  `QuestReward`-Resource, ausgelöst nur aus `on_quest_complete_confirmed()`.

In allen drei Fällen läuft `request_add_item()`/`request_add_xp()` bereits auf
dem Autoritäts-Prozess selbst — der `rpc_id(1, "_rpc_add_item"/"_rpc_add_xp", …)`-
Zweig wurde von keinem dieser Pfade je genommen. Trotzdem blieb er (und die
`_rpc_add_item`/`_rpc_add_xp`-Empfänger in `NetworkBridge.gd`) live erreichbar:
Godots `@rpc("any_peer")` prüft nicht, ob "ehrlicher" Code den Aufruf je senden
würde — ein modifizierter Client kann `_rpc_add_item()`/`_rpc_add_xp()` direkt
aufrufen, unabhängig von jeglichem Client-Code.

**Entscheidung (Option A statt B):** Fläche entfernen statt nachträglich
validieren. Es gibt aktuell kein Feature (Shop/Crafting = 🟡 "fehlt komplett"
laut `TODO-offene-probleme.md`), das einen client-initiierten Grant mit freier
Menge bräuchte — eine Plausibilitätsprüfung an dieser Stelle hätte eine
Schnittstelle bewacht, die es architektonisch nicht geben sollte.

**Umgesetzt:**
- `NetworkBridge._rpc_add_item()`/`_rpc_add_xp()` entfernt (die eigentlichen
  `@rpc("any_peer")`-Empfänger — das war die tatsächliche Angriffsfläche).
- `NetworkBridge.send_add_item()`/`send_add_xp()` entfernt — unbenutzte
  Wrapper, die ausschließlich zu den beiden RPCs oben sendeten; nichts in
  Produktionscode rief sie auf (`InventorySystem`/`SkillSystem` senden nie über
  diese Bridge-Methoden, sondern — vormals — direkt selbst).
- `InventorySystem.request_add_item()`/`SkillSystem.request_add_xp()`: der
  `_network.rpc_id(1, …)`-Zweig entfällt, beide rufen jetzt immer direkt
  `on_item_add_confirmed()`/`on_xp_add_confirmed()` auf. Deren eigener C-02-
  Authority-Guard bleibt unverändert als Verteidigung in der Tiefe bestehen.
- `NetworkContract.gd`: der Kommentar, der noch den Vor-R-1/R-2-Zustand
  beschrieb ("Loot-Roll/XP-Bemessung laufen weiterhin in `InteractionExecutor`
  … nur als fertiges Ergebnis über `_rpc_add_item`/`_rpc_add_xp` gemeldet"),
  war selbst stale — aktualisiert.

**Falls künftig doch ein client-initiierter Grant nötig wird** (z. B. Shop-Kauf,
Crafting-Ergebnis): nicht `_rpc_add_item`/`_rpc_add_xp` wiederherstellen, sondern
dasselbe Muster wie `send_entity_interaction()`/`resolve_for_player()` (ADR-023)
anwenden — Client schickt nur eine Absicht/Referenz (z. B. `shop_item_id`), die
Autorität löst Menge/Preis aus ihren eigenen Daten auf. Ein roher Zahlenwert vom
Client sollte nie wieder direkt in `on_item_add_confirmed()`/`on_xp_add_confirmed()`
münden.

**Tests:** `test_network_bridge.gd`/`test_network_bridge_contract.gd` um die
entfernten `send_add_item()`/`send_add_xp()`/Tier-2-RPC-Routing-Tests bereinigt,
neuer Regressionstest `test_no_rpc_add_item_or_add_xp_surface()` sichert, dass
die Methoden nicht wieder auftauchen.

`TODO-offene-probleme.md`: "Server validiert RPC-Werte nicht" auf geschlossen
gesetzt.

## Ablösung

[Leer lassen bis dieser ADR durch einen neuen abgelöst wird]
