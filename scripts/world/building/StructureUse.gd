class_name StructureUse
extends RefCounted

## StructureUse — die Nutzung einer Struktur (BuildPieceDefinition.use_*): Zutaten verbrauchen,
## Ergebnis ins Inventar legen. Zustandslose Utility wie InteractionResolver (kein Service): es gibt
## EINE feste Aktion je Bauteil, keine Auswahl unter vielen Rezepten wie beim Schmieden.
##
## Läuft ausschließlich auf der Autorität (Aufrufer: BuildPiece._on_interacted(), dort per
## is_multiplayer_authority() abgesichert). Was verbraucht/gegeben wird, steht in der Definition —
## der Client schickt nur "ich habe das Bauteil benutzt".

const FAIL_NO_USE := "no_use"
const FAIL_INVALID_PLAYER := "invalid_player"
const FAIL_MISSING := "missing_items"
const FAIL_INVENTORY_FULL := "inventory_full"
const FAIL_COOLDOWN := "cooldown"

## Warum kann player_id das Bauteil JETZT nicht nutzen? "" = geht. Prüft nur Zutaten (reine
## Lesefunktion — der Client nutzt sie für eine sofortige Rückmeldung, die Autorität zusätzlich
## Cooldown und Inventarplatz in use()).
static func check(def: BuildPieceDefinition, player_id: String, inventory: InventorySystem) -> String:
	if def == null or not def.has_use():
		return FAIL_NO_USE
	if player_id.is_empty() or not is_instance_valid(inventory):
		return FAIL_INVALID_PLAYER
	for item_id in def.use_consumes:
		if not inventory.has_item(String(item_id), player_id, int(def.use_consumes[item_id])):
			return FAIL_MISSING
	return ""

## Führt die Nutzung aus. `last_use_msec`: Zeitpunkt der letzten Nutzung dieses Bauteils durch
## diesen Spieler (0 = nie), `now_msec` die Uhr — beides vom Aufrufer, damit Tests keine echte Zeit
## brauchen. Gibt "" bei Erfolg zurück, sonst den Fehlgrund (FAIL_*). Bei vollem Inventar werden
## verbrauchte Zutaten zurückgegeben.
static func use(def: BuildPieceDefinition, player_id: String, inventory: InventorySystem,
		last_use_msec: int, now_msec: int) -> String:
	var reason := check(def, player_id, inventory)
	if not reason.is_empty():
		return reason
	if last_use_msec > 0 and float(now_msec - last_use_msec) / 1000.0 < def.use_cooldown:
		return FAIL_COOLDOWN
	var taken: Dictionary = {}
	for item_id in def.use_consumes:
		var qty := int(def.use_consumes[item_id])
		if not inventory.remove_item(String(item_id), player_id, qty):
			_refund(inventory, player_id, taken)
			return FAIL_MISSING
		taken[String(item_id)] = qty
	var given: Dictionary = {}
	for item_id in def.use_gives:
		var qty := int(def.use_gives[item_id])
		if not inventory.request_add_item(String(item_id), player_id, qty):
			# Schon Gegebenes ließe sich nur mit remove_item zurücknehmen — alle Ergebnisse
			# gehören zu einer Nutzung, deshalb alles zurückdrehen.
			for gid in given:
				inventory.remove_item(String(gid), player_id, int(given[gid]))
			_refund(inventory, player_id, taken)
			return FAIL_INVENTORY_FULL
		given[String(item_id)] = qty
	return ""

static func _refund(inventory: InventorySystem, player_id: String, taken: Dictionary) -> void:
	for item_id in taken:
		inventory.request_add_item(String(item_id), player_id, int(taken[item_id]))

## Deutscher Hinweistext für einen Fehlgrund (Benachrichtigung am Bildschirm).
static func reason_text(reason: String, def: BuildPieceDefinition = null, data: DataService = null) -> String:
	match reason:
		FAIL_MISSING:
			var parts: PackedStringArray = []
			if def != null:
				for item_id in def.use_consumes:
					var item: ItemDefinition = data.get_item(String(item_id)) if data != null else null
					var item_name: String = item.display_name if item != null else String(item_id)
					parts.append("%dx %s" % [int(def.use_consumes[item_id]), item_name])
			return "Dir fehlt: %s." % ", ".join(parts) if not parts.is_empty() else "Dir fehlen Zutaten."
		FAIL_INVENTORY_FULL:
			return "Inventar voll."
		FAIL_COOLDOWN:
			return "Einen Moment noch."
		_:
			return "Das geht gerade nicht."
