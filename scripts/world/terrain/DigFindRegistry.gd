class_name DigFindRegistry
extends RefCounted

## DigFindRegistry — die WAHRHEIT darüber, welche Funde (Erz/Edelsteine) am Boden liegen.
##
## Gleiches Muster wie BuildRegistry/LadderRegistry: die 3D-Entities (DigFind) sind nur eine
## Ansicht, WorldDigHandler erzeugt sie beim Laden eines Chunks. Ein Fund verschwindet erst,
## wenn er geborgen wird — nicht durch Chunk-Entladen und nicht durch Speichern/Laden.
##
## Record: {key, kind (DigFindTable-Art), x, y, z}
## Reine Datenklasse: kein Node, kein Service.

var _records: Dictionary = {}   # { key: Dictionary }

## Schlüssel aus der Position (auf 0,1 m gerundet, y spielt keine Rolle: Funde werden auf den
## Boden gesetzt, an einer x/z-Stelle liegt höchstens einer).
static func make_key(x: float, z: float) -> String:
	return "F_%d_%d" % [roundi(x * 10.0), roundi(z * 10.0)]

func count() -> int:
	return _records.size()

func has_key(key: String) -> bool:
	return _records.has(key)

func get_record(key: String) -> Dictionary:
	return (_records.get(key, {}) as Dictionary).duplicate()

func get_all() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for k in _records.keys():
		out.append((_records[k] as Dictionary).duplicate())
	return out

## false bei fehlendem Schlüssel, Doppelbelegung oder unbekannter Art.
func add(record: Dictionary) -> bool:
	var key: String = String(record.get("key", ""))
	if key.is_empty() or _records.has(key):
		return false
	if not DigFindTable.is_known(String(record.get("kind", ""))):
		return false
	_records[key] = record.duplicate()
	return true

## Entfernt einen Record und gibt ihn zurück ({} wenn nicht vorhanden).
func remove(key: String) -> Dictionary:
	if not _records.has(key):
		return {}
	var rec: Dictionary = _records[key]
	_records.erase(key)
	return rec

## Setzt die Höhe eines Fundes (nach Graben/Füllen). false, wenn es ihn nicht gibt.
func set_height(key: String, y: float) -> bool:
	if not _records.has(key):
		return false
	(_records[key] as Dictionary)["y"] = y
	return true

func clear() -> void:
	_records.clear()

## Alle Funde im waagerechten Umkreis `radius` um (x, z).
func near(x: float, z: float, radius: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _records.values():
		var dx: float = float(rec.get("x", 0.0)) - x
		var dz: float = float(rec.get("z", 0.0)) - z
		if sqrt(dx * dx + dz * dz) <= radius:
			out.append(rec.duplicate())
	return out

func records_in_chunk(chunk_coord: Vector2i, chunk_size: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in _records.values():
		if BuildRegistry.chunk_of(float(rec.get("x", 0.0)), float(rec.get("z", 0.0)), chunk_size) == chunk_coord:
			out.append(rec.duplicate())
	return out

func to_save() -> Array:
	var out: Array = []
	for rec: Dictionary in _records.values():
		out.append(rec.duplicate())
	return out

## Lädt aus to_save()-Format. Ungültige Einträge werden übersprungen.
func load_save(raw: Variant) -> void:
	clear()
	if not raw is Array:
		return
	for entry in (raw as Array):
		if not entry is Dictionary:
			continue
		var rec: Dictionary = entry
		if not (rec.has("x") and rec.has("y") and rec.has("z")):
			continue
		add(rec)
