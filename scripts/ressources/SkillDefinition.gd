class_name SkillDefinition
extends Resource

## SkillDefinition — Statische Daten für einen Skill als .tres-Ressource.
##
## NEU (Session 4): Ersetzt hardkodiertes Dictionary in SkillSystem.
##   VORHER: skills = { "woodcutting": {...}, "mining": {...} } im Code
##           → neuer Skill = Code-Änderung an SkillSystem
##   NACHHER: res://data/skills/woodcutting.tres, mining.tres, etc.
##            → neuer Skill = neue .tres-Datei, kein Code-Anfassen
##
## DataService lädt alle *.tres aus res://data/skills/ automatisch.
## SkillSystem initialisiert sich daraus statt aus hardkodiertem Dict.
##
## XP-Kurve: xp_to_level_up[i] = benötigte XP für Level (i+2)
##   Beispiel: xp_to_level_up = [100, 250, 500, 900]
##             → Level 1→2: 100 XP, 2→3: 250 XP, 3→4: 500 XP, 4→5: 900 XP
##   Letzter Wert gilt für alle weiteren Level (extrapoliert mit Multiplikator).

@export var id:           String   = ""
@export var display_name: String   = ""
@export var description:  String   = ""
@export var icon:         Texture2D

## XP-Kosten pro Level-Up (0-indiziert: [0] = Level 1→2, [1] = Level 2→3, …)
@export var xp_to_level_up: Array[int] = [100, 250, 500, 900, 1400, 2000]

## Multiplikator für Level über dem letzten definierten Eintrag.
@export var xp_scaling_factor: float = 1.5

## Maximales Level. -1 = unbegrenzt (extrapoliert via xp_scaling_factor).
@export var max_level: int = 99


## Gibt die benötigte XP-Menge für einen Level-Up zurück.
## level = aktuelles Level (1-basiert).
func get_xp_required(level: int) -> int:
	var idx := level - 1  # Level 1 → Index 0
	if idx < xp_to_level_up.size():
		return xp_to_level_up[idx]
	# Extrapolation: letzter Wert × Scaling ^ Überlauf-Stufen
	var base:     int   = xp_to_level_up[-1] if not xp_to_level_up.is_empty() else 100
	var overflow: int   = idx - xp_to_level_up.size() + 1
	return int(float(base) * pow(xp_scaling_factor, overflow))
