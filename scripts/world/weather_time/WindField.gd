class_name WindField
extends RefCounted

## WindField — Wind ist auch nur Mathematik: kein echter Zufall, keine
## Physik-Simulation, sondern zwei überlagerte Sinuskurven aus `world_seed` +
## verstrichener Zeit. Gleiches Prinzip wie TerrainField/WeatherService
## (Seed + deterministischer Eingabewert -> überall dasselbe Ergebnis) —
## HIER bewusst NICHT netzwerk-kritisch: reine Optik (Regenwinkel, Gras-
## Sway), Peers können leicht auseinanderlaufen (eigene _t pro Peer seit
## Verbindungsaufbau) ohne dass es die Spiellogik beträfe. Siehe WeatherVfx.

## Richtung als Einheitsvektor in der XZ-Ebene.
var direction: Vector2 = Vector2.RIGHT
## Stärke in [0, 1] — 0 = Flaute, 1 = Sturm.
var strength: float = 0.3

var _t: float = 0.0
var _seed_offset: float = 0.0

func _init(world_seed: int = 0) -> void:
	# posmod statt %, damit auch negative world_seed-Werte einen stabilen,
	# positiven Offset ergeben (world_seed kann laut TerrainSeed jeder int sein).
	_seed_offset = float(posmod(world_seed, 10007))
	_recompute()

## delta in Sekunden seit dem letzten advance()-Aufruf (siehe WeatherVfx._process()).
func advance(delta: float) -> void:
	_t += delta
	_recompute()

## Für "Böen" während eines Sturms — WeatherVfx setzt dies bei "storm" höher.
func set_gust_multiplier(mult: float) -> void:
	strength = clampf(strength * mult, 0.0, 1.0)

func _recompute() -> void:
	var a: float = _t * 0.05 + _seed_offset
	direction = Vector2(cos(a), sin(a * 0.7)).normalized()
	# Zwei Frequenzen überlagert -> wirkt weniger mechanisch als eine einzelne Sinuskurve.
	var s: float = sin(_t * 0.11 + _seed_offset * 0.3) * 0.5 + sin(_t * 0.37 + _seed_offset) * 0.15
	strength = clampf(0.35 + s * 0.35, 0.0, 1.0)
