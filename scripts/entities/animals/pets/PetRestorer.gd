class_name PetRestorer
extends RefCounted

## PetRestorer — Stellt gespeicherte Pets beim Laden der Welt wieder her.
##
## Ausgelagert aus WorldSpawner._restore_pets() (v28).
## Liest Pet-Daten aus WorldData.get_meta("saved_pets") und spawnt sie über
## EntityOrchestrator.spawn_entity("pet", ...) — nicht per direktem
## PetComponent.new() + add_child() (siehe AnimalCatcher für dieselbe
## Begründung: Replikation an andere Peers braucht die EntityRegistry-Definition).

const LOG_CAT := "PetRestorer"

var _data: WorldData
var _orchestrator: EntityOrchestrator

func _init(data: WorldData, orchestrator: EntityOrchestrator) -> void:
	_data = data
	_orchestrator = orchestrator

func restore(_world_root: Node3D) -> void:
	if not is_instance_valid(_data) or not _data.has_meta("saved_pets"):
		return
	var pet_data: Variant = _data.get_meta("saved_pets")
	if not pet_data is Array:
		return

	var restored := 0
	for entry in pet_data:
		if not entry is Dictionary:
			continue
		var pos: Variant = str_to_var(entry.get("pos", "Vector3(0,1,0)"))
		if not pos is Vector3:
			continue
		var col: Variant = str_to_var(entry.get("color", "Color(0.7,0.5,0.3,1)"))
		# BUGFIX ("Pets schrumpfen nach Save/Load zu kleinen Kugeln"): body_size fehlte
		# hier komplett im config-Dict — ohne es fällt PetComponent.on_spawn() auf seinen
		# winzigen Klassen-Default zurück. Alte Saves (von vor dem get_save_state()-Fix)
		# haben kein "body_size"-Feld -> defensiver Default identisch zu PetComponent._body_size,
		# kein Crash, kein Absturz auf String->Vector3-Fehlparsen (siehe color-Pattern oben).
		var bsize: Variant = str_to_var(entry.get("body_size", "Vector3(0.3,0.4,0.3)"))
		var config := {
			"name":          entry.get("name", "Pet"),
			"color":         col if col is Color else Color(0.7, 0.5, 0.3),
			"body_size":     bsize if bsize is Vector3 else Vector3(0.3, 0.4, 0.3),
			"speed":         entry.get("speed", 4.0),
			# species_id fehlt in Saves von vor dem Reit-Feature → "" (Pet ist dann kein Reittier).
			"species_id":    String(entry.get("species_id", "")),
			# BUGFIX ("Nach dem Fangen ist das ursprüngliche Modell weg"): fehlten hier
			# komplett — Saves von vor diesem Fix haben diese Felder nicht, Defaults
			# entsprechen AnimalVisualProfile's eigenen Defaults (identisch zu
			# PetComponent._ear_style etc.), kein Crash bei alten Saves.
			"ear_style":       entry.get("ear_style", AnimalVisualProfile.EarStyle.ROUND),
			"tail_style":      entry.get("tail_style", AnimalVisualProfile.TailStyle.STUB),
			"snout_style":     entry.get("snout_style", AnimalVisualProfile.SnoutStyle.SHORT),
			"headgear_style":  entry.get("headgear_style", AnimalVisualProfile.HeadgearStyle.NONE),
			"tail_scale":      entry.get("tail_scale", 1.0),
			# body_plan/wing_style/back_style fehlen in Saves von vor diesem Fix —
			# Defaults entsprechen AnimalVisualProfile.BodyPlan.QUADRUPED / WingStyle.NONE /
			# BackStyle.NONE (generisches "Standardtier"), kein Crash bei alten Saves.
			"body_plan":       entry.get("body_plan", AnimalVisualProfile.BodyPlan.QUADRUPED),
			"wing_style":      entry.get("wing_style", AnimalVisualProfile.WingStyle.NONE),
			"back_style":      entry.get("back_style", AnimalVisualProfile.BackStyle.NONE),
			# body_shape/leg_style fehlen in Saves von vor diesem Fix — Defaults entsprechen
			# AnimalVisualProfile.BodyShape.NORMAL / LegStyle.NORMAL (unverändertes Verhalten).
			"body_shape":      entry.get("body_shape", AnimalVisualProfile.BodyShape.NORMAL),
			"leg_style":       entry.get("leg_style", AnimalVisualProfile.LegStyle.NORMAL),
			# pattern_style/pattern_color fehlen in Saves von vor diesem Fix — Default NONE
			# (unverändertes Verhalten, reine Flächenfarbe).
			"pattern_style":   entry.get("pattern_style", AnimalVisualProfile.PatternStyle.NONE),
			"pattern_color":   entry.get("pattern_color", Color(0.12, 0.10, 0.09)),
			# accent_style fehlt in Saves von vor diesem Feld — Default NONE (unverändert).
			"accent_style":    entry.get("accent_style", AnimalVisualProfile.AccentStyle.NONE),
			# owner_peer_id fehlt in Saves von vor diesem Fix — Default 1 (Solo/Host),
			# kein Absturz, keine Fehl-Zuordnung an einen falschen Spieler.
			"owner_peer_id": entry.get("owner_peer_id", 1),
			# owner_player_id fehlt in Saves von vor diesem Feld — leerer String,
			# PetComponent.on_spawn() löst ihn dann best-effort über NetworkBridge
			# nach (siehe dortiger Kommentar), genau wie bei einem frischen Fang.
			"owner_player_id": entry.get("owner_player_id", ""),
			# FEATURE (Pet-Fähigkeiten): Saves von vor diesem Feature haben kein
			# "abilities"-Feld — PetAbilities.sanitize(null) liefert dann ein
			# leeres Array (PetComponent.on_spawn()), das Pet bleibt bis zu einer
			# künftigen Neuzuweisung ohne Fähigkeiten. Bewusst KEIN
			# artenbasierter Fallback hier: die Tierart des ursprünglich
			# gefangenen Tieres ist zu diesem Zeitpunkt nicht mehr bekannt (nur
			# noch der generische Pet-Name "Zahmes X" als String).
			"abilities": PetAbilities.sanitize(entry.get("abilities", [])),
			# FEATURE (Pet-XP/Level): Saves von vor diesem Feature haben kein
			# "xp"-Feld — Default 0 (Level 1), kein Absturz.
			"xp": entry.get("xp", 0),
			# battle_team fehlt in Saves von vor den Pet-Kämpfen → false (kein Kampfteam).
			"battle_team": bool(entry.get("battle_team", false)),
		}
		var pet := _orchestrator.spawn_entity("pet", pos, config, config["owner_peer_id"])
		if is_instance_valid(pet):
			restored += 1
		else:
			AppLogger.log_warn("Pet-Wiederherstellung fehlgeschlagen für Eintrag: %s" % str(entry), LOG_CAT)

	AppLogger.log_info("Pets wiederhergestellt: %d." % restored, LOG_CAT)
