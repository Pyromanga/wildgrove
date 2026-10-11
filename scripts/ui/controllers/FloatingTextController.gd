class_name FloatingTextController

## FloatingTextController — zeigt XP-Gains, Level-Ups und Loot-Drops als schwebenden Text.
## Lauscht auf PlayerEvents (XP/Level) und UIEvents (Loot-Floating-Text).

var _visuals: FloatingTextVisuals
var _ctx: IUIContext

## BUGFIX (Bug #2, "Text über Spieler überlagert sich"): identisches Muster
## wie NotificationController._is_setup / InventoryUIController — kein
## `extends Node`, also reines RefCounted. Die Signalverbindungen auf dem
## langlebigen EventBus (bus() lebt in der CharacterScope-Registry, überlebt
## HUD-Rebuilds) halten eine harte Referenz auf `self` und verhindern, dass
## dieser Controller je freigegeben wird. HUDManager._on_world_scene_ready()
## ruft zwar bereits generisch teardown() auf jedem alten Controller auf,
## der die Methode anbietet (siehe dortiger Bugfix-Kommentar) — dieser
## Controller bot sie bisher aber schlicht nicht an, war also von diesem Fix
## nie erfasst. Jeder HUD-Rebuild (world_scene_ready, z.B. bei Welt-Reload
## ohne vollen Szenenwechsel) fügte einen weiteren dauerhaft lauschenden
## Zombie hinzu → bei jedem xp_gained/level_up/floating_loot_text_requested
## spawnen N überlappende Text-Labels an derselben Bildschirmposition,
## N = Anzahl bisheriger HUD-Rebuilds. Fix: disconnect in teardown().
var _is_setup: bool = false

func setup(visuals: FloatingTextVisuals, ctx: IUIContext) -> void:
	assert(ctx != null, "FloatingTextController.setup: ctx ist null!")
	if _is_setup:
		AppLogger.log_warn(
			"setup() erneut aufgerufen — vorherige Verbindung wird zuerst getrennt (teardown()).",
			"UI/FloatingText"
		)
		teardown()
	_visuals = visuals
	_ctx = ctx
	_ctx.bus().player().xp_gained.connect(_on_xp_gained)
	_ctx.bus().player().level_up.connect(_on_level_up)
	# Loot-Drop-Text über UIEvents
	_ctx.bus().ui().floating_loot_text_requested.connect(_on_floating_loot)
	_is_setup = true

## MUSS von HUDManager vor dem Verwerfen dieses Controllers aufgerufen werden
## (siehe HUDManager._on_world_scene_ready()) — sonst bleibt dieser Controller
## als Zombie-Listener am Leben (siehe Klassenkommentar zu _is_setup oben).
func teardown() -> void:
	if is_instance_valid(_ctx) and is_instance_valid(_ctx.bus()):
		if _ctx.bus().player().xp_gained.is_connected(_on_xp_gained):
			_ctx.bus().player().xp_gained.disconnect(_on_xp_gained)
		if _ctx.bus().player().level_up.is_connected(_on_level_up):
			_ctx.bus().player().level_up.disconnect(_on_level_up)
		if _ctx.bus().ui().floating_loot_text_requested.is_connected(_on_floating_loot):
			_ctx.bus().ui().floating_loot_text_requested.disconnect(_on_floating_loot)
	_is_setup = false

func _on_xp_gained(skill: String, amount: int, peer_id: int) -> void:
	# BUGFIX (2026-09-13): xp_gained liefert 3 Argumente (skill, amount,
	# peer_id) — ohne peer_id-Parameter schlug JEDER Aufruf mit einem
	# 'Method expected 2 argument(s), but called with 3' Engine-Fehler fehl,
	# XP-Floating-Text wurde nie angezeigt. Zusätzlich: nur für den lokalen
	# Spieler anzeigen, nicht für fremde peer_ids (Coop).
	if peer_id != _ctx.get_local_peer_id():
		return
	_visuals.spawn_text("+%d %s" % [amount, skill], Color(1.0, 0.9, 0.2), 24, 2.0)

func _on_level_up(skill: String, new_level: int, peer_id: int) -> void:
	if peer_id != _ctx.get_local_peer_id():
		return
	_visuals.spawn_text("LEVEL UP!\n%s → %d" % [skill, new_level], Color(0.2, 0.8, 1.0), 32, 3.0)

func _on_floating_loot(text: String, _world_pos: Vector3) -> void:
	# Loot-Text grün mit leichtem Versatz damit er sich von XP abhebt
	_visuals.spawn_text(text, Color(0.3, 1.0, 0.4), 22, 2.5)
