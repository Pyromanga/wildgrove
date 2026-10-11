class_name UuidGen
# justified: reine Utility-Klasse, keine ServiceNode/Service-Semantik nötig (nur eine
# statische Funktion) — kein DI-Eintrag, keine configure()/on_ready()-Lifecycle.

## UuidGen — lokale, RFC-4122-artige UUID-v4-Erzeugung.
##
## ADR-029: für `SaveSystem.player_uuid`/`player_secret` gedacht — beides wird
## LOKAL auf dem jeweiligen Gerät erzeugt (keine Autorität/Netzwerk-Koordination
## nötig, anders als `EntityOrchestrator._generate_uuid()`, das absichtlich nur
## von der Autorität aufgerufen werden darf, weil Entity-UUIDs netzwerkweit
## eindeutig und konsistent sein müssen). `player_uuid`/`player_secret` sind
## rein lokale Zufallswerte — Kollisionsfreiheit kommt aus der Zufallsbreite
## (122 Bit bei v4), nicht aus zentraler Vergabe.
##
## Absichtlich eigenständig statt `EntityOrchestrator._generate_uuid()`
## wiederzuverwenden: unterschiedliche Aufrufer-Constraints (kein
## Autoritäts-Guard hier), unterschiedlicher Lebenszyklus (Save-Erzeugung vs.
## Entity-Spawn). Das Bit-Format (Version-4/Variant-Bits) ist absichtlich
## identisch gehalten — reiner Formatstandard, keine Kopplung.

static func generate_v4() -> String:
	var a := randi()
	var b := randi()
	var c := randi()
	var d := randi()
	# Version-Bits setzen: version=4 (0100xxxx), variant=10xx (RFC 4122)
	c = (c & 0x0FFF) | 0x4000
	d = (d & 0x3FFFFFFF) | 0x80000000
	return "%08x-%04x-%04x-%04x-%04x%08x" % [
		a,
		(b >> 16) & 0xFFFF,
		c & 0xFFFF,
		(c >> 16) & 0xFFFF,
		d & 0xFFFF,
		d >> 16
	]
