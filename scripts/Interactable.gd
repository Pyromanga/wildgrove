extends Node3D
## Interactable.gd
## Basis-Klasse für alle interagierbaren Objekte in der Welt.
## Erben: Baum, Erz, NPC, Truhe, etc.
##
## Verwendung:
##   1. Node3D erstellen
##   2. Dieses Script anhängen
##   3. @export Felder im Inspector setzen
##   4. interact() überschreiben für spezifisches Verhalten

signal interaction_started(interactable: Node3D, player: Node3D)
signal interaction_completed(interactable: Node3D, result: Dictionary)
signal interaction_failed(interactable: Node3D, reason: String)

@export var interaction_label: String = "Interagieren"  # Text der über dem Objekt erscheint
@export var interaction_radius: float = 2.5             # Wie nah muss der Spieler sein
@export var requires_tool: String = ""                  # z.B. "axe", "pickaxe", "" = kein Tool nötig
@export var interaction_time: float = 0.0               # 0 = sofort, >0 = Fortschrittsbalken

var _is_busy: bool = false       # Wird gerade benutzt?
var _interacting_player: Node3D = null
var _progress_timer: float = 0.0

# Highlight wenn Spieler in Reichweite
var _in_range: bool = false
var _original_material: Material = null


func _ready() -> void:
	add_to_group("interactable")
	_setup_collision()


func _setup_collision() -> void:
	# Area3D für Nähe-Erkennung automatisch erstellen
	var area := Area3D.new()
	var col := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	col.shape = sphere
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _process(delta: float) -> void:
	if _is_busy and _interacting_player and interaction_time > 0.0:
		_progress_timer += delta
		if _progress_timer >= interaction_time:
			_progress_timer = 0.0
			_finish_interaction()


# ── Öffentliche API ────────────────────────────────────────────────────────

## Wird von Player.gd aufgerufen wenn der Spieler "Interagieren" drückt
func interact(player: Node3D) -> void:
	if _is_busy:
		emit_signal("interaction_failed", self, "Bereits in Benutzung")
		return

	if not _is_in_range(player):
		emit_signal("interaction_failed", self, "Zu weit entfernt")
		return

	if requires_tool != "" and not _player_has_tool(player, requires_tool):
		emit_signal("interaction_failed", self,
			"Benötigt: " + requires_tool)
		return

	_is_busy = true
	_interacting_player = player
	_progress_timer = 0.0
	emit_signal("interaction_started", self, player)

	if interaction_time <= 0.0:
		_finish_interaction()


func cancel_interaction() -> void:
	_is_busy = false
	_interacting_player = null
	_progress_timer = 0.0


func is_busy() -> bool:
	return _is_busy


func get_progress() -> float:
	if interaction_time <= 0.0:
		return 1.0
	return clamp(_progress_timer / interaction_time, 0.0, 1.0)


# ── Überschreiben in Unterklassen ──────────────────────────────────────────

## Wird aufgerufen wenn Interaktion abgeschlossen ist.
## Gibt Dictionary mit Ergebnis zurück z.B. {"item": "log_normal", "xp": 25}
func _on_interaction_complete() -> Dictionary:
	return {}


# ── Intern ────────────────────────────────────────────────────────────────
func _finish_interaction() -> void:
	var result: Dictionary = _on_interaction_complete()
	_is_busy = false
	emit_signal("interaction_completed", self, result)
	_interacting_player = null


func _is_in_range(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position) <= interaction_radius + 0.5


func _player_has_tool(player: Node3D, tool_name: String) -> bool:
	# Später via InventorySystem prüfen
	# Für jetzt: immer true damit man testen kann
	return true


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_in_range = true
		# Spieler informieren dass Interaktion möglich ist
		if body.has_method("show_interact_hint"):
			body.show_interact_hint(interaction_label)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_in_range = false
		cancel_interaction()
		if body.has_method("hide_interact_hint"):
			body.hide_interact_hint()
