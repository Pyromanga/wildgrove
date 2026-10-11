class_name WorldSeedUtil
extends RefCounted

## WorldSeedUtil — einzige Quelle für "world_seed ist 0 -> neu würfeln".
##
## Wunsch ("kann es sein, dass world_seed immer 0 ist?"): es gab VORHER DREI unabhängige
## Kopien derselben Zeit-Fallback-Formel (WorldService.configure(),
## WorldService.on_world_scene_ready() für TerrainField, WorldSpawner._generate_positions()
## für die Entity-Positionen) — bei leicht unterschiedlichem Timing (z.B. zwei Aufrufe in
## unterschiedlichen Frames) hätten diese unterschiedliche Werte erzeugen können, obwohl sie
## alle denselben world_seed meinten. Schlimmer: on_world_scene_ready()s TerrainField-Zweig
## LOGGTE einen irreführenden "nutzt Default-Seed (1337)"-Hinweis, übergab TerrainField dann
## aber weiterhin die rohe 0 — ein reiner Logging-Bug ohne echten Fallback, data.world_seed
## blieb an dieser Stelle tatsächlich 0. Jetzt: EINE Formel, UND jeder Aufrufer schreibt das
## Ergebnis zurück nach data.world_seed (nicht nur in eine lokale Variable) — damit alle
## Konsumenten (Terrain, Spawner, Wetter, Speicherstand) auch wirklich denselben, tatsächlich
## von 0 verschiedenen Wert sehen, egal wer zuerst dran war.
##
## world_seed == 0 bleibt der Sentinel für "noch nie gesetzt" (WorldData-Default, siehe dort) —
## 0 selbst ist also bewusst NIE ein gültiger, tatsächlich genutzter Seed-Wert im laufenden
## Spiel, auch wenn & 0x7FFFFFFF rein rechnerisch 0 liefern könnte (astronomisch
## unwahrscheinlich bei einem echten Unix-Timestamp, aber nicht unmöglich — siehe resolve()).
static func resolve(current: int) -> int:
	if current != 0:
		return current
	var fallback := int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	# Siehe Klassenkommentar letzter Absatz — im (praktisch nie eintretenden) Fall, dass die
	# Maskierung selbst 0 ergibt, auf TerrainConfig.DEFAULT_SEED ausweichen statt den
	# 0-Sentinel versehentlich als "gültigen" Seed durchzureichen.
	return fallback if fallback != 0 else TerrainConfig.DEFAULT_SEED
