class_name ItemInstance
extends RefCounted

## ItemInstance — Laufzeit-Repräsentation eines einzelnen Inventar-Items.
##
## ADR-035 Phase 1 (Round 88): Migration ausgeführt. InventorySystem/BankService
## speichern ihre Item-Buckets jetzt als { item_id: ItemInstance } (vorher
## { item_id: quantity(int) }) — der Dictionary-KEY bleibt item_id (unveränderte
## Slot-Semantik: ein Slot pro Item-Typ, Menge weiter bei def.max_stack gedeckelt),
## aber der VALUE ist jetzt ein Objekt mit stabiler `uuid` statt eines rohen int.
##
## GRUND: TradeService/AuctionHouseService (ADR-035) brauchen eine autoritäts-
## vergebene, client-unfälschbare Referenz auf ein konkretes Item — dieselbe
## Vertrauenseigenschaft wie `entity_uuid` (ADR-023), nur für Inventar-Items
## statt Welt-Entities (ADR-023 selbst deckt Inventar-Items nicht ab, siehe
## docs/adr/035-trading.md Umsetzungsnotiz). `uuid` wird hier über UuidGen
## (RFC-4122-v4, siehe scripts/persistence/UuidGen.gd) erzeugt; Autoritäts-
## Zwang kommt indirekt aus den bereits bestehenden Guards an den Aufrufstellen
## (InventorySystem.on_item_add_confirmed()/BankService.on_deposit_item_confirmed()
## sind schon auf "nur Autorität" geprüft) — kein zusätzlicher Guard hier nötig.
##
## BEKANNTE EINSCHRÄNKUNG (bewusst, nicht Teil dieser Phase): weiterhin genau
## EINE ItemInstance pro item_id pro Spieler-Bucket (wie zuvor die Menge pro
## Slot gedeckelt war) — kein "mehrere gleichzeitig besessene, unterschiedliche
## Instanzen desselben Item-Typs" (z.B. zwei Schwerter mit unterschiedlich
## gewürfeltem Schaden). Das würde echtes Stack-Splitting + Array[ItemInstance]
## brauchen (das hier absichtlich NICHT gemacht wurde — größerer, eigenständiger
## Umbau, aktuell kein Bedarf: `durability` existiert, wird aber nirgends
## gesetzt/genutzt; Stat-Rolls existieren im Code nicht). Folgeschritt, falls/
## wenn Stat-Rolls tatsächlich gebaut werden.
##
## ADR-038 (Item-Schutz-Dreiklang): profitiert direkt von der "eine Instanz pro
## item_id pro Spieler"-Einschränkung oben — item_id + player_id identifiziert
## die Instanz bereits eindeutig, ItemProtectionService braucht deshalb keinen
## eigenen uuid-basierten Lookup-Pfad, sondern liest/schreibt die drei
## is_*_protected-Felder unten direkt über InventorySystem.get_item_instance().

var definition: ItemDefinition
var quantity:   int    = 1
var durability: float  = 100.0
var uuid:       String = ""

## ADR-038: Item-Schutz-Dreiklang — Instanz-Zustand, kein Item-Typ-Flag (siehe
## ADR "Entscheidung"). Gesetzt/gelesen ausschließlich über ItemProtectionService,
## nie direkt von anderen Aufrufern mutiert (analog "nur Autorität mutiert" für
## andere Instanz-Felder, hier zusätzlich ausschließlich über den einen Service).
## is_pve_death_protected/is_theft_protected: permanent, einmal gesetzt nie
## automatisch zurückgesetzt. is_pvp_protected: einmalig verbrauchend — wird
## nach einem auslösenden PvP-Tod-Ereignis (künftig ADR-036) über
## ItemProtectionService.consume_pvp_protection() automatisch auf false gesetzt.
var is_pve_death_protected: bool = false
var is_theft_protected:     bool = false
var is_pvp_protected:       bool = false

func _init(def: ItemDefinition, qty: int = 1, item_uuid: String = "") -> void:
	self.definition = def
	self.quantity   = qty
	self.uuid       = item_uuid if not item_uuid.is_empty() else UuidGen.generate_v4()

func get_id() -> String:
	return definition.id if definition else ""

func get_display_name() -> String:
	return definition.display_name if definition else "???"

func is_stackable() -> bool:
	return definition.max_stack > 1 if definition else false

func is_broken() -> bool:
	return durability <= 0.0

## Serialisierungsform für Save-Daten UND Netzwerk-Sync (RPC-Payloads können
## keine RefCounted-Objekte übertragen — nur Dictionary/Array/Primitive).
func to_dict() -> Dictionary:
	return {
		"item_id":    get_id(),
		"quantity":   quantity,
		"durability": durability,
		"uuid":       uuid,
		# ADR-038:
		"is_pve_death_protected": is_pve_death_protected,
		"is_theft_protected":     is_theft_protected,
		"is_pvp_protected":       is_pvp_protected,
	}

## Gegenstück zu to_dict(). `def` muss vom Aufrufer aufgelöst werden (per
## item_id-Lookup in der jeweiligen Item-Registry) — ItemInstance kennt keine
## Registry selbst. Gibt null zurück wenn `def` null ist (unbekanntes Item,
## z.B. aus einem alten/korrupten Save) statt eine kaputte Instanz zu bauen.
static func from_dict(data: Dictionary, def: ItemDefinition) -> ItemInstance:
	if not def:
		return null
	var inst := ItemInstance.new(def, int(data.get("quantity", 1)), String(data.get("uuid", "")))
	inst.durability = float(data.get("durability", 100.0))
	# ADR-038: fehlt in älteren (Pre-ADR-038) Saves — Default false ist korrekt
	# (kein Item war vor diesem ADR jemals geschützt).
	inst.is_pve_death_protected = bool(data.get("is_pve_death_protected", false))
	inst.is_theft_protected     = bool(data.get("is_theft_protected", false))
	inst.is_pvp_protected       = bool(data.get("is_pvp_protected", false))
	return inst
