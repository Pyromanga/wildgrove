extends Node
## SkillSystem.gd — Autoload Singleton
## RuneScape-artiges Skill-System
## Registrieren in Project → Autoload als "SkillSystem"

signal xp_gained(skill: String, amount: int, new_total: int)
signal level_up(skill: String, new_level: int)

# ── Skill-Definitionen ─────────────────────────────────────────────────────
const SKILLS: Array[String] = [
	# Kampf
	"attack", "strength", "defense", "hitpoints", "ranged", "magic",
	# Gathering
	"woodcutting", "fishing", "mining", "farming", "foraging",
	# Crafting
	"crafting", "cooking", "smithing", "herbalism",
	# Misc
	"agility", "construction",
]

const SKILL_LABELS: Dictionary = {
	"attack":      "Angriff",
	"strength":    "Stärke",
	"defense":     "Verteidigung",
	"hitpoints":   "Trefferpunkte",
	"ranged":      "Fernkampf",
	"magic":       "Magie",
	"woodcutting": "Holzfällen",
	"fishing":     "Angeln",
	"mining":      "Bergbau",
	"farming":     "Landwirtschaft",
	"foraging":    "Sammeln",
	"crafting":    "Handwerk",
	"cooking":     "Kochen",
	"smithing":    "Schmieden",
	"herbalism":   "Kräuterkunde",
	"agility":     "Agilität",
	"construction":"Bauen",
}

const MAX_LEVEL: int = 99

# ── XP-Kurve (RuneScape-Formel) ────────────────────────────────────────────
static func xp_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var total: int = 0
	for i in range(1, level):
		total += int(i + 300.0 * pow(2.0, float(i) / 7.0))
	return total / 4


static func level_from_xp(xp: int) -> int:
	for lvl in range(MAX_LEVEL, 0, -1):
		if xp >= xp_for_level(lvl):
			return lvl
	return 1


# ── State ──────────────────────────────────────────────────────────────────
var _xp: Dictionary = {}      # skill → int
var _level: Dictionary = {}   # skill → int (gecacht)


func _ready() -> void:
	add_to_group("skill_system")
	for skill in SKILLS:
		_xp[skill]    = 0
		_level[skill] = 1
	# Hitpoints startet bei Level 10
	add_xp("hitpoints", xp_for_level(10))


# ── XP hinzufügen ──────────────────────────────────────────────────────────
func add_xp(skill: String, amount: int) -> void:
	if not skill in _xp:
		push_warning("[SkillSystem] Unbekannter Skill: " + skill)
		return
	if amount <= 0:
		return

	_xp[skill] += amount
	emit_signal("xp_gained", skill, amount, _xp[skill])

	var new_level: int = level_from_xp(_xp[skill])
	if new_level > _level[skill]:
		_level[skill] = new_level
		emit_signal("level_up", skill, new_level)
		print("[SkillSystem] LEVEL UP! %s → %d" % [get_label(skill), new_level])


# ── Getter ─────────────────────────────────────────────────────────────────
func get_level(skill: String) -> int:
	return _level.get(skill, 1)


func get_xp(skill: String) -> int:
	return _xp.get(skill, 0)


func get_xp_to_next(skill: String) -> int:
	var lvl: int = _level.get(skill, 1)
	if lvl >= MAX_LEVEL:
		return 0
	return xp_for_level(lvl + 1) - _xp.get(skill, 0)


func get_label(skill: String) -> String:
	return SKILL_LABELS.get(skill, skill)


func meets_requirement(skill: String, req_level: int) -> bool:
	return get_level(skill) >= req_level


# ── Speichern / Laden ──────────────────────────────────────────────────────
func to_dict() -> Dictionary:
	return { "xp": _xp.duplicate(), "level": _level.duplicate() }


func from_dict(data: Dictionary) -> void:
	if data.has("xp"):
		for skill in data["xp"]:
			if skill in _xp:
				_xp[skill] = data["xp"][skill]
	if data.has("level"):
		for skill in data["level"]:
			if skill in _level:
				_level[skill] = data["level"][skill]
