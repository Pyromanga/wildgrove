class_name VillageKinds
extends RefCounted

## VillageKinds — Register aller Dorf-Arten (siehe VillageKind). EINE Anlaufstelle: wer wissen will,
## welche Art ein Standort hat, welchen Katalog ein Gebäudetyp nutzt oder wie ein Tier heißt, fragt hier.
##
## NEUE ART HINZUFÜGEN: Klasse schreiben, in _create_all() instanziieren, ID in SPECIAL_ORDER
## ANHÄNGEN. Reihenfolge nie ändern/einfügen: Sie legt fest, welcher Würfelbereich zu welcher Art gehört —
## ein Einschub würde die Dörfer bestehender Welten umverteilen.

const KIND_GROUND := "ground"
const KIND_CANOPY := "canopy"

## Sonderarten in fester Reihenfolge. "ground" ist immer der Rückfall und steht nicht in der Liste.
const SPECIAL_ORDER: Array[String] = [KIND_CANOPY]

static var _kinds: Dictionary = {}
static var _type_owner: Dictionary = {}   # type_id → kind id (nur Sonderarten)

static func get_kind(kind_id: String) -> VillageKind:
	_ensure()
	return (_kinds.get(kind_id, _kinds[KIND_GROUND])) as VillageKind

## Art eines Standorts (fehlender Eintrag, etwa in alten Daten = "ground").
static func kind_of_site(site: Dictionary) -> VillageKind:
	return get_kind(String(site.get("kind", KIND_GROUND)))

static func all_ids() -> Array[String]:
	var out: Array[String] = [KIND_GROUND]
	out.append_array(SPECIAL_ORDER)
	return out

## Welche Arten werden für diesen Würfelwert (0..1) der Reihe nach versucht? Sonderarten teilen sich
## [0, Σ chance) in Abschnitte; der Rückfall "ground" steht immer am Ende.
static func ids_for_roll(roll: float) -> Array[String]:
	_ensure()
	var out: Array[String] = []
	var acc: float = 0.0
	for kind_id: String in SPECIAL_ORDER:
		var c: float = (_kinds[kind_id] as VillageKind).chance()
		if roll >= acc and roll < acc + c:
			out.append(kind_id)
		acc += c
	out.append(KIND_GROUND)
	return out

static func tier_label(site: Dictionary) -> String:
	return kind_of_site(site).tier_label(String(site.get("tier", "")))

## Katalog-Eintrag eines Sonderart-Gebäudetyps oder {} (Bodentypen liegen in BuildingRecipes.CATALOG).
static func entry_for(type_id: String) -> Dictionary:
	_ensure()
	var owner: String = String(_type_owner.get(type_id, ""))
	if owner.is_empty():
		return {}
	return (_kinds[owner] as VillageKind).catalog().get(type_id, {})

static func kind_of_type(type_id: String) -> VillageKind:
	_ensure()
	return get_kind(String(_type_owner.get(type_id, KIND_GROUND)))

static func _ensure() -> void:
	if not _kinds.is_empty():
		return
	_kinds[KIND_GROUND] = GroundVillageKind.new()
	_kinds[KIND_CANOPY] = CanopyVillageKind.new()
	for kind_id: String in SPECIAL_ORDER:
		for type_id: String in (_kinds[kind_id] as VillageKind).catalog():
			_type_owner[type_id] = kind_id
