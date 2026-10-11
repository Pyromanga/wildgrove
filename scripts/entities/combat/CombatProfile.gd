# res://scripts/entities/combat/CombatProfile.gd
class_name CombatProfile extends Resource

## CombatProfile — Resistenz-Profil für eine Entity-Klasse.
##
## Löst TD-10 (ADR-008): Resistenzwerte (Rüstung, Magie-Resistenz) lagen vorher
## nicht vor — CombatSystem.calculate_damage() nahm target_armor/target_magic_resist
## als lose Parameter entgegen, die jeder Call-Site selbst hartcoden musste.
##
## NACHHER: Jede Entity-Klasse referenziert ein CombatProfile über DataService
## (res://data/combat_profiles/*.tres) statt Resistenzwerte am Call-Site zu raten.
##
## WARUM ZWEI FLOATS STATT EINEM Dictionary[DamageType, float]:
## Godots Resource-Inspector kann Dictionaries mit Enum-Keys nicht editierbar
## darstellen. Zwei benannte @export-Felder bleiben im Editor bearbeitbar und
## sind funktional identisch zu einem DamageType-Dictionary mit zwei Einträgen.
## TRUE-Schaden hat bewusst kein Feld — er ignoriert per ADR-008 immer Resistenz.
## Ein neuer DamageType (z.B. FIRE) bekommt ein eigenes @export-Feld nach
## demselben Schema plus einen neuen match-Zweig in get_resistance().
##
## VERWENDUNG:
##   var profile: CombatProfile = data_service.get_combat_profile("goblin")
##   var record := combat.calculate_damage_with_profile(record, profile)
##
## ZUKÜNFTIGE ERWEITERUNG (kein Equipment-System heute):
## Wenn Equipment-Boni ankommen, sollte Rüstung aus zwei Quellen zusammengesetzt
## werden: dieser statische Basiswert (Spezies/Klasse) + ein dynamischer
## StatModifier-Bonus (Ausrüstung, Buffs) on top. CombatProfile bleibt dabei die
## Basis — es wird NICHT durch StatModifier ersetzt, sondern ergänzt.

@export var id: String = ""
@export var display_name: String = ""

## Physische Rüstung (DamageType.PHYSICAL). 0.0 = keine Rüstung.
## CombatSystem.calculate_damage() clamped auf max. 0.85 — nie 100 % Mitigation.
@export_range(0.0, 1.0, 0.01) var armor: float = 0.0

## Magische Resistenz (DamageType.MAGIC). Gleiches Schema wie armor.
@export_range(0.0, 1.0, 0.01) var magic_resist: float = 0.0

## Gibt die Resistenz für einen DamageType zurück.
## TRUE ignoriert per Definition immer Resistenz (ADR-008) — gibt 0.0 zurück.
func get_resistance(damage_type: DamageRecord.DamageType) -> float:
	match damage_type:
		DamageRecord.DamageType.PHYSICAL:
			return armor
		DamageRecord.DamageType.MAGIC:
			return magic_resist
		_:
			return 0.0

## Neutrales Fallback-Profil (keine Resistenz) — wird genutzt wenn DataService
## keine Definition für eine angefragte ID findet (z.B. neue Entity-Klasse ohne
## eigenes .tres). Verhindert, dass calculate_damage_with_profile() einen
## null-Check pro Call-Site erzwingt.
static func default_profile() -> CombatProfile:
	var p := CombatProfile.new()
	p.id = "default"
	p.display_name = "Unbewaffnet"
	return p
