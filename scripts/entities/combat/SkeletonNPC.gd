extends EnemyNPC
class_name SkeletonNPC

## SkeletonNPC — Zweiter Gegnertyp. Beweist dass EnemyNPC-Parametrisierung
## über on_spawn(cfg) funktioniert ohne Lifecycle-Code zu duplizieren.
##
## Unterschiede zu Goblin:
##   - Höhere HP (50 vs 30), geringerer Schaden (3 vs 5) — tankiger Typ
##   - Schneller (3.5 vs 2.5) — erfordert andere Kampf-Taktik
##   - Blau-graue Farbe damit Spieler ihn visuell unterscheidet
##   - Eigenes LootTable-Preset (skeleton_loot) und CombatProfile (skeleton)
##   - XP-Reward höher (35 vs 20) — schwieriger zu besiegen
##
## Neue Gegnertypen: nur diese Klasse als Vorlage nehmen,
## _get_defaults() überschreiben, in WorldEntityRegistry.register_all() eintragen.
##
## KEIN Lifecycle-Code hier — alles läuft durch EnemyNPC.

## Überschreibt die Default-Werte die _ready() in EnemyNPC verwendet.
## Wird aufgerufen BEVOR _ready() die ersten Felder liest —
## daher reicht es die vars direkt zu setzen.
func _init() -> void:
	_color           = Color(0.55, 0.65, 0.75)  # Blau-grau
	_max_health      = 50
	_damage          = 3
	_speed           = 3.5
	_detect_range    = 10.0
	_attack_range    = 1.5
	_attack_cd       = 2.0                        # Langsamer Angriff, aber tankt mehr
	_xp_reward       = 35
	_xp_skill        = "combat"
	_loot_table_id   = "skeleton_loot"
	_label           = "Skelett"
	_combat_profile_id = "skeleton"
	_type_id         = "skeleton"
