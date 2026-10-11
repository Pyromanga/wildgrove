extends EnemyNPC
class_name FogWraithNPC

## FogWraithNPC — Special-Encounter-Gegner (siehe ConditionalEncounterService):
## spawnt NUR bei Nebel/Sturm in swamp/meadow, nicht über
## BiomeDefinition.enemy_chances wie goblin/skeleton.
##
## Unterschiede zu Goblin/Skeleton:
##   - Niedrige HP (25) aber hoher Schaden (6) — Glaskanone, passend zu einem
##     geisterhaften Gegner der nicht lange standhält.
##   - Mittlere Geschwindigkeit (3.0), kurze Angriffsreichweite dafür knapper
##     Cooldown (1.2s) — "schwirrt umher" statt stur anzurennen.
##   - Blass-bläuliches Grau mit niedriger Deckkraft-Anmutung (Nebel-Optik
##     über die Farbe allein, kein echtes Transparenz-Material nötig für
##     einen Platzhalter-Würfel).
##
## KEIN Lifecycle-Code hier — alles läuft durch EnemyNPC (siehe SkeletonNPC.gd
## Klassenkommentar für die Vorlage/das Muster).

func _init() -> void:
	_color           = Color(0.70, 0.76, 0.80)  # Blass-bläuliches Nebelgrau
	_max_health      = 25
	_damage          = 6
	_speed           = 3.0
	_detect_range    = 11.0
	_attack_range    = 1.3
	_attack_cd       = 1.2
	_xp_reward       = 45
	_xp_skill        = "combat"
	_loot_table_id   = "fog_wraith_loot"
	_label           = "Nebelgeist"
	_combat_profile_id = "fog_wraith"
	_type_id         = "fog_wraith"
