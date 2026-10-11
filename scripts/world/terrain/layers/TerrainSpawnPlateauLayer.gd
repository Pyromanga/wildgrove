class_name TerrainSpawnPlateauLayer
extends TerrainLayer

## TerrainSpawnPlateauLayer — ebnet den Startbereich um den Ursprung ein.
##
## Dorf/NPCs/Ackerbeete/Spawn liegen bei (0..25, ...). Ohne Plateau hing es vom Seed ab, ob
## dort Wiese, Hang, Fluss oder See war. Jetzt: innerhalb von spawn_flat_radius exakt
## spawn_height (trocken, eben), bis spawn_blend_radius weich in das umliegende Gelände
## überblendet (S-Kurve, keine Kante).
##
## Läuft NACH Basis und Fluss, damit weder Becken noch Flussbett den Spawn fluten.

var _cfg: TerrainConfig

func _init(cfg: TerrainConfig) -> void:
	_cfg = cfg

func apply(world_x: float, world_z: float, h: float) -> float:
	var dist: float = Vector2(world_x, world_z).length()
	if dist >= _cfg.spawn_blend_radius:
		return h
	var w: float = 1.0 - smoothstep(_cfg.spawn_flat_radius, _cfg.spawn_blend_radius, dist)
	return lerpf(h, _cfg.spawn_height, w)
