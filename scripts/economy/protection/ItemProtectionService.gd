extends Service
class_name ItemProtectionService

## ItemProtectionService — ADR-038: Item-Schutz-Dreiklang (PvE-Todesschutz,
## Diebstahlschutz, PvP-Schutz). Zentraler Anwendungs- UND Abfragepunkt für
## alle drei Schutzarten — konsumiert künftig von ADR-036 (PvP-Tod-Verlust),
## ADR-037 (PvE-Tod-Loot) und ADR-039 (Pickpocketing).
##
## SPEICHERORT: kein eigener Save-Bucket. Schutz ist laut ADR ein
## Item-INSTANZ-Zustand, nicht eigener Service-State — die drei is_*_protected-
## Felder leben direkt auf ItemInstance (siehe dort) und werden von
## InventorySystem bereits mit-serialisiert/mit-synchronisiert (Save UND
## Netzwerk-Rücksync). Dieser Service ist damit zustandslos: er liest/schreibt
## ausschließlich über InventorySystem.get_item_instance().
##
## MUSTER: identisch zu BankService/ShopService (Absicht statt Wert,
## request_*() routet/prüft, on_*_confirmed() mutiert NUR auf der Autorität,
## eigenes NetworkBridge-Routing weil die UI auf dem Peer des anwendenden
## Spielers läuft, nicht zwingend der Autorität).
##
## SICHERHEITS-ABWEICHUNG von der ADR-Pseudo-Signatur: die ADR skizziert
## `request_apply_protection(item_ref, protection_type)`. Hier bewusst
## `request_apply_protection(scroll_item_id, target_item_id, player_id)` —
## OHNE protection_type als Parameter. Der protection_type wird ausschließlich
## serverseitig aus der ItemDefinition des Scrolls gelesen
## (ItemDefinition.grants_protection_type). Ein separater, client-gesendeter
## protection_type-Parameter wäre fälschbar: ein Client könnte ein billiges
## Scroll mit einem selbstgewählten protection_type="pvp" einreichen und so
## den teuersten Schutz mit dem billigsten Scroll erkaufen. "Absicht statt
## Wert" heißt hier: der Client meldet NUR, welches Scroll er auf welches
## Ziel anwenden möchte — was das Scroll bewirkt, bestimmt einzig seine
## Definition, nicht die Anfrage.

signal protection_applied(player_id: String, item_id: String, protection_type: String)
signal application_failed(player_id: String, reason: String)
signal pvp_protection_consumed(player_id: String, item_id: String)

const LOG_CAT := "ItemProtection"

## Werte für protection_type / threat_type — identisch zu
## ItemDefinition.grants_protection_type.
const TYPE_PVE   := "pve"
const TYPE_THEFT := "theft"
const TYPE_PVP    := "pvp"
const VALID_TYPES := [TYPE_PVE, TYPE_THEFT, TYPE_PVP]

var _inventory: InventorySystem = null
var _network:   NetworkBridge   = null

# ─────────────────────────────────────────────
# Phase 4: Configure (DI)
# ─────────────────────────────────────────────

func configure(deps: ServiceDeps) -> void:
	_inventory = deps.require(ServiceKeys.INVENTORY) as InventorySystem
	_network   = deps.get_optional(ServiceKeys.NETWORK_BRIDGE) as NetworkBridge
	AppLogger.log_info("ItemProtectionService initialisiert.", LOG_CAT)

## Phase C8 Late-Inject (siehe BootPipeline.gd) — analog Bank/Shop/Trade.
func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network

# ─────────────────────────────────────────────
# Öffentliche API — Abfrage (von ADR-036/037/039 konsumiert)
# ─────────────────────────────────────────────

## Zentraler Abfragepunkt für alle drei konsumierenden ADRs: "ist item_id von
## player_id gegen threat_type (TYPE_PVE/TYPE_THEFT/TYPE_PVP) geschützt?"
## false für unbekannte player_id/item_id/threat_type statt zu crashen — ein
## fehlender Schutz ist der sichere Default (kein Item ist geschützt, solange
## nichts anderes belegt ist).
func is_protected_from(player_id: String, item_id: String, threat_type: String) -> bool:
	var inst := _get_instance(player_id, item_id)
	if not inst:
		return false
	match threat_type:
		TYPE_PVE:
			return inst.is_pve_death_protected
		TYPE_THEFT:
			return inst.is_theft_protected
		TYPE_PVP:
			return inst.is_pvp_protected
		_:
			AppLogger.log_error("is_protected_from: unbekannter threat_type '%s'." % threat_type, LOG_CAT)
			return false

# ─────────────────────────────────────────────
# Öffentliche API — Anwendung (Scroll auf Item)
# ─────────────────────────────────────────────

## Absicht: "wende scroll_item_id (aus dem Inventar von player_id) auf
## target_item_id (ebenfalls aus dessen Inventar) an". Kein protection_type-
## Parameter — siehe Klassenkommentar "SICHERHEITS-ABWEICHUNG".
func request_apply_protection(scroll_item_id: String, target_item_id: String, player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_item_protection_apply(scroll_item_id, target_item_id, player_id)
	else:
		on_apply_protection_confirmed(scroll_item_id, target_item_id, player_id)

func on_apply_protection_confirmed(scroll_item_id: String, target_item_id: String, player_id: String) -> void:
	if not _require_authority("on_apply_protection_confirmed"):
		return

	if not is_instance_valid(_inventory):
		application_failed.emit(player_id, "no_inventory")
		return

	if scroll_item_id == target_item_id:
		application_failed.emit(player_id, "cannot_target_scroll_itself")
		return

	var scroll_def := _inventory.get_item_info(scroll_item_id)
	if not scroll_def:
		application_failed.emit(player_id, "unknown_scroll")
		return

	var protection_type: String = scroll_def.grants_protection_type
	if protection_type.is_empty() or not VALID_TYPES.has(protection_type):
		application_failed.emit(player_id, "not_a_protection_scroll")
		return

	if not _inventory.has_item(scroll_item_id, player_id, 1):
		application_failed.emit(player_id, "scroll_not_owned")
		return

	var target_inst := _inventory.get_item_instance(player_id, target_item_id)
	if not target_inst:
		application_failed.emit(player_id, "target_not_owned")
		return

	if is_protected_from(player_id, target_item_id, protection_type):
		application_failed.emit(player_id, "already_protected")
		return

	# Scroll ZUERST konsumieren: has_item() oben hat den Bestand bereits
	# geprüft, remove_item() kann an dieser Stelle nur noch aus einem bereits
	# ausgeschlossenen Grund fehlschlagen — Reihenfolge stellt trotzdem sicher,
	# dass niemals ein Schutz gesetzt wird, ohne dass das Scroll auch wirklich
	# verbraucht wurde (kein "kostenloser Schutz"-Fenster).
	if not _inventory.remove_item(scroll_item_id, player_id, 1):
		application_failed.emit(player_id, "scroll_not_owned")
		return

	match protection_type:
		TYPE_PVE:
			target_inst.is_pve_death_protected = true
		TYPE_THEFT:
			target_inst.is_theft_protected = true
		TYPE_PVP:
			target_inst.is_pvp_protected = true

	protection_applied.emit(player_id, target_item_id, protection_type)
	AppLogger.log_debug(
		"Schutz angewendet: Typ '%s' auf '%s' für Spieler '%s' (Scroll '%s' verbraucht)."
		% [protection_type, target_item_id, player_id, scroll_item_id],
		LOG_CAT
	)

# ─────────────────────────────────────────────
# Öffentliche API — Verbrauch (für künftiges ADR-036)
# ─────────────────────────────────────────────

## Wird von ADR-036 (PvP-Tod-Verlust) nach genau EINEM auslösenden PvP-Tod-
## Ereignis aufgerufen, um den einmalig verbrauchenden PvP-Schutz
## zurückzusetzen. Autorität-only wie on_apply_protection_confirmed() — ADR-036
## selbst läuft bereits ausschließlich auf der Autorität (Tod-Verlust ist immer
## eine Server-Entscheidung), dieser Guard ist trotzdem Verteidigung in der
## Tiefe, analog InventorySystem.on_item_add_confirmed().
## Gibt false zurück wenn nichts zu konsumieren war (kein Item, kein aktiver
## Schutz) — Aufrufer kann das nutzen, um zwischen "Schutz hat gegriffen" und
## "kein Schutz vorhanden" zu unterscheiden.
func consume_pvp_protection(player_id: String, item_id: String) -> bool:
	if not _require_authority("consume_pvp_protection"):
		return false
	var inst := _get_instance(player_id, item_id)
	if not inst or not inst.is_pvp_protected:
		return false
	inst.is_pvp_protected = false
	pvp_protection_consumed.emit(player_id, item_id)
	AppLogger.log_debug("PvP-Schutz verbraucht: '%s' für Spieler '%s'." % [item_id, player_id], LOG_CAT)
	return true

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

func _get_instance(player_id: String, item_id: String) -> ItemInstance:
	if not is_instance_valid(_inventory):
		return null
	return _inventory.get_item_instance(player_id, item_id)

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true
