class_name ZoneConfig extends Resource

## ZoneConfig — Daten-Definition einer Zone (ADR-030, Option C).
##
## Rein deklarativ, keine Logik. Ein ZoneTriggerVolume referenziert genau
## eine ZoneConfig; mehrere Trigger-Volumes können dieselbe ZoneConfig teilen
## (z.B. eine PvP-Zone aus mehreren Teilflächen).

## Eindeutige Kennung dieser Zone, z.B. &"pvp_north_ridge". Konsumenten
## (PvP-Check, Diebstahl-Erlaubnis) filtern primär über tags, nicht zone_id —
## zone_id dient vor allem Logging/Debug und der Unterscheidung mehrerer
## Instanzen desselben Zonentyps.
@export var zone_id: StringName = &""

## Zonentyp-Tags, z.B. [&"pvp"], [&"theft"], [&"minigame:capture_the_flag"].
## Additiv/Set-basiert (ADR-030 "Mitigationen") — ein Konsument fragt nur nach
## seinem eigenen Tag und ignoriert alle anderen, keine Prioritätsauflösung.
@export var tags: Array[StringName] = []

## Optionale, konsumentenspezifische Zusatzdaten (z.B. Quest-ID, Minigame-Regeln).
## Bewusst als generisches Dictionary statt eigener Felder — ZoneConfig kennt
## die Bedeutung nicht, nur der jeweilige Konsument interpretiert sie.
@export var metadata: Dictionary = {}

func has_tag(tag: StringName) -> bool:
	return tags.has(tag)
