## tests/unit/test_desert_pvp_zone_placer.gd
## Unit-Tests für DesertPvpZonePlacer._find_desert_position() — reine
## GDScript-Arithmetik, kein Godot-Node nötig (siehe Klassenkommentar). Der
## Godot-spezifische Teil (place(): Area3D/CollisionShape3D/add_child()) ist
## NICHT abgedeckt — dafür bräuchte es eine echte Szene-Runtime (siehe
## TODO-offene-probleme.md "Tests gegen die echte Godot/GUT-Runtime").

extends GutTest

func test_finds_desert_at_origin_immediately() -> void:
	var lookup := func(_x: float, _z: float) -> String: return "desert"
	var pos: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	assert_eq(pos, Vector2.ZERO, "Wenn (0,0) bereits Wüste ist, muss sofort (0,0) zurückkommen, kein Suchlauf nötig")

func test_finds_desert_further_out() -> void:
	# Simuliert eine Wüste, die erst ab x >= 100 beginnt — (0,0) ist NICHT Wüste.
	var lookup := func(x: float, _z: float) -> String:
		return "desert" if x >= 100.0 else "meadow"
	var pos: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	assert_true(pos is Vector2, "Muss eine Position finden, nicht null")
	assert_gte((pos as Vector2).x, 100.0, "Gefundene Position muss tatsächlich in der simulierten Wüste liegen")

func test_returns_null_when_desert_never_found() -> void:
	var lookup := func(_x: float, _z: float) -> String: return "meadow"
	var pos: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	assert_null(pos, "Wenn nirgends Wüste ist (im Suchradius), muss null zurückkommen statt eine falsche Position zu erfinden")

func test_returned_position_is_actually_desert() -> void:
	# Realistischeres Fake: nur ein einzelner "Wüsten-Fleck" bei (48, -24).
	var target := Vector2(48.0, -24.0)
	var lookup := func(x: float, z: float) -> String:
		return "desert" if Vector2(x, z).distance_to(target) < 12.0 else "forest"
	var pos: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	assert_true(pos is Vector2, "Muss den isolierten Wüsten-Fleck finden")
	if pos is Vector2:
		assert_eq(lookup.call((pos as Vector2).x, (pos as Vector2).y), "desert",
			"Die zurückgegebene Position muss beim erneuten Nachfragen wirklich 'desert' sein")

func test_search_is_deterministic() -> void:
	# Gleicher Lookup, zweimal aufgerufen → muss dieselbe Position liefern
	# (wichtig für Round 74s Kernanforderung: jeder Peer findet unabhängig
	# denselben Ort, siehe DesertPvpZonePlacer-Klassenkommentar).
	var lookup := func(x: float, _z: float) -> String:
		return "desert" if x >= 200.0 else "swamp"
	var pos1: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	var pos2: Variant = DesertPvpZonePlacer._find_desert_position(lookup)
	assert_eq(pos1, pos2)
