class_name WorkSchedule
extends RefCounted

## WorkSchedule — Tagesablauf eines Berufs-NPCs als reine Funktion der Uhrzeit (kein Zustand).
##
## shift = {start, end, break: [von, bis], free_until} in Spielstunden (0..24, Bruch erlaubt):
##   start..end          WORK  (mit Pause break[0]..break[1] → BREAK)
##   end..free_until     FREE  (Feierabend: steht im Dorf, plaudert)
##   free_until..start   SLEEP (zu Hause: NPC unsichtbar und nicht ansprechbar)
## Fenster dürfen über Mitternacht laufen (end < start). Uhr = WorldService.day_time.

enum State { SLEEP, WORK, BREAK, FREE }

static func in_window(hour: float, from: float, to: float) -> bool:
	var h: float = fposmod(hour, 24.0)
	var a: float = fposmod(from, 24.0)
	var b: float = fposmod(to, 24.0)
	if is_equal_approx(a, b):
		return false
	if a < b:
		return h >= a and h < b
	return h >= a or h < b

static func state_at(hour: float, shift: Dictionary) -> int:
	var start: float = float(shift["start"])
	var end: float = float(shift["end"])
	var free_until: float = float(shift["free_until"])
	if in_window(hour, start, end):
		var brk: Array = shift.get("break", [])
		if brk.size() == 2 and in_window(hour, float(brk[0]), float(brk[1])):
			return State.BREAK
		return State.WORK
	if in_window(hour, end, free_until):
		return State.FREE
	return State.SLEEP

## "" = gültig, sonst Fehlertext (für Tests/Katalog-Prüfung).
static func validate(shift: Dictionary) -> String:
	for key in ["start", "end", "free_until"]:
		if not shift.has(key):
			return "Feld '%s' fehlt." % key
	var start: float = float(shift["start"])
	var end: float = float(shift["end"])
	if not in_window(start + 0.01, start, end):
		return "Arbeitsfenster leer."
	var brk: Array = shift.get("break", [])
	if not brk.is_empty():
		if brk.size() != 2:
			return "break braucht [von, bis]."
		if not in_window(float(brk[0]), start, end) or not in_window(float(brk[1]) - 0.01, start, end):
			return "Pause liegt nicht in der Arbeitszeit."
	return ""

static func state_name(state: int) -> String:
	match state:
		State.WORK: return "work"
		State.BREAK: return "break"
		State.FREE: return "free"
		_: return "sleep"
