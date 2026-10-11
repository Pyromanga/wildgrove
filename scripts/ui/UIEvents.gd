class_name UIEvents extends BaseEvents

## UIEvents.gd
## UI-spezifische Signale.
##
## request_context_menu — neu; wird von ContextButtonController gefeuert und
## von ContextMenuController empfangen. Vorher fehlte die Deklaration hier,
## was zur Laufzeit zu einem "Signal not found"-Fehler geführt hätte.

signal layout_requested(state: String)
signal menu_toggled(menu_name: String, is_visible: bool)
signal overlay_changed(overlay_type: String, active: bool)

signal joystick_moved(origin: Vector2, offset: Vector2)
signal joystick_toggled(is_active: bool, origin: Vector2)

## Wird von ContextButtonController gesendet, wenn der Spieler den Kontext-Button drückt.
## ContextMenuController empfängt es und öffnet das Menü mit den verfügbaren Aktionen.
signal request_context_menu

## Wird von beliebigen UI-Layern gesendet um eine Kurznotiz anzuzeigen.
## NotificationController lauscht hierauf.
signal notification_requested(text: String)

## Wird gesendet wenn ein Item gedroppt/aufgesammelt wird.
## FloatingTextController zeigt den Text kurz im HUD an.
## world_pos ist die 3D-Position des Drops (optional, wird ggf. ignoriert wenn kein Camera3D).
signal floating_loot_text_requested(text: String, world_pos: Vector3)

## Wird von UI-Controllern gesendet wenn eine Interaktion ausgeführt werden soll.
## InteractionExecutor lauscht hierauf.
signal interaction_execute_requested(action: InteractableAction)

## Szenen-Wechsel vom UI angefordert (z.B. Neu laden im Pause-Menü).
signal scene_reload_requested

## Round 88: Shop-NPC wurde interagiert — öffnet das Shop-Panel.
## npc_display_name nur für den Panel-Titel, keine Gameplay-relevante ID.
signal shop_opened(npc_display_name: String)
signal shop_closed

## Pet-Kampf: ein Dorfbewohner wurde (lokal vom interagierenden Spieler) herausgefordert → öffnet das
## Kampf-Fenster (PetBattleController). villager_key = Node-Name des Dorfbewohners (Rückmeldung unten),
## enemy_seed = Seed seines Gegner-Teams (PetBattleEncounter.seed_for), bias_type = bevorzugter Typ
## seines Berufs (PetBattleTypes.Type, -1 = keiner).
signal pet_battle_requested(villager_key: String, villager_name: String, enemy_seed: int, bias_type: int)
## Kampf ist vorbei: der Dorfbewohner merkt sich das (Ruhepause + nächstes Team nach einem Sieg).
signal pet_battle_finished(villager_key: String, won: bool)

## Schmelzen & Schmieden: ein Hochofen/Amboss (BuildPiece mit station_kind) wurde interagiert —
## öffnet das Schmiede-Panel für diese Station. station_kind ist "furnace" oder "anvil"
## (SmithingRecipe.STATION_*), station_name nur der Panel-Titel (z.B. "Hochofen").
signal smithing_opened(station_kind: String, station_name: String)
signal smithing_closed

## Lokaler Bau-Modus (Bau-Menü offen oder Platzieren aktiv) hat sich geändert — siehe
## BuildModeState. BuildPieces blenden darüber "Abreißen" ein/aus.
signal build_mode_changed(active: bool)

## ADR-034: Bank-NPC wurde interagiert — öffnet das Bank-Panel.
signal bank_opened(npc_display_name: String)
signal bank_closed

## ADR-035: Auktionshaus-NPC wurde interagiert — öffnet das Auktionshaus-Panel.
## Bewusst KEIN "trade_opened"-Gegenstück: der Handshake-Handel wird nicht über
## einen NPC geöffnet, sondern über TradeService.invite_received/session_started
## direkt (siehe TradeService.gd) — die zukünftige TradeUIController abonniert
## das direkt über get_trade_service(), kein NPC-Zwischenschritt nötig (anders
## als bei Bank/Shop/Auktionshaus, deren "öffnen" keinen zweiten Teilnehmer hat).
signal auction_house_opened(npc_display_name: String)
signal auction_house_closed

## Hauptmenü vom UI angefordert (z.B. "Hauptmenü"-Button im Pause-Menü).
signal main_menu_requested

func _init() -> void:
	super._init("Events/UI")

# --- Logik-Emitter ---

func emit_layout_requested(state: String) -> void:
	_log("Layout Änderung angefordert: %s" % state)
	layout_requested.emit(state)

func emit_menu_toggled(menu_name: String, is_visible: bool) -> void:
	_log("Menü '%s' sichtbar: %s" % [menu_name, is_visible])
	menu_toggled.emit(menu_name, is_visible)

func emit_overlay_changed(overlay_type: String, active: bool) -> void:
	_log("Overlay '%s' Status: %s" % [overlay_type, active])
	overlay_changed.emit(overlay_type, active)

func emit_joystick_toggled(is_active: bool, origin: Vector2 = Vector2.ZERO) -> void:
	_log("Joystick aktiv: %s" % is_active)
	joystick_toggled.emit(is_active, origin)

func emit_joystick_moved(origin: Vector2, offset: Vector2) -> void:
	joystick_moved.emit(origin, offset)

func emit_request_context_menu() -> void:
	_log("Kontext-Menü angefordert.")
	request_context_menu.emit()

func emit_notification_requested(text: String) -> void:
	_log("Notification: %s" % text)
	notification_requested.emit(text)

func emit_floating_loot_text_requested(text: String, world_pos: Vector3 = Vector3.ZERO) -> void:
	floating_loot_text_requested.emit(text, world_pos)

func emit_interaction_execute_requested(action: InteractableAction) -> void:
	_log("Interaktion ausführen: '%s'" % action.label)
	interaction_execute_requested.emit(action)

func emit_scene_reload_requested() -> void:
	_log("Szenen-Reload angefordert.")
	scene_reload_requested.emit()

func emit_shop_opened(npc_display_name: String) -> void:
	_log("Shop geöffnet: '%s'" % npc_display_name)
	shop_opened.emit(npc_display_name)

func emit_shop_closed() -> void:
	shop_closed.emit()

func emit_pet_battle_requested(villager_key: String, villager_name: String, enemy_seed: int, bias_type: int) -> void:
	_log("Pet-Kampf angefordert gegen '%s'." % villager_name)
	pet_battle_requested.emit(villager_key, villager_name, enemy_seed, bias_type)

func emit_pet_battle_finished(villager_key: String, won: bool) -> void:
	pet_battle_finished.emit(villager_key, won)

func emit_build_mode_changed(active: bool) -> void:
	_log("Bau-Modus: %s" % ("an" if active else "aus"))
	build_mode_changed.emit(active)

func emit_smithing_opened(station_kind: String, station_name: String) -> void:
	_log("Schmiede-Panel geöffnet: '%s' (%s)" % [station_name, station_kind])
	smithing_opened.emit(station_kind, station_name)

func emit_smithing_closed() -> void:
	smithing_closed.emit()

func emit_bank_opened(npc_display_name: String) -> void:
	_log("Bank geöffnet: '%s'" % npc_display_name)
	bank_opened.emit(npc_display_name)

func emit_bank_closed() -> void:
	bank_closed.emit()

func emit_auction_house_opened(npc_display_name: String) -> void:
	_log("Auktionshaus geöffnet: '%s'" % npc_display_name)
	auction_house_opened.emit(npc_display_name)

func emit_auction_house_closed() -> void:
	auction_house_closed.emit()

func emit_main_menu_requested() -> void:
	_log("Hauptmenü angefordert.")
	main_menu_requested.emit()
