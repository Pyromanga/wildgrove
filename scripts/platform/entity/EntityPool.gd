class_name EntityPool
extends RefCounted

## EntityPool — Object-Pooling für World-Entities.
##
## Verantwortung:
##   - Despawnte Entities zwischenspeichern für Wiederverwendung
##   - Pool-Größe pro Typ begrenzen (default_max_size, optional pro Typ überschreibbar)
##   - Nodes aus dem SceneTree entfernen bevor sie gelagert werden
##
## Verwendet von EntityOrchestrator für _create_or_pool() und _try_return_to_pool().

const LOG_CAT := "EntityPool"

## Default-Limit für Typen ohne explizites Override (vorher: hartcodierte POOL_SIZE).
var default_max_size: int = 10

## Optionale Pro-Typ-Limits — überschreiben default_max_size für einzelne type_id.
## Sinnvoll wenn ein Typ deutlich häufiger gespawnt wird als andere
## (z.B. Bäume vs. seltene Boss-Encounter).
var _max_size_overrides: Dictionary = {}

## { type_id: Array[Node3D] }
var _pool: Dictionary = {}

## Statistiken (spiegeln EntityOrchestrator._stats für Pool-Entries)
var pool_hits:   int = 0
var pool_misses: int = 0

## Optionaler "Park"-Container für gepoolte (inaktive) Entities. OHNE dieses Feld verhält
## sich release() wie ursprünglich: entity.get_parent().remove_child(entity) lässt die Node
## komplett ohne Parent im Pool liegen — Godots Performance-Monitor zählt das per Definition
## als "verwaiste Node" (OBJECT_ORPHAN_NODE_COUNT), auch wenn hier bewusst fürs Pooling und
## durch die Pool-Limits gedeckelt.
## BUGFIX (2026-09-26, "Telemetrie meldet ständig verwaiste Nodes"): mit gesetztem Container
## werden released Entities dorthin REPARENTED statt komplett entparent zu werden — sie
## bleiben damit normale (nur unsichtbare/inaktive) Kindnodes, keine Orphans mehr, ohne dass
## sich am Pooling-Verhalten selbst (Limits, Wiederverwendung) etwas ändert.
## EntityOrchestrator setzt diesen Container in _ready(). Ohne set_park_container()-Aufruf
## (z.B. die bestehenden Unit-Tests dieser Klasse) bleibt exakt das alte Verhalten erhalten —
## kein bestehender Test musste dafür angepasst werden.
var _park_container: Node = null

func _init(p_default_max_size: int = 10) -> void:
	default_max_size = p_default_max_size

## Setzt den Park-Container für gepoolte Entities — siehe Feldkommentar oben.
func set_park_container(container: Node) -> void:
	_park_container = container

## Setzt ein individuelles Pool-Limit für einen bestimmten Entity-Typ.
## Überschreibt default_max_size nur für diese type_id.
func set_max_size_for(type_id: String, max_size: int) -> void:
	if max_size < 0:
		AppLogger.log_warn(
			"set_max_size_for('%s', %d): negativer Wert ignoriert." % [type_id, max_size],
			LOG_CAT
		)
		return
	_max_size_overrides[type_id] = max_size

## Gibt das effektive Limit für einen Typ zurück (Override oder Default).
func get_max_size_for(type_id: String) -> int:
	return _max_size_overrides.get(type_id, default_max_size)

## Versucht eine Instanz aus dem Pool zu holen.
## Gibt null zurück wenn kein valider Eintrag vorhanden.
func acquire(type_id: String) -> Node3D:
	if not _pool.has(type_id) or _pool[type_id].is_empty():
		pool_misses += 1
		return null

	var pooled := _pool[type_id].pop_back() as Node3D
	if is_instance_valid(pooled):
		pool_hits += 1
		# BUGFIX 2026-09-26: siehe _park_container-Feldkommentar — hängt die Node dort
		# (Container gesetzt UND tatsächlich noch dort geparkt), muss sie vor der Rückgabe
		# entfernt werden. Ohne diesen Schritt schlägt das spätere add_child() im
		# World-Root fehl ("Can't add child, already has a parent").
		if is_instance_valid(_park_container) and pooled.get_parent() == _park_container:
			_park_container.remove_child(pooled)
		AppLogger.log_debug(
			"Pool-Hit: '%s' (Pool noch: %d)" % [type_id, _pool[type_id].size()], LOG_CAT
		)
		return pooled

	AppLogger.log_debug("Pool-Eintrag für '%s' war invalid — übersprungen." % type_id, LOG_CAT)
	pool_misses += 1
	return null

## Legt eine Instanz in den Pool zurück.
## Gibt false zurück wenn Pool voll oder type_id unbekannt.
func release(type_id: String, entity: Node3D) -> bool:
	if type_id.is_empty():
		return false

	if not _pool.has(type_id):
		_pool[type_id] = []

	var max_size := get_max_size_for(type_id)
	if _pool[type_id].size() >= max_size:
		AppLogger.log_debug(
			"Pool voll für '%s' (max: %d) → queue_free." % [type_id, max_size], LOG_CAT
		)
		return false

	# Aus dem alten Tree-Platz entfernen bevor im Pool lagern (Baum/Erz war z.B. Kind eines
	# Chunk-Root-Nodes — das darf nicht bestehen bleiben, sonst hängt die Node am falschen Ort).
	if entity.is_inside_tree() and is_instance_valid(entity.get_parent()):
		entity.get_parent().remove_child(entity)

	# BUGFIX 2026-09-26: siehe _park_container-Feldkommentar oben — ohne Container bleibt die
	# Node ab hier absichtlich ohne Parent (altes Verhalten, für Rückwärtskompatibilität).
	if is_instance_valid(_park_container):
		_park_container.add_child(entity)

	_pool[type_id].append(entity)
	return true

## Gibt alle Pool-Nodes frei (bei World-Unload).
## Gibt die Anzahl der freigegebenen Nodes zurück.
func flush() -> int:
	var freed := 0
	for type_id in _pool.keys():
		for pooled in _pool[type_id]:
			if not is_instance_valid(pooled):
				continue
			# BUGFIX 2026-09-26: pooled Entities hängen bei gesetztem _park_container jetzt
			# regulär im Baum (siehe release()) — die alte Bedingung "not is_inside_tree()"
			# hätte sie hier fälschlich übersprungen (Leak: Pool wird geleert, ohne die
			# eigentlichen Nodes freizugeben). Weiterhin übersprungen wird nur der
			# Sonderfall, dass eine Node entgegen der Pool-Invariante anderswo (nicht im
			# eigenen Park-Container) wieder in den Baum gehängt wurde — das deutet auf
			# einen Bug an ANDERER Stelle hin, den flush() nicht durch Doppel-Free verschlimmern soll.
			var unexpectedly_reparented: bool = (
				pooled.is_inside_tree()
				and not (is_instance_valid(_park_container) and pooled.get_parent() == _park_container)
			)
			if unexpectedly_reparented:
				continue
			if is_instance_valid(_park_container) and pooled.get_parent() == _park_container:
				_park_container.remove_child(pooled)
			pooled.queue_free()
			freed += 1
	_pool.clear()
	return freed

## Gibt Debug-Infos zurück: { type_id: pool_size }
func get_sizes() -> Dictionary:
	var out: Dictionary = {}
	for type_id in _pool:
		out[type_id] = _pool[type_id].size()
	return out

## Gibt Debug-Infos inkl. Limits zurück: { type_id: {"size": n, "max": m} }
func get_sizes_with_limits() -> Dictionary:
	var out: Dictionary = {}
	for type_id in _pool:
		out[type_id] = {"size": _pool[type_id].size(), "max": get_max_size_for(type_id)}
	return out
