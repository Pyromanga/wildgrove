# res://scripts/platform/interfaces/IEntityContext.gd
class_name IEntityContext extends RefCounted

## IEntityContext — Schmale Service-Fassade für Entities.
##
## Stattdessen bekommen sie via on_spawn(config, context) nur die Services,
## die sie wirklich brauchen — testbar, server/client-dual-context-fähig.
##
## VERWENDUNG:
##   EntityOrchestrator erstellt einen EntityContext und injiziert ihn in on_spawn():
##     entity.on_spawn(config, context)
##
##   In einem Server-Kontext: ServerEntityContext mit anderen Implementierungen.
##   In einem Client-Kontext: ClientEntityContext mit Prediction-Services.
##   In Tests:               MockEntityContext mit Mock-Implementations.
##
## WICHTIG: Entities speichern den Context als _ctx: IEntityContext.

# ─────────────────────────────────────────────
# Gameplay-Services
# ─────────────────────────────────────────────

## Skill-System für Schadens-Berechnung, XP-Queries.
## Gibt null zurück wenn der Kontext diesen Service nicht bereitstellt
## (z.B. rein visueller Client-Kontext).
func get_skill_system() -> SkillSystem:
	return null

## InventorySystem für Item-Checks (z.B. Tool-Requirement).
func get_inventory() -> InventorySystem:
	return null

## EventBus-Zugriff über IEventBus-Interface für echte Testbarkeit.
## Gibt null zurück wenn der Kontext keinen Bus bereitstellt.
## EntityContext überschreibt das mit dem injizierten IEventBus.
func get_event_bus() -> IEventBus:
	return null

## SettingsService — für Entities, die geräteweite UI-/Input-Präferenzen lesen
## müssen (z.B. TouchInput: feste Joystick-Position, siehe joystick_pos_x/y).
## Gibt null zurück wenn der Kontext keinen SettingsService bereitstellt (z.B.
## Server-Kontext ohne Client-UI, reiner Test-Kontext) — Konsumenten behandeln
## das wie jeden anderen optionalen Service (Fallback auf SettingsService.DEFAULTS).
func get_settings() -> SettingsService:
	return null

# ─────────────────────────────────────────────
# Welt-Services
# ─────────────────────────────────────────────

## Factory3D für prozedurales Spawning von Sub-Entities.
func get_factory() -> Factory3D:
	return null

## RespawnService — für Entities die ihren eigenen Respawn triggern müssen.
func get_respawn() -> RespawnService:
	return null

## DataService — für Entities die Basiswerte (Stats, Definitionen) lesen müssen.
## Player nutzt ihn um Geschwindigkeit und Schwerkraft aus PlayerStats zu laden.
func get_data() -> DataService:
	return null

## StatModifierService — für Entities die effektive Stat-Werte berechnen.
func get_stat_modifiers() -> StatModifierService:
	return null

## CombatSystem — für Entities die Schaden berechnen und anwenden müssen.
## EnemyNPC nutzt es in _on_interacted() um player_melee_damage() zu berechnen.
func get_combat_system() -> CombatSystem:
	return null

## EquipmentService — für Entities die ihr eigenes Equipment lesen/ändern müssen
## (z.B. Player beim Ausrüsten einer Waffe aus dem Inventar).
func get_equipment() -> EquipmentService:
	return null

## CurrencyService (ADR-033) — für Entities die Gold auszahlen müssen (z.B.
## EnemyNPC._die() für Goblin/Skelett-Gold-Drops).
func get_currency() -> CurrencyService:
	return null

## ADR-035: TradeService, für den einen Autoritäts-Einstiegspunkt
## on_invite_confirmed() — siehe Player._on_trade_requested()/TradeService.gd
## Klassenkommentar. Gibt null zurück wenn der Kontext diesen Service nicht
## bereitstellt (analog get_currency()).
func get_trade_service() -> TradeService:
	return null

## ADR-036: PvPDeathLossService, für Player._on_player_died() — wendet
## Item-/Gold-Verlust an, sobald ein PvP-Tod erkannt wird. Gibt null zurück
## wenn der Kontext diesen Service nicht bereitstellt (analog get_currency()).
func get_pvp_death_loss() -> PvPDeathLossService:
	return null

## ADR-036: AuraService, für Player._on_thank_requested(). Gibt null zurück
## wenn der Kontext diesen Service nicht bereitstellt (analog get_currency()).
func get_aura() -> AuraService:
	return null

## ADR-037: DeathLootService, für Player._on_player_died() (PvE-Zweig). Gibt
## null zurück wenn der Kontext diesen Service nicht bereitstellt (analog
## get_currency()).
func get_death_loot() -> DeathLootService:
	return null

## ADR-039: PickpocketService, für Player._on_pickpocket_requested(). Gibt
## null zurück wenn der Kontext diesen Service nicht bereitstellt (analog
## get_currency()).
func get_pickpocket() -> PickpocketService:
	return null

## AmbientSpawnService — für natürliche UND spielerplatzierte Spawner-
## Gräber (siehe Gravestone.gd/GraveyardGravestone.gd bzw. BuildPiece.gd),
## um sich für periodisches Skelett-Nachspawnen an-/abzumelden. Gibt null
## zurück wenn der Kontext diesen Service nicht bereitstellt (analog
## get_currency()) — z.B. reiner Client-/Test-Kontext.
func get_ambient_spawner() -> AmbientSpawnService:
	return null

## NetworkBridge — ADR-021 (R-5), Option C: für Entities, deren lokal (pro Peer)
## laufende Interaktionslogik keinen authority-geguardeten Hook hat (QuestNPC,
## QuestCustomTrigger) und die deshalb `report_domain_event()` selbst aufrufen
## müssen, um die Autorität überhaupt zu erreichen. Gibt null zurück wenn der
## Kontext keine NetworkBridge bereitstellt (z.B. reiner Test-Kontext ohne Netz).
func get_network_bridge() -> NetworkBridge:
	return null

## ADR-051 Stufe 3: QuestService-Lesezugriff für Entities, die Quest-Status
## VON ANDEREN Quests abfragen müssen, nicht nur die eigene (z.B. ein
## DialogueTreeController, der einen Gesprächszweig hinter "quest_x
## abgeschlossen" versteckt — siehe QuestNPC.gd/DialogueTreeController.gd).
## Rein lesend (is_quest_active()/is_quest_completed()) — kein
## Schreibpfad hier, der bleibt exklusiv über
## _bus.quest().emit_quest_start_requested() (ADR-021). Gibt null zurück wenn
## der Kontext keinen QuestService bereitstellt (analog get_network_bridge()).
func get_quest_service() -> QuestService:
	return null

# ─────────────────────────────────────────────
# Welt-Kontext
# ─────────────────────────────────────────────

## WorldService — für Entities die ihren Harvest-State markieren müssen
## (OakTree, IronOre nach on_despawn()).
func get_world() -> WorldService:
	return null

## InteractionExecutor — für InteractableComponent.start_default_interaction().
func get_interaction_executor() -> InteractionExecutor:
	return null

## Factory3D — für visuellen Setup in InteractableComponent und World-Entities.
## Für Entities die keinen vollen EntityContext benötigen.
func get_factory3d() -> Factory3D:
	return null

# ─────────────────────────────────────────────
# Lokale Spieler-Identität (ADR-015)
# ─────────────────────────────────────────────

## peer_id DIESES laufenden Prozesses (Tier 1: immer 1). NICHT zu verwechseln
## mit owner_peer_id einer konkreten Entity — get_local_peer_id() beantwortet
## "wer bin ich hier lokal", nicht "wem gehört diese eine Entity".
## Produktions-Implementierung delegiert an SessionManager.get_local_peer_id()
## (die bereits kanonische Quelle, siehe NetworkBridge) statt
## multiplayer.get_unique_id() ein zweites Mal selbst nachzubauen.
func get_local_peer_id() -> int:
	return 1

## Owner-Peer DIESER konkreten Entity — "wem gehört dieses Objekt", z. B. 1 für
## ein Weltobjekt egal welcher Spieler gerade damit interagiert, oder die
## peer_id des besitzenden Spielers für Player/Pet. NICHT zu verwechseln mit
## get_local_peer_id() ("wer bin ich hier lokal") und NICHT mit
## multiplayer_authority (die für Player künftig einheitlich beim Server liegt,
## ADR-025 — Ownership und Netzwerk-Autorität sind zwei verschiedene Fragen).
## EntityContext überschreibt das mit dem beim Spawn übergebenen owner_peer_id.
func get_owner_peer_id() -> int:
	return 1

## Bequemlichkeits-Wrapper um get_local_peer_id(): findet den Player-Node mit
## passendem "owner_peer_id"-Meta in der Gruppe "player". Ersetzt die zehn
## `get_nodes_in_group("player")[0]`-Stellen (ADR-015) durch eine einzige
## korrekte Quelle. Muster identisch zu PetComponent._find_owner(), das
## dasselbe Problem für Pet-Besitzer bereits löst.
##
## Nutzt bewusst das "owner_peer_id"-Meta (von EntityOrchestrator.spawn_entity()
## gesetzt) statt get_multiplayer_authority() — letztere beantwortet "wer ist
## Netzwerk-Autorität", nicht "wem gehört das Node". Für Player fielen beide
## Werte bisher zufällig zusammen; seit ADR-025 (Autorität = Server) gilt das
## nicht mehr, siehe TODO "BLOCKER für ADR-025/026-Umsetzung".
func get_local_player() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var my_id := get_local_peer_id()
	for p in tree.get_nodes_in_group("player"):
		if p is Node3D and p.get_meta("owner_peer_id", 1) == my_id:
			return p as Node3D
	# Fallback fuer Solo/Tier 1: genau ein Spieler in der Gruppe, Owner-
	# Abgleich ist dann ohnehin eindeutig — greift nur bei Timing-Lücken.
	return tree.get_first_node_in_group("player") as Node3D
