class_name BuildingRecipes
extends RefCounted

## BuildingRecipes — Katalog + Bauanleitungen der Siedlungsgebäude des BODENDORFS, zugleich die
## Anlaufstelle (Fassade) für ALLE Gebäudetypen: Typen anderer Dorf-Arten (VillageKind.catalog())
## werden über VillageKinds aufgelöst, das Aufrufmuster bleibt für alle gleich.
##
## Jedes Gebäude ist ein Rezept aus StructureParts-Teilen in LOKALEN Koordinaten:
##   +Z = Vorderseite/Tür/Straße, y = 0 = Oberkante der Bodenplatte, Ursprung = Grundstücksmitte.
## `half` ist das ganze Grundstück (Haus + Vorgarten/Hof) als halbe Kantenlängen; die
## Dorfplanung benutzt es für Abstände/Kollision, der Builder dreht das Ergebnis dann auf
## die Straße (yaw).
##
## `npcs`: wo (lokal) welche Bewohner stehen. Es werden bewusst nur Typen genutzt, die als
## Mehrfach-Spawns erlaubt sind (settler/farmer/water_carrier und die Berufs-NPCs aus
## ProfessionCatalog) — keine Quest-NPCs.

const T_HOUSE_SMALL := "house_small"
const T_HOUSE_LONG := "house_long"
const T_HOUSE_LARGE := "house_large"
const T_FARMSTEAD := "farmstead"
const T_BARN := "barn"
const T_FIELD := "field"
const T_STABLE := "stable"
const T_GRANARY := "granary"
const T_SMITHY := "smithy"
const T_BAKERY := "bakery"
const T_WORKSHOP := "workshop"
const T_TAVERN := "tavern"
const T_CHAPEL := "chapel"
const T_CEMETERY := "cemetery"
const T_MILL := "mill"
const T_WELL := "well"
const T_MARKET := "market_square"
const T_WATCHPOST := "watchpost"
const T_WAYHOUSE := "wayhouse"
const T_WAYCROSS := "wayside_cross"
# Berufe (ProfessionCatalog, docs/professions.md)
const T_POTTERY := "pottery"
const T_WEAVERY := "weavery"
const T_DYEHOUSE := "dyehouse"
const T_BREWERY := "brewery"
const T_TANNERY := "tannery"
const T_DAIRY := "dairy"
const T_SALTWORKS := "saltworks"
const T_GLASSWORKS := "glassworks"
const T_WHEELWRIGHT := "wheelwright"
const T_SCRIPTORIUM := "scriptorium"
const T_FISHERY := "fishery"

const WALL_COLORS: Array[Color] = [
	Color(0.82, 0.76, 0.62), Color(0.55, 0.40, 0.24), Color(0.72, 0.65, 0.52), Color(0.58, 0.57, 0.53),
]
const ROOF_COLORS: Array[Color] = [
	Color(0.55, 0.25, 0.18), Color(0.30, 0.30, 0.34), Color(0.60, 0.52, 0.26), Color(0.42, 0.22, 0.16),
]

const _NPC_SETTLER := "settler_npc"
const _NPC_FARMER := "farmer_npc"
const _NPC_WATER := "water_carrier_npc"
const _NPC_SMITH := "smith_npc"
const _NPC_BAKER := "baker_npc"
const _NPC_MILLER := "miller_npc"

## type → {half, slab, npcs}. `slab` = Farbe der Bodenplatte.
const CATALOG: Dictionary = {
	T_HOUSE_SMALL: {"half": Vector2(4.0, 4.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_SETTLER, Vector2(0.0, 2.6)]]},
	T_HOUSE_LONG: {"half": Vector2(5.5, 4.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_SETTLER, Vector2(-1.0, 2.6)]]},
	T_HOUSE_LARGE: {"half": Vector2(5.0, 5.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_SETTLER, Vector2(0.0, 3.4)]]},
	T_FARMSTEAD: {"half": Vector2(8.0, 8.0), "slab": Color(0.42, 0.36, 0.26), "npcs": [[_NPC_FARMER, Vector2(-4.5, 3.5)]]},
	T_BARN: {"half": Vector2(6.0, 6.0), "slab": Color(0.42, 0.36, 0.26), "npcs": []},
	T_FIELD: {"half": Vector2(5.0, 4.0), "slab": Color(0.30, 0.21, 0.12), "npcs": [[_NPC_FARMER, Vector2(0.0, 0.2)]]},
	T_STABLE: {"half": Vector2(6.0, 6.0), "slab": Color(0.42, 0.36, 0.26), "npcs": [[_NPC_FARMER, Vector2(3.0, 2.5)]]},
	T_GRANARY: {"half": Vector2(3.0, 3.5), "slab": Color(0.42, 0.40, 0.36), "npcs": []},
	T_SMITHY: {"half": Vector2(5.5, 5.5), "slab": Color(0.38, 0.38, 0.38), "npcs": [[_NPC_SMITH, Vector2(2.6, -0.6)]]},
	T_BAKERY: {"half": Vector2(4.5, 5.0), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_BAKER, Vector2(2.0, 3.4)]]},
	T_WORKSHOP: {"half": Vector2(5.0, 5.5), "slab": Color(0.42, 0.40, 0.36), "npcs": [[_NPC_SETTLER, Vector2(2.5, -0.5)]]},
	T_TAVERN: {"half": Vector2(6.0, 6.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_SETTLER, Vector2(-1.5, 3.4)], [_NPC_SETTLER, Vector2(1.5, 3.8)]]},
	T_CHAPEL: {"half": Vector2(5.0, 7.0), "slab": Color(0.50, 0.50, 0.48), "npcs": [[_NPC_SETTLER, Vector2(0.0, 5.5)]]},
	T_CEMETERY: {"half": Vector2(5.0, 5.0), "slab": Color(0.28, 0.38, 0.22), "npcs": []},
	T_MILL: {"half": Vector2(4.5, 5.5), "slab": Color(0.50, 0.50, 0.48), "npcs": [[_NPC_MILLER, Vector2(2.2, 3.0)]]},
	T_WELL: {"half": Vector2(2.0, 2.0), "slab": Color(0.50, 0.50, 0.48), "npcs": [[_NPC_WATER, Vector2(1.6, 1.6)]]},
	T_MARKET: {"half": Vector2(9.0, 9.0), "slab": Color(0.50, 0.48, 0.44), "npcs": [[_NPC_WATER, Vector2(2.5, 2.5)], [_NPC_SETTLER, Vector2(-4.0, 3.5)], [_NPC_SETTLER, Vector2(4.5, -3.0)]]},
	T_WATCHPOST: {"half": Vector2(3.0, 3.5), "slab": Color(0.45, 0.45, 0.43), "npcs": [[_NPC_SETTLER, Vector2(1.8, 2.4)]]},
	T_WAYHOUSE: {"half": Vector2(5.0, 5.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [[_NPC_SETTLER, Vector2(1.5, 3.4)]]},
	T_WAYCROSS: {"half": Vector2(1.6, 1.6), "slab": Color(0.50, 0.50, 0.48), "npcs": []},
	T_POTTERY: {"half": Vector2(5.0, 5.5), "slab": Color(0.42, 0.36, 0.30), "npcs": [["potter_npc", Vector2(2.2, 2.4)]]},
	T_WEAVERY: {"half": Vector2(5.0, 5.0), "slab": Color(0.45, 0.43, 0.40), "npcs": [["weaver_npc", Vector2(0.5, 2.4)]]},
	T_DYEHOUSE: {"half": Vector2(5.5, 5.5), "slab": Color(0.42, 0.38, 0.36), "npcs": [["dyer_npc", Vector2(3.2, 2.2)]]},
	T_BREWERY: {"half": Vector2(6.0, 6.0), "slab": Color(0.45, 0.43, 0.40), "npcs": [["brewer_npc", Vector2(3.0, 3.2)]]},
	T_TANNERY: {"half": Vector2(5.5, 5.5), "slab": Color(0.36, 0.30, 0.22), "npcs": [["tanner_npc", Vector2(0.5, 2.6)]]},
	T_DAIRY: {"half": Vector2(5.0, 5.5), "slab": Color(0.45, 0.43, 0.40), "npcs": [["cheesemaker_npc", Vector2(1.5, 2.6)]]},
	T_SALTWORKS: {"half": Vector2(6.0, 6.0), "slab": Color(0.60, 0.60, 0.58), "npcs": [["salter_npc", Vector2(-1.0, 3.4)]]},
	T_GLASSWORKS: {"half": Vector2(5.5, 5.5), "slab": Color(0.38, 0.38, 0.38), "npcs": [["glassmaker_npc", Vector2(1.8, 2.4)]]},
	T_WHEELWRIGHT: {"half": Vector2(5.5, 5.5), "slab": Color(0.42, 0.40, 0.36), "npcs": [["wheelwright_npc", Vector2(-0.5, 2.8)]]},
	T_SCRIPTORIUM: {"half": Vector2(4.5, 5.0), "slab": Color(0.50, 0.50, 0.48), "npcs": [["scribe_npc", Vector2(0.0, 2.9)]]},
	T_FISHERY: {"half": Vector2(6.0, 6.0), "slab": Color(0.40, 0.36, 0.30), "npcs": [["fisher_npc", Vector2(-0.5, 3.4)]]},
}

## Katalog-Eintrag eines Gebäudetyps: erst die Bodentypen (CATALOG), dann die der Sonderarten
## (VillageKinds). {} = unbekannter Typ.
static func entry(type_id: String) -> Dictionary:
	if CATALOG.has(type_id):
		return CATALOG[type_id] as Dictionary
	return VillageKinds.entry_for(type_id)

static func has_type(type_id: String) -> bool:
	return CATALOG.has(type_id) or not VillageKinds.entry_for(type_id).is_empty()

static func half_extents(type_id: String) -> Vector2:
	return entry(type_id)["half"] as Vector2

## Umkreisradius des Grundstücks (für grobe Abstandsprüfungen und Vegetations-Freiraum).
static func radius(type_id: String) -> float:
	return half_extents(type_id).length()

static func npc_slots(type_id: String) -> Array:
	return entry(type_id)["npcs"] as Array

## Baut das Gebäude `type_id` in `b`. variant (0..) steuert Farben/Kleinvarianten.
## slab_depth: Fundamenttiefe (Geländespreizung + Reserve), vom Aufrufer berechnet.
## info: der Gebäude-Datensatz aus der Dorfplanung (spread, params …) — Bodentypen brauchen ihn nicht,
## Sonderarten (z. B. Riesenbaum mit Rampe/Brücken) schon. Leer erlaubt (Katalog-Tests).
## Bodenplatte nur, wenn der Katalog eine `slab`-Farbe hat (Baumhäuser stehen auf Stämmen, nicht auf Platten).
static func build(type_id: String, b: PartBatch, variant: int, slab_depth: float, info: Dictionary = {}) -> void:
	var e: Dictionary = entry(type_id)
	if e.is_empty():
		return
	if not CATALOG.has(type_id):
		VillageKinds.kind_of_type(type_id).build_type(type_id, b, variant, slab_depth, info)
		return
	var half: Vector2 = half_extents(type_id)
	StructureParts.slab(b, half.x, half.y, slab_depth, e["slab"] as Color)
	var wall: Color = WALL_COLORS[absi(variant) % WALL_COLORS.size()]
	var roof: Color = ROOF_COLORS[absi(floori(variant / 3.0)) % ROOF_COLORS.size()]
	match type_id:
		T_HOUSE_SMALL: _house_small(b, wall, roof, variant)
		T_HOUSE_LONG: _house_long(b, wall, roof, variant)
		T_HOUSE_LARGE: _house_large(b, wall, roof)
		T_FARMSTEAD: _farmstead(b, wall, roof, variant)
		T_BARN: _barn(b, roof)
		T_FIELD: _field(b, variant)
		T_STABLE: _stable(b, roof)
		T_GRANARY: _granary(b, roof)
		T_SMITHY: _smithy(b, roof)
		T_BAKERY: _bakery(b, wall, roof)
		T_WORKSHOP: _workshop(b, wall, roof)
		T_TAVERN: _tavern(b, wall, roof)
		T_CHAPEL: _chapel(b)
		T_CEMETERY: _cemetery(b, variant)
		T_MILL: _mill(b, roof)
		T_WELL: StructureParts.well(b, Vector2.ZERO)
		T_MARKET: _market(b, variant)
		T_WATCHPOST: _watchpost(b)
		T_WAYHOUSE: _wayhouse(b, wall, roof)
		T_WAYCROSS: StructureParts.stone_cross(b, Vector2.ZERO)
		T_POTTERY: _pottery(b, wall, roof)
		T_WEAVERY: _weavery(b, wall, roof)
		T_DYEHOUSE: _dyehouse(b, wall, roof)
		T_BREWERY: _brewery(b, wall, roof)
		T_TANNERY: _tannery(b, roof)
		T_DAIRY: _dairy(b, roof)
		T_SALTWORKS: _saltworks(b, roof)
		T_GLASSWORKS: _glassworks(b, roof)
		T_WHEELWRIGHT: _wheelwright(b, wall, roof)
		T_SCRIPTORIUM: _scriptorium(b, roof)
		T_FISHERY: _fishery(b, wall, roof)

## Drehwinkel (um Y), sodass lokal +Z von `from` nach `to` zeigt.
static func facing_yaw(from: Vector2, to: Vector2) -> float:
	var d: Vector2 = to - from
	return atan2(d.x, d.y)

# ─────────────────────────────────────────────
# Wohnhäuser
# ─────────────────────────────────────────────

static func _house_small(b: PartBatch, wall: Color, roof: Color, v: int) -> void:
	var r := Rect2(-2.6, -3.7, 5.2, 4.4)
	StructureParts.box_house(b, r, 2.7, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.7, 1.8, roof)
	StructureParts.chimney(b, Vector3(1.4, 2.7, -2.2), 1.6)
	StructureParts.bed(b, Vector2(-1.6, -2.6))
	StructureParts.table(b, Vector2(1.0, -1.0))
	if v % 2 == 0:
		StructureParts.crop_plot(b, Vector2(-1.8, 3.1), Vector2(1.6, 0.8), 3)
	else:
		StructureParts.barrel(b, Vector2(2.9, 1.4))
		StructureParts.log_stack(b, Vector2(-2.9, -0.3), PI * 0.5)

static func _house_long(b: PartBatch, wall: Color, roof: Color, v: int) -> void:
	var r := Rect2(-4.5, -3.8, 9.0, 4.4)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, -1.2, 2)
	StructureParts.gable_over(b, r, 2.8, 1.9, roof)
	StructureParts.chimney(b, Vector3(-3.0, 2.8, -2.0), 1.7)
	StructureParts.bed(b, Vector2(-3.4, -2.8))
	StructureParts.bed(b, Vector2(3.4, -2.8))
	StructureParts.table(b, Vector2(0.0, -1.5))
	StructureParts.bench(b, Vector2(2.6, 1.5))
	if v % 2 == 1:
		StructureParts.fence_run(b, Vector2(-4.0, 3.6), Vector2(4.0, 3.6), 0.9, StructureParts.COL_WOOD, [Vector2(3.0, 5.0)])

static func _house_large(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.5, -4.8, 7.0, 5.3)
	StructureParts.box_house(b, r, 4.6, wall, 1.3, 2.2, 0, 0.0, 2)
	for k in range(2):
		b.add_box(Vector3(0.9, 0.9, StructureParts.WALL_T + 0.04), Vector3(-1.6 + 3.2 * float(k), 3.4, 0.5), StructureParts.COL_GLASS, 0.0, false)
	StructureParts.gable_over(b, r, 4.6, 2.4, roof)
	StructureParts.chimney(b, Vector3(2.2, 4.6, -3.0), 2.0)
	StructureParts.crate(b, Vector2(-3.3, 1.8))
	StructureParts.barrel(b, Vector2(3.4, 1.8))

# ─────────────────────────────────────────────
# Landwirtschaft
# ─────────────────────────────────────────────

static func _farmstead(b: PartBatch, wall: Color, roof: Color, v: int) -> void:
	var house := Rect2(-7.0, -7.5, 5.0, 4.5)
	StructureParts.box_house(b, house, 2.7, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, house, 2.7, 1.8, roof)
	StructureParts.chimney(b, Vector3(-3.0, 2.7, -6.2), 1.6)
	var barn := Rect2(-0.8, -7.5, 6.5, 6.0)
	StructureParts.box_house(b, barn, 3.4, StructureParts.COL_WOOD, 2.6, 2.8, 0, 0.0, 0)
	StructureParts.gable_over(b, barn, 3.4, 2.3, ROOF_COLORS[2])
	StructureParts.fence_rect(b, Rect2(-7.5, -1.0, 13.0, 7.6), 0, 3.0)
	StructureParts.hay_bale(b, Vector2(2.4, -0.2), 0.2)
	StructureParts.hay_bale(b, Vector2(3.5, -0.4), -0.1)
	StructureParts.barrel(b, Vector2(-5.5, -2.2))
	if v % 2 == 0:
		StructureParts.well(b, Vector2(-2.0, 3.0))

static func _barn(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-4.5, -5.5, 9.0, 7.0)
	StructureParts.box_house(b, r, 3.5, StructureParts.COL_WOOD, 2.8, 2.9, 0, 0.0, 0)
	StructureParts.gable_over(b, r, 3.5, 2.5, roof)
	StructureParts.hay_bale(b, Vector2(-3.5, 2.6))
	StructureParts.hay_bale(b, Vector2(-2.4, 2.8), 0.4)
	StructureParts.crate(b, Vector2(3.6, 2.4))

static func _field(b: PartBatch, v: int) -> void:
	StructureParts.crop_plot(b, Vector2.ZERO, Vector2(4.3, 3.3), 6 + (v % 2), StructureParts.COL_CROP if v % 3 != 0 else Color(0.70, 0.60, 0.22))
	StructureParts.fence_rect(b, Rect2(-4.8, -3.8, 9.6, 7.6), 0, 1.6, 0.9)

static func _stable(b: PartBatch, roof: Color) -> void:
	StructureParts.lean_to(b, Rect2(-4.5, -5.0, 9.0, 3.4), 2.6, roof, true)
	StructureParts.fence_rect(b, Rect2(-5.5, -1.2, 11.0, 6.4), 0, 2.6, 1.1)
	StructureParts.hay_bale(b, Vector2(-3.0, -3.6))
	StructureParts.hay_bale(b, Vector2(3.4, -3.8), 0.3)
	StructureParts.barrel(b, Vector2(0.0, -4.2))

static func _granary(b: PartBatch, roof: Color) -> void:
	for sx: float in [-1.3, 1.3]:
		for sz: float in [-1.3, 1.3]:
			b.add_box(Vector3(0.25, 0.9, 0.25), Vector3(sx, 0.45, sz - 0.5), StructureParts.COL_WOOD_DARK)
	b.add_box(Vector3(3.2, 2.2, 3.0), Vector3(0.0, 2.0, -0.5), StructureParts.COL_WOOD)
	b.add_gable_roof(1.9, 1.8, 1.2, Vector3(0.0, 3.1, -0.5), roof)
	b.add_box(Vector3(1.2, 0.3, 0.9), Vector3(0.0, 0.15, 1.5), StructureParts.COL_WOOD_LIGHT)

# ─────────────────────────────────────────────
# Handwerk, Dorfleben
# ─────────────────────────────────────────────

static func _smithy(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-3.5, -4.5, 5.0, 4.2)
	StructureParts.box_house(b, r, 2.9, StructureParts.COL_STONE, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.9, 1.7, roof)
	StructureParts.lean_to(b, Rect2(1.8, -4.5, 3.0, 3.6), 2.4, roof, true)
	b.add_box(Vector3(1.3, 1.0, 1.1), Vector3(3.3, 0.5, -3.8), StructureParts.COL_STONE_DARK)
	StructureParts.chimney(b, Vector3(3.3, 1.0, -4.2), 3.2, StructureParts.COL_STONE_DARK)
	b.add_box(Vector3(0.7, 0.6, 0.4), Vector3(3.4, 0.3, -1.9), StructureParts.COL_IRON)
	StructureParts.barrel(b, Vector2(-3.8, 0.8))
	StructureParts.crate(b, Vector2(4.2, 0.2))
	StructureParts.signpost(b, Vector2(-4.4, 3.2), 0.0, Color(0.30, 0.30, 0.34))

static func _bakery(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.0, -4.4, 6.0, 4.0)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, -1.5, 1)
	StructureParts.gable_over(b, r, 2.8, 1.8, roof)
	b.add_cylinder(0.95, 1.7, Vector3(-3.9, 0.85, -2.4), StructureParts.COL_STONE)
	StructureParts.chimney(b, Vector3(-3.9, 1.7, -2.4), 2.4)
	StructureParts.market_stall(b, Vector2(2.0, 2.6), 0.0, Color(0.75, 0.30, 0.22))
	StructureParts.crate(b, Vector2(3.6, 1.1))

static func _workshop(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.5, -5.0, 5.0, 4.4)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.8, 1.8, roof)
	StructureParts.lean_to(b, Rect2(2.0, -4.8, 2.8, 3.6), 2.3, roof, true)
	StructureParts.table(b, Vector2(3.4, -3.0), 0.0, Vector2(1.8, 0.8))
	StructureParts.log_stack(b, Vector2(3.8, 0.8), 0.0)
	StructureParts.log_stack(b, Vector2(-4.2, 0.4), PI * 0.5)
	StructureParts.signpost(b, Vector2(-1.5, 2.4), 0.0, Color(0.50, 0.37, 0.20))

static func _tavern(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-4.5, -5.0, 9.0, 6.0)
	StructureParts.box_house(b, r, 3.4, wall, 1.5, 2.3, 0, 0.0, 3)
	StructureParts.gable_over(b, r, 3.4, 2.2, roof)
	StructureParts.chimney(b, Vector3(-3.2, 3.4, -3.2), 2.0)
	StructureParts.chimney(b, Vector3(3.0, 3.4, -3.2), 2.0)
	StructureParts.table(b, Vector2(-1.0, -2.0), 0.0, Vector2(2.2, 0.9))
	StructureParts.table(b, Vector2(2.4, -2.5), 0.0, Vector2(1.6, 0.9))
	StructureParts.signpost(b, Vector2(4.4, 3.2), 0.4, Color(0.62, 0.40, 0.14))
	for k in range(2):
		var x: float = -3.0 + 3.6 * float(k)
		StructureParts.table(b, Vector2(x, 3.4))
		StructureParts.bench(b, Vector2(x, 2.6))
		StructureParts.bench(b, Vector2(x, 4.2))
	StructureParts.barrel(b, Vector2(-5.2, 1.8))
	StructureParts.barrel(b, Vector2(-5.2, 2.7))

static func _chapel(b: PartBatch) -> void:
	var stone: Color = Color(0.64, 0.62, 0.58)
	var nave := Rect2(-2.5, -6.0, 5.0, 6.4)
	# Schiff: Front bleibt offen zum Turm (Vorraum), die drei anderen Seiten zu.
	StructureParts.wall_run(b, Vector2(-2.5, -6.0), Vector2(2.5, -6.0), 4.0, stone)
	StructureParts.wall_run(b, Vector2(-2.5, -6.0), Vector2(-2.5, 0.4), 4.0, stone, [
		{"t0": 2.2, "t1": 3.2, "kind": "window", "sill": 1.2, "top": 3.2}, {"t0": 4.4, "t1": 5.4, "kind": "window", "sill": 1.2, "top": 3.2}])
	StructureParts.wall_run(b, Vector2(2.5, -6.0), Vector2(2.5, 0.4), 4.0, stone, [
		{"t0": 2.2, "t1": 3.2, "kind": "window", "sill": 1.2, "top": 3.2}, {"t0": 4.4, "t1": 5.4, "kind": "window", "sill": 1.2, "top": 3.2}])
	StructureParts.gable_over(b, nave, 4.0, 2.4, Color(0.34, 0.30, 0.30))
	# Turm vor dem Schiff: Seiten + Tür vorn, hinten offen zum Schiff.
	StructureParts.wall_run(b, Vector2(-1.6, 0.4), Vector2(-1.6, 3.4), 7.0, stone)
	StructureParts.wall_run(b, Vector2(1.6, 0.4), Vector2(1.6, 3.4), 7.0, stone)
	StructureParts.wall_run(b, Vector2(-1.6, 3.4), Vector2(1.6, 3.4), 7.0, stone, [{"t0": 1.0, "t1": 2.2, "kind": "door", "top": 2.5}])
	StructureParts.wall_run(b, Vector2(-1.6, 0.4), Vector2(1.6, 0.4), 7.0, stone, [{"t0": 0.9, "t1": 2.3, "kind": "door", "top": 2.6}])
	b.add_pyramid(2.0, 2.2, 3.2, Vector3(0.0, 7.0, 1.9), Color(0.34, 0.30, 0.30))
	StructureParts.bench(b, Vector2(-1.0, -2.0), PI * 0.5, 2.2)
	StructureParts.bench(b, Vector2(1.0, -2.0), PI * 0.5, 2.2)
	StructureParts.bench(b, Vector2(-1.0, -4.0), PI * 0.5, 2.2)
	StructureParts.bench(b, Vector2(1.0, -4.0), PI * 0.5, 2.2)
	b.add_box(Vector3(1.6, 0.9, 0.7), Vector3(0.0, 0.45, -5.4), StructureParts.COL_STONE)
	StructureParts.lamp_post(b, Vector2(-2.2, 5.2), 2.4, true)
	StructureParts.lamp_post(b, Vector2(2.2, 5.2), 2.4, true)

static func _cemetery(b: PartBatch, v: int) -> void:
	StructureParts.fence_rect(b, Rect2(-4.5, -4.5, 9.0, 9.0), 0, 2.0, 1.0)
	for row in range(3):
		for col in range(3):
			var jitter: float = float(((row * 7 + col * 3 + v) % 5) - 2) * 0.05
			StructureParts.gravestone(b, Vector2(-2.6 + 2.6 * float(col), -2.8 + 2.4 * float(row)), jitter, 0.7 + 0.15 * float((row + col) % 3))
	StructureParts.stone_cross(b, Vector2(0.0, -3.9))

static func _mill(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-2.0, -3.8, 4.0, 4.2)
	StructureParts.box_house(b, r, 5.6, Color(0.72, 0.68, 0.60), 1.2, 2.1, 0, 0.0, 1)
	StructureParts.pyramid_over(b, r, 5.6, 2.4, roof)
	StructureParts.mill_sails(b, Vector3(0.0, 5.0, 0.7), 3.4)
	StructureParts.crate(b, Vector2(2.6, 1.4))
	StructureParts.crate(b, Vector2(-2.7, 1.2), 0.6)
	StructureParts.hay_bale(b, Vector2(3.0, 2.8), 0.4)

static func _market(b: PartBatch, v: int) -> void:
	StructureParts.paving(b, Vector2.ZERO, Vector2(8.6, 8.6))
	StructureParts.well(b, Vector2.ZERO)
	var canopy: Array[Color] = [Color(0.75, 0.30, 0.22), Color(0.28, 0.45, 0.62), Color(0.80, 0.68, 0.28), Color(0.40, 0.58, 0.32)]
	var spots: Array[Vector2] = [Vector2(5.5, 5.5), Vector2(-5.5, 5.5), Vector2(5.5, -5.5), Vector2(-5.5, -5.5)]
	for i in range(spots.size()):
		StructureParts.market_stall(b, spots[i], BuildingRecipes.facing_yaw(spots[i], Vector2.ZERO), canopy[(i + v) % canopy.size()])
	for corner: Vector2 in [Vector2(8.0, 8.0), Vector2(-8.0, 8.0), Vector2(8.0, -8.0), Vector2(-8.0, -8.0)]:
		StructureParts.lamp_post(b, corner, 3.2)
	StructureParts.bench(b, Vector2(3.4, 0.0), PI * 0.5)
	StructureParts.bench(b, Vector2(-3.4, 0.0), PI * 0.5)
	StructureParts.barrel(b, Vector2(7.2, 0.0))
	StructureParts.crate(b, Vector2(-7.2, 0.6))

static func _watchpost(b: PartBatch) -> void:
	var r := Rect2(-1.5, -2.0, 3.0, 3.0)
	StructureParts.box_house(b, r, 6.0, Color(0.52, 0.50, 0.46), 1.1, 2.1, 0, 0.0, 0)
	b.add_box(Vector3(4.0, 0.2, 4.0), Vector3(0.0, 6.1, -0.5), StructureParts.COL_WOOD_DARK)
	for sx: float in [-1.8, 1.8]:
		for sz: float in [-2.3, 1.3]:
			b.add_box(Vector3(0.14, 1.6, 0.14), Vector3(sx, 7.0, sz), StructureParts.COL_WOOD_DARK, 0.0, false)
	b.add_pyramid(2.4, 2.4, 1.4, Vector3(0.0, 7.8, -0.5), Color(0.30, 0.30, 0.34), 0.0, false)
	StructureParts.lamp_post(b, Vector2(1.9, 2.4), 2.6, true)

static func _wayhouse(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.5, -4.8, 7.0, 4.6)
	StructureParts.box_house(b, r, 3.0, wall, 1.3, 2.2, 0, 0.0, 2)
	StructureParts.gable_over(b, r, 3.0, 2.0, roof)
	StructureParts.chimney(b, Vector3(2.4, 3.0, -3.4), 1.8)
	StructureParts.signpost(b, Vector2(3.9, 2.4), 0.3, Color(0.62, 0.40, 0.14))
	StructureParts.bench(b, Vector2(-2.0, 1.2))
	StructureParts.fence_run(b, Vector2(-4.2, 4.6), Vector2(1.0, 4.6), 1.0)
	StructureParts.barrel(b, Vector2(-4.2, 1.0))

# ─────────────────────────────────────────────
# Berufe (ProfessionCatalog) — jedes Gebäude zeigt sein Handwerk schon von außen
# ─────────────────────────────────────────────

static func _pottery(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.5, -5.0, 5.0, 4.4)
	StructureParts.box_house(b, r, 2.7, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.7, 1.8, roof)
	StructureParts.kiln(b, Vector2(3.3, -3.4), 1.0, 1.8)
	StructureParts.table(b, Vector2(3.4, 0.4), 0.0, Vector2(1.8, 0.8))
	StructureParts.pots(b, Vector2(2.7, 0.4), 4, 0.45)
	StructureParts.pots(b, Vector2(-3.8, 0.8), 3, 0.5)
	StructureParts.heap(b, Vector2(-3.2, 2.6), 0.9, 0.6, Color(0.50, 0.38, 0.26))
	StructureParts.log_stack(b, Vector2(0.8, -5.0), 0.0)
	StructureParts.signpost(b, Vector2(-1.8, 2.8), 0.0, Color(0.70, 0.38, 0.22))

static func _weavery(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-3.5, -4.5, 7.0, 4.0)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, 0.0, 2)
	StructureParts.gable_over(b, r, 2.8, 1.8, roof)
	StructureParts.chimney(b, Vector3(2.6, 2.8, -3.2), 1.6)
	StructureParts.loom(b, Vector2(-3.0, 1.8))
	StructureParts.drying_rack(b, Vector2(2.0, 2.0), Vector2(4.2, 2.0), [Color(0.88, 0.84, 0.70), Color(0.80, 0.86, 0.72), Color(0.90, 0.88, 0.80)], 1.8)
	StructureParts.crate(b, Vector2(-4.2, -0.2))
	StructureParts.bench(b, Vector2(0.0, 1.0), 0.0, 1.4)

static func _dyehouse(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-4.5, -5.0, 6.0, 4.0)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.8, 1.8, roof)
	StructureParts.vat(b, Vector2(3.4, -3.8), 0.8, Color(0.52, 0.20, 0.55))
	StructureParts.vat(b, Vector2(3.4, -1.9), 0.8, Color(0.92, 0.76, 0.18))
	StructureParts.vat(b, Vector2(3.4, 0.0), 0.8, Color(0.22, 0.34, 0.74))
	StructureParts.drying_rack(b, Vector2(-3.5, 3.4), Vector2(0.5, 3.4), [
		Color(0.52, 0.20, 0.55), Color(0.92, 0.76, 0.18), Color(0.22, 0.34, 0.74), Color(0.78, 0.30, 0.22)], 2.0)
	StructureParts.barrel(b, Vector2(-4.8, 0.2))
	StructureParts.signpost(b, Vector2(4.6, 3.2), 0.4, Color(0.52, 0.20, 0.55))

static func _brewery(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-5.0, -5.5, 7.0, 5.0)
	StructureParts.box_house(b, r, 3.2, wall, 1.4, 2.2, 0, 0.0, 2)
	StructureParts.gable_over(b, r, 3.2, 2.1, roof)
	StructureParts.chimney(b, Vector3(-3.6, 3.2, -4.0), 3.0)
	StructureParts.vat(b, Vector2(4.0, -3.6), 0.95, Color(0.78, 0.55, 0.20), Color(0.72, 0.45, 0.22), 1.3)
	StructureParts.barrel(b, Vector2(4.8, -0.6))
	StructureParts.barrel(b, Vector2(4.8, 0.3))
	StructureParts.barrel(b, Vector2(4.2, -0.1))
	StructureParts.barrel(b, Vector2(-5.4, 1.0))
	StructureParts.barrel(b, Vector2(-5.4, 2.0))
	StructureParts.crate(b, Vector2(-4.2, 3.0))
	StructureParts.signpost(b, Vector2(-1.5, 3.6), 0.2, Color(0.78, 0.55, 0.20))

static func _tannery(b: PartBatch, roof: Color) -> void:
	StructureParts.lean_to(b, Rect2(-4.5, -5.0, 5.5, 3.6), 2.4, roof, true)
	StructureParts.drying_rack(b, Vector2(2.2, -4.0), Vector2(2.2, -0.6), [Color(0.66, 0.50, 0.32), Color(0.52, 0.38, 0.24), Color(0.72, 0.58, 0.40)], 1.9)
	StructureParts.vat(b, Vector2(-3.8, 0.6), 0.7, Color(0.34, 0.26, 0.14), StructureParts.COL_WOOD_DARK, 0.7)
	StructureParts.vat(b, Vector2(-2.2, 1.2), 0.7, Color(0.38, 0.30, 0.16), StructureParts.COL_WOOD_DARK, 0.7)
	b.add_box(Vector3(1.6, 0.9, 0.5), Vector3(-1.5, 0.45, -2.2), StructureParts.COL_WOOD, 0.3, true)
	StructureParts.barrel(b, Vector2(4.2, 1.0))
	StructureParts.crate(b, Vector2(4.4, 2.2))

static func _dairy(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-4.0, -5.0, 6.5, 4.2)
	StructureParts.box_house(b, r, 2.7, Color(0.90, 0.88, 0.80), 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.7, 1.8, roof)
	StructureParts.cheese_rack(b, Vector2(3.4, -2.6), PI * 0.5)
	for i in range(3):
		b.add_cylinder(0.2, 0.6, Vector3(-4.2 + 0.5 * float(i), 0.3, 1.2), Color(0.70, 0.72, 0.76), false, 8)
	StructureParts.hay_bale(b, Vector2(3.4, 2.4), 0.2)
	StructureParts.fence_run(b, Vector2(-4.5, 4.6), Vector2(0.5, 4.6), 1.0)
	StructureParts.signpost(b, Vector2(4.2, 3.6), 0.3, Color(0.94, 0.82, 0.40))

static func _saltworks(b: PartBatch, roof: Color) -> void:
	StructureParts.lean_to(b, Rect2(-5.0, -5.5, 4.5, 3.4), 2.6, roof, true)
	for i in range(3):
		var z: float = -4.2 + 2.3 * float(i)
		b.add_box(Vector3(2.6, 0.45, 1.8), Vector3(2.0, 0.22, z), StructureParts.COL_STONE_DARK, 0.0, true)
		b.add_box(Vector3(2.3, 0.08, 1.5), Vector3(2.0, 0.5, z), Color(0.88, 0.90, 0.92), 0.0, false)
		b.add_box(Vector3(0.5, 0.25, 0.4), Vector3(0.45, 0.2, z), Color(1.0, 0.55, 0.18), 0.0, false)
	StructureParts.heap(b, Vector2(-3.5, 0.6), 1.0, 0.8, Color(0.94, 0.94, 0.92))
	StructureParts.heap(b, Vector2(-2.0, 1.2), 0.7, 0.55, Color(0.92, 0.92, 0.90))
	StructureParts.log_stack(b, Vector2(-4.4, -0.8), PI * 0.5)
	StructureParts.barrel(b, Vector2(4.8, 3.0))
	StructureParts.barrel(b, Vector2(4.8, 4.0))

static func _glassworks(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-4.5, -5.0, 6.0, 4.6)
	StructureParts.box_house(b, r, 3.0, StructureParts.COL_STONE, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 3.0, 1.8, roof)
	StructureParts.kiln(b, Vector2(3.4, -3.4), 1.2, 2.2)
	StructureParts.heap(b, Vector2(-3.4, 1.6), 1.1, 0.7, Color(0.86, 0.78, 0.52))
	StructureParts.table(b, Vector2(3.6, 0.6), 0.0, Vector2(1.6, 0.8))
	for i in range(3):
		b.add_box(Vector3(0.18, 0.32, 0.18), Vector3(3.2 + 0.4 * float(i), 1.0, 0.6), Color(0.30, 0.62, 0.66), 0.0, false)
	StructureParts.crate(b, Vector2(-4.4, -0.2))
	StructureParts.signpost(b, Vector2(-1.6, 3.0), 0.0, Color(0.30, 0.62, 0.66))

static func _wheelwright(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-4.5, -5.0, 5.5, 4.2)
	StructureParts.box_house(b, r, 2.8, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.8, 1.8, roof)
	StructureParts.lean_to(b, Rect2(1.8, -4.8, 3.0, 3.6), 2.4, roof, true)
	StructureParts.wheel_stack(b, Vector2(3.6, 1.2), 0.7, 3)
	StructureParts.wheel_stack(b, Vector2(-3.6, 1.2), 0.6, 2)
	b.add_box(Vector3(1.4, 0.2, 2.6), Vector3(3.2, 0.6, -2.8), StructureParts.COL_WOOD_LIGHT, 0.0, true)
	StructureParts.log_stack(b, Vector2(-4.4, -1.2), PI * 0.5)
	StructureParts.signpost(b, Vector2(-1.6, 2.4), 0.0, Color(0.58, 0.40, 0.22))

static func _scriptorium(b: PartBatch, roof: Color) -> void:
	var r := Rect2(-3.5, -4.5, 7.0, 4.4)
	StructureParts.box_house(b, r, 3.0, StructureParts.COL_PLASTER, 1.2, 2.2, 0, 0.0, 3)
	StructureParts.gable_over(b, r, 3.0, 1.9, roof)
	StructureParts.chimney(b, Vector3(2.6, 3.0, -3.2), 1.6)
	StructureParts.table(b, Vector2(2.8, 2.2), 0.0, Vector2(1.4, 0.8))
	b.add_box(Vector3(0.5, 0.06, 0.38), Vector3(2.8, 0.85, 2.2), Color(0.94, 0.92, 0.84), 0.0, false)
	StructureParts.bench(b, Vector2(-2.8, 2.2), 0.0, 1.4)
	StructureParts.lamp_post(b, Vector2(-3.6, 3.6), 2.6, true)
	StructureParts.crate(b, Vector2(3.6, 0.6))

static func _fishery(b: PartBatch, wall: Color, roof: Color) -> void:
	var r := Rect2(-5.0, -5.0, 5.0, 3.8)
	StructureParts.box_house(b, r, 2.6, wall, 1.2, 2.1, 0, 0.0, 1)
	StructureParts.gable_over(b, r, 2.6, 1.6, roof)
	StructureParts.drying_rack(b, Vector2(2.4, -4.4), Vector2(2.4, -1.4), [Color(0.50, 0.60, 0.72), Color(0.56, 0.66, 0.76), Color(0.46, 0.56, 0.68)], 1.9)
	StructureParts.boat(b, Vector2(3.8, 1.8), 0.2)
	StructureParts.barrel(b, Vector2(-4.4, -0.4))
	StructureParts.crate(b, Vector2(-3.4, -0.2))
	StructureParts.jetty(b, Vector2(-4.5, 4.6), Vector2(0.5, 5.4), 1.4)
	StructureParts.signpost(b, Vector2(-2.0, 3.4), 0.0, Color(0.28, 0.46, 0.58))
