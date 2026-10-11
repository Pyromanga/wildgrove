extends EnemyNPC
class_name WerewolfNPC

## WerewolfNPC — Special-Encounter-Gegner (siehe ConditionalEncounterService):
## spawnt NUR nachts in forest/dense_forest/mountain, nicht über
## BiomeDefinition.enemy_chances wie goblin/skeleton.
##
## Unterschiede zu Goblin/Skeleton:
##   - Hohe HP (70) UND hoher Schaden (8) — bewusst bedrohlicher als die
##     permanenten Gegnertypen, als Belohnung für das selten/situativ sein.
##   - Sehr schnell (4.5) — Nacht-Jäger-Gefühl, schwer zu entkommen.
##   - Dunkles Graubraun mit rötlichem Unterton (Fell + Mondlicht-Assoziation).
##
## KEIN Lifecycle-Code hier — alles läuft durch EnemyNPC (siehe SkeletonNPC.gd
## Klassenkommentar für die Vorlage/das Muster).

func _init() -> void:
	_color           = Color(0.28, 0.24, 0.22)  # Dunkles Graubraun
	_max_health      = 70
	_damage          = 8
	_speed           = 4.5
	_detect_range    = 14.0
	_attack_range    = 1.8
	_attack_cd       = 1.5
	_xp_reward       = 60
	_xp_skill        = "combat"
	_loot_table_id   = "werewolf_loot"
	_label           = "Werwolf"
	_combat_profile_id = "werewolf"
	_type_id         = "werewolf"
