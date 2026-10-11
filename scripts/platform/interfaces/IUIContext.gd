# res://scripts/platform/interfaces/IUIContext.gd
class_name IUIContext extends RefCounted

## IUIContext — Schmale Service-Fassade für UI-Controller.
##
## Analogon zu IEntityContext für den UI-Layer.
## Controller bekommen via setup(visuals, ctx) nur die Services die sie
## wirklich brauchen — testbar, ohne AutoLoad-Abhängigkeiten.
##
## VERWENDUNG:
##   HUDBuilder.build_all(hud, context) injiziert den Context via set_ui_context_factory().
##   In Tests: UIContext.for_test() mit Mock-Implementations.
##
## WICHTIG: Controller speichern den Context als _ctx: IUIContext.

## QuestService — für Panels die Quest-State lesen.
func get_quest() -> QuestService:
	return null

## SkillSystem — für Panels die Skill-Level/XP anzeigen.
func get_skill_system() -> SkillSystem:
	return null

## InventorySystem — für das Inventar-Panel.
func get_inventory() -> InventorySystem:
	return null

## EquipmentService — für das Equipment-Panel.
func get_equipment() -> EquipmentService:
	return null

## CurrencyService (ADR-033) — für die Gold-Anzeige im Inventory-Panel.
func get_currency() -> CurrencyService:
	return null

## ShopService (Round 88) — für das Shop-NPC-Panel (kaufen/verkaufen).
func get_shop() -> ShopService:
	return null

## SmithingService — für das Schmiede-Panel an Hochofen/Amboss (Rezepte, Herstellen).
func get_smithing() -> SmithingService:
	return null

## BankService (ADR-034) — für das Bank-NPC-Panel (ein-/auszahlen).
func get_bank() -> BankService:
	return null

## TradeService (ADR-035) — für das Handels-Panel (Angebot/Ready/Bestätigen).
func get_trade_service() -> TradeService:
	return null

## AuctionHouseService (ADR-035) — für das Auktionshaus-Panel (listen/kaufen).
func get_auction_house() -> AuctionHouseService:
	return null

## ItemProtectionService (ADR-038) — für das Inventar-Panel (Scroll auf Item anwenden).
func get_item_protection() -> ItemProtectionService:
	return null

## DataService — für Item-Definitionen in Equipment-Panel.
func get_data() -> DataService:
	return null

## WorldService — NUR für Lese-Abfragen der UI (Bau-Vorschau/Geist). Schreibende Wünsche
## (Bauen, Graben, Abreißen) laufen weiter über den EventBus (bus().world().emit_*_requested).
func get_world() -> WorldService:
	return null

## AchievementService (ADR-046) — für das Achievement-Panel (Round 104).
func get_achievement_service() -> AchievementService:
	return null

## CharacterCreationService (ADR-048) — für die Tutorial-Fragenreihe
## (Round 105).
func get_character_creation_service() -> CharacterCreationService:
	return null

## WikiService (ADR-049) — für das Wiki-Panel (Round 108).
func get_wiki_service() -> WikiService:
	return null

## SettingsService — für das Settings-Panel (Joystick/Kamera/Zoom/Rotation).
## Optional wie die anderen Facaden-Getter: Panels die es brauchen, prüfen
## selbst auf null (Service könnte in Tests/Editor-Previews fehlen).
func get_settings() -> SettingsService:
	return null

## IEventBus — Event-Zugriff für Controller die auf Signale lauschen oder welche emittieren.
## I-02 (AUDIT-03): schließt die UI-Hälfte von H-07/ADR-011 — Services injizieren IEventBus
## bereits korrekt via deps.require(EVENT_BUS); Controller griffen bisher direkt auf den
## EventBus-AutoLoad zu (EventBus.player.*, EventBus.ui.* …) statt über diesen Context.
##
## In Produktion: EventBusAdapter, aus derselben Session-Registry aufgelöst die auch
## Services ihren IEventBus gibt (ServiceKeys.EVENT_BUS) — identischer Adapter, keine
## zweite Implementierung.
## In Tests: MockEventBus (tests/mocks/MockEventBus.gd) — kein AutoLoad, kein SceneTree nötig.
##
## VERWENDUNG in Controllern:
##   var _ctx: IUIContext
##   func setup(visuals: ..., ctx: IUIContext) -> void:
##       _ctx = ctx
##       _ctx.bus().player().xp_gained.connect(_on_xp_gained)
##   Kein EventBus.player.xp_gained.connect(...) mehr in Controller-Code (ADR-012).
func bus() -> IEventBus:
	return null

# ─────────────────────────────────────────────
# Lokale Spieler-Identität (ADR-015)
# ─────────────────────────────────────────────

## peer_id DIESES laufenden Prozesses. Analog zu IEntityContext.get_local_peer_id()
## — dieselbe Primitive, zweites Interface, damit UI-Controller sie ohne
## AutoLoad/Gruppen-Scan bekommen. Produktions-Implementierung delegiert an
## SessionManager.get_local_peer_id().
func get_local_peer_id() -> int:
	return 1

## ADR-029 Plan-Schritt 4 (Round 63): stabile player_id (String) DIESES
## laufenden Prozesses — Pendant zu get_local_peer_id() (int, Routing-Identität,
## ADR-015), für Panels die gegen bereits migrierte Services (bisher:
## InventorySystem) lesen. Produktions-Implementierung delegiert an
## SessionManager.get_local_player_id() (über UIContext.from_registry()).
## Leerer String als Default statt eines geratenen Platzhalters — Panels die
## damit nicht umgehen können, sollen das sichtbar bemerken statt still gegen
## den falschen Bucket zu lesen.
func get_local_player_id() -> String:
	return ""

## Ersetzt `get_nodes_in_group("player")[0]` — vormals u. a. in
## `InventoryUIController._find_local_player_visuals()`, dessen Name diese
## Korrektheit versprach, ohne sie zu haben (siehe ADR-015). Diese Kopie
## existiert seit ADR-027 nicht mehr — Equip-Visuals werden jetzt
## autoritätsseitig über WorldService.get_player_visuals(peer_id) aufgelöst,
## nicht mehr lokal vom aufrufenden UI-Controller.
##
## Nutzt das "owner_peer_id"-Meta (von EntityOrchestrator.spawn_entity() gesetzt),
## nicht get_multiplayer_authority() — "wem gehört das Node" und "wer ist
## Netzwerk-Autorität" sind zwei verschiedene Fragen, die für Player nur
## zufällig denselben Wert hatten. Seit ADR-025 (Autorität = Server für
## Player-Nodes) gilt das nicht mehr, siehe TODO "BLOCKER für
## ADR-025/026-Umsetzung".
func get_local_player() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	var my_id := get_local_peer_id()
	for p in tree.get_nodes_in_group("player"):
		if p is Node3D and p.get_meta("owner_peer_id", 1) == my_id:
			return p as Node3D
	return tree.get_first_node_in_group("player") as Node3D
