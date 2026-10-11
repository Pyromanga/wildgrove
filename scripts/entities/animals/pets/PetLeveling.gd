class_name PetLeveling
extends RefCounted

## PetLeveling — reine, statische XP-Kurve fürs generelle Pet-Level (Wunsch
## "Pets sollen XP bekommen wie der Spieler auch, muss nicht in einem Skill
## sein, Cap bei 100").
##
## BEWUSST NICHT über SkillDefinition/SkillSystem — das ist Spieler-Progression
## pro einzelnem Skill (Holzfällen, Bergbau, ...). Ein Pet-Level ist stattdessen
## EIN einziger, globaler Fortschrittswert pro Pet, unabhängig davon welche
## Fähigkeit es gerade ausübt (ein Pet, das sammelt UND kämpft, levelt durch
## beides gleichermaßen hoch).
##
## KURVE/BALANCING (Wunsch "Formel ist halb so wichtig, kann man einfach
## fixen"): bewusst simpel gehalten (linear statt wie bei Skills exponentiell
## mit Scaling-Faktor) — ein einziger Ort (XP_PER_LEVEL_STEP unten) zum Tunen,
## keine .tres-Ressourcen-Infrastruktur wie bei Skills, weil Pet-Level kein
## Content ist, den Designer ohne Code-Änderung balancen müssen sollen.

## Wie viel mehr XP jedes Level zusätzlich zum vorherigen braucht (linear).
## Level 1→2: 30 XP, 2→3: 60 XP, 3→4: 90 XP, ... Level 99→100: 2970 XP.
## Leicht anzupassen, falls sich das zu schnell/langsam anfühlt.
const XP_PER_LEVEL_STEP := 30

const MAX_LEVEL := 100

## XP-Belohnung je abgeschlossener Pet-Aktion — bewusst EIN flacher Wert pro
## Fähigkeits-Kategorie statt pro einzelnem Item/Gegner differenziert (siehe
## Klassenkommentar: "Formel ist halb so wichtig"). Einfach anzupassen, falls
## sich eine Fähigkeit zu schnell/langsam leveln soll.
const XP_HARVEST := 5   ## gathering / mining / woodcutting, pro abgeschlossener Ernte.
const XP_COMBAT  := 3   ## pro gelandetem Angriff (nicht erst beim Kill — siehe PetAbilityComponent._do_attack()).
const XP_DIG     := 5   ## pro abgeschlossenem Grabversuch.

## Wie viel XP insgesamt nötig ist, um level zu erreichen (kumulativ ab Level 1,
## 0 XP). Für level<=1 immer 0.
static func xp_required_for_level(level: int) -> int:
	if level <= 1:
		return 0
	var capped_level: int = mini(level, MAX_LEVEL)
	# Summe einer arithmetischen Reihe: Stufe i (1-basiert, i=1..capped_level-1)
	# kostet i * XP_PER_LEVEL_STEP XP. Geschlossene Form statt Schleife.
	var steps: int = capped_level - 1
	return int(steps * (steps + 1) / 2.0 * XP_PER_LEVEL_STEP)

## Errechnet Level + Rest-Fortschritt aus einer absoluten Gesamt-XP-Zahl.
## Gibt ein Dictionary zurück: {"level": int, "xp_into_level": int, "xp_for_next": int}
## xp_for_next == -1 bei MAX_LEVEL (kein weiteres Level mehr möglich).
static func resolve(total_xp: int) -> Dictionary:
	var level := 1
	while level < MAX_LEVEL and total_xp >= xp_required_for_level(level + 1):
		level += 1
	var xp_for_next: int = -1 if level >= MAX_LEVEL else xp_required_for_level(level + 1) - xp_required_for_level(level)
	var xp_into_level: int = total_xp - xp_required_for_level(level)
	return {
		"level": level,
		"xp_into_level": xp_into_level,
		"xp_for_next": xp_for_next,
	}

## XP-Belohnung je Fähigkeit (siehe PetAbilities-Konstanten). Unbekannte/neue
## Fähigkeits-IDs fallen auf 0 zurück statt zu crashen — ein Pet mit einer ID,
## für die es (noch) keinen XP-Betrag gibt, levelt dadurch einfach nicht hoch,
## bricht aber nichts.
static func xp_reward_for(ability_id: String) -> int:
	if PetAbilities.is_harvest_ability(ability_id):
		return XP_HARVEST
	match ability_id:
		PetAbilities.COMBAT:
			return XP_COMBAT
		PetAbilities.DIGGING:
			return XP_DIG
		_:
			return 0
