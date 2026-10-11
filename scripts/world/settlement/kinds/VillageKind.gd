class_name VillageKind
extends RefCounted

## VillageKind — Basisklasse einer DORF-ART (Boden-, Baum-, später Fischer-/Schnee-/Pilz-/Wolken-/Höhlendorf).
##
## Warum eine eigene Ebene: Standort (SettlementSites), Straßen (RoadPaths), Registry und Karte sind für
## alle Arten gleich. Verschieden sind nur fünf Dinge — und die stehen hier an EINER Stelle:
##   1. wo die Art siedeln darf          → site_score()
##   2. wie groß sie je Stufe ist        → tier_radius() / tier_label()
##   3. wie sie aufgebaut wird           → plan()   (Gebäudeliste + Straßen + Wege, deterministisch)
##   4. welche Gebäudetypen sie hat      → catalog()
##   5. wie ein Gebäudetyp aussieht      → build_type()
##
## Eine neue Art = eine Unterklasse + EIN Eintrag in VillageKinds.SPECIAL_ORDER (siehe docs/settlements.md,
## "Neue Dorf-Art hinzufügen"). Sonst muss kein bestehender Code angefasst werden.
##
## Regeln für Unterklassen: rein deterministisch (nur world_seed + Basis-Gelände, kein Zufall ohne Seed,
## keine Zeit), kein Zustand — eine Instanz wird von allen Dörfern geteilt.

const TIER_HAMLET := "hamlet"
const TIER_VILLAGE := "village"
const TIER_TOWN := "town"

## Technische ID ("ground", "canopy", …). Steht im Standort (`site["kind"]`) und im Spielstand-Seed-Pfad.
func id() -> String:
	return ""

## Anteil der Standorte (0..1), auf denen diese Art ZUERST versucht wird. Passt der Ort nicht,
## fällt der Standort auf die nächste Art zurück (zuletzt "ground"). 0 = nur Rückfall-Art.
func chance() -> float:
	return 0.0

## Symbol der Karte ("house", "tree", …). Neue Symbole in WorldMapView._draw_site_icon ergänzen.
func icon() -> String:
	return "house"

func tier_radius(_tier: String) -> float:
	return 40.0

func tier_label(tier: String) -> String:
	return tier

## Endungen der Ortsnamen (leer = Standard-Endungen von VillageNames).
func name_suffixes() -> Array[String]:
	return []

## Eignung eines Punktes als Dorfzentrum: kleiner Wert = besser, negativ = ungeeignet.
func site_score(_field: TerrainField, _p: Vector2, _radius: float) -> float:
	return -1.0

## Planung: {buildings: Array[Dictionary], streets: Array[Dictionary], paths: Array[Dictionary]}.
## `incoming`: Array[PackedVector2Array] — Fernstraßen, jeweils VOM Zentrum nach außen.
## Gebäude: {id, type, x, z, yaw, y, spread, variant, site, params?}; `params` ist frei für die Art.
func plan(_field: TerrainField, _site: Dictionary, _incoming: Array) -> Dictionary:
	return {"buildings": [], "streets": [], "paths": []}

## Gebäudetypen dieser Art: type_id → {half: Vector2, slab: Color | (fehlt = keine Bodenplatte), npcs: Array}.
func catalog() -> Dictionary:
	return {}

## Geometrie eines Gebäudetyps dieser Art in `b` (lokale Koordinaten, y = 0 = Boden-Oberkante).
## `info` = der Gebäude-Datensatz aus plan() (spread, params, …); leer im Katalog-Test.
func build_type(_type_id: String, _b: PartBatch, _variant: int, _slab_depth: float, _info: Dictionary) -> void:
	pass
