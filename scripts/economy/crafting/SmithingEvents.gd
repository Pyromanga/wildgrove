class_name SmithingEvents extends BaseEvents

## SmithingEvents — EventBus-Namespace für den Schmelz-/Schmiede-Service (SmithingService).
##
## Dasselbe Schema wie ShopEvents/BankEvents (ADR-050 Phase 2): `<domain>_<verb>_completed` /
## `<domain>_..._failed`, Konsumenten (Schmiede-Panel) holen sich den Service per DI und
## lauschen auf dem Bus statt auf einem nativen Service-Signal — es gibt hier bewusst KEINE
## nativen Signale am Service, also auch keine Namenskollision zu bereinigen.
##
## Einbinden: EventBus.gd (`var smithing: SmithingEvents`), IEventBus/EventBusAdapter.
##
## Verwendung:
##   ctx.bus().smithing().smithing_craft_completed.connect(_on_craft_completed)

## Emittiert nach jedem erfolgreichen Schmelzen/Schmieden — auf der Autorität (der Server
## läuft das Rezept). Auf einem Client kommt das Ergebnis über den Inventar-Sync an; das
## Panel aktualisiert sich über inventory_changed. `xp` ist die vergebene Skill-XP.
signal smithing_craft_completed(player_id: String, recipe_id: String, output_item_id: String, quantity: int, xp: int)

## Fehlgrund-Codes (siehe SmithingService.FAIL_*): "unknown_recipe", "invalid_player",
## "level_too_low", "missing_tool", "missing_ingredients", "inventory_full", "invalid_quantity".
signal smithing_craft_failed(player_id: String, recipe_id: String, reason: String)

## Ein Spieler hat eine Schmiede-Station (Hochofen/Amboss) benutzt — gemeldet von BuildPiece auf der
## AUTORITÄT (nie auf einem reinen Client). SmithingService merkt sich den Zeitpunkt und erlaubt
## Rezepte dieser Station nur innerhalb von SmithingService.STATION_ACCESS_SEC danach: Ein Client
## kann den Craft-RPC also nicht ohne Station "aus der Ferne" auslösen. station_kind ist
## "furnace" oder "anvil" (SmithingRecipe.STATION_*).
signal smithing_station_used(player_id: String, station_kind: String)

func _init() -> void:
	super._init("Events/Smithing")

func emit_smithing_station_used(player_id: String, station_kind: String) -> void:
	_log("Schmiede: '%s' benutzt Station '%s'." % [player_id, station_kind])
	smithing_station_used.emit(player_id, station_kind)

func emit_smithing_craft_completed(player_id: String, recipe_id: String, output_item_id: String, quantity: int, xp: int) -> void:
	_log("Schmiede: '%s' stellt %dx '%s' her (Rezept '%s', +%d XP)." % [player_id, quantity, output_item_id, recipe_id, xp])
	smithing_craft_completed.emit(player_id, recipe_id, output_item_id, quantity, xp)

func emit_smithing_craft_failed(player_id: String, recipe_id: String, reason: String) -> void:
	_log_warn("Schmiede fehlgeschlagen: '%s' / Rezept '%s' (%s)." % [player_id, recipe_id, reason])
	smithing_craft_failed.emit(player_id, recipe_id, reason)
