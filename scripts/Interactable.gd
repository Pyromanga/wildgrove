extends Node3D
## Interactable.gd — Basis für alle interagierbaren Objekte

signal interaction_started(interactable: Node3D, player: Node3D)
signal interaction_completed(interactable: Node3D, result: Dictionary)
signal interaction_failed(interactable: Node3D, reason: String)

@export var interaction_label: String = "Interagieren"
@export var interaction_radius: float = 2.5
@export var requires_tool: String     = ""
@export var interaction_time: float   = 0.0

var _is_busy: bool        = false
var _interacting_player: Node3D = null
var _progress_timer: float = 0.0
var _progress_bar: ColorRect = null
var _progress_fill: ColorRect = null


func _ready() -> void:
	add_to_group("interactable")
	_setup_area()
	_setup_progress_bar()


func _setup_area() -> void:
	var area := Area3D.new()
	var col  := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	col.shape = sphere
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)


func _setup_progress_bar() -> void:
	if interaction_time <= 0.0:
		return
	# 3D Fortschrittsbalken über dem Objekt
	var bar_root := Node3D.new()
	bar_root.position = Vector3(0, 3.2, 0)

	# Hintergrund
	var bg := MeshInstance3D.new()
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(1.2, 0.12, 0.02)
	bg.mesh = bg_mesh
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.material_override = bg_mat
	bar_root.add_child(bg)

	# Füllung
	var fill := MeshInstance3D.new()
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.0, 0.10, 0.03)  # Breite = 0 am Anfang
	fill.mesh = fill_mesh
	fill.position.x = -0.6
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.2, 0.85, 0.3, 1)
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill.material_override = fill_mat
	bar_root.add_child(fill)
	bar_root.visible = false
	add_child(bar_root)


func _process(delta: float) -> void:
	if not _is_busy:
		return

	if interaction_time > 0.0:
		_progress_timer += delta
		_update_progress_bar(_progress_timer / interaction_time)

		if _progress_timer >= interaction_time:
			_progress_timer = 0.0
			_finish_interaction()


func _update_progress_bar(progress: float) -> void:
	# Node3D[0] = bg, Node3D[1] = fill
	var bar_root: Node = get_child(get_child_count() - 1)
	if not bar_root is Node3D:
		return
	bar_root.visible = true
	if bar_root.get_child_count() < 2:
		return
	var fill: MeshInstance3D = bar_root.get_child(1)
	var fill_mesh: BoxMesh = fill.mesh
	fill_mesh.size = Vector3(clamp(progress, 0.0, 1.0) * 1.2, 0.10, 0.03)
	fill.position.x = -0.6 + clamp(progress, 0.0, 1.0) * 0.6


func interact(player: Node3D) -> void:
	if _is_busy:
		emit_signal("interaction_failed", self, "Bereits aktiv")
		return

	if not _is_in_range(player):
		emit_signal("interaction_failed", self, "Zu weit entfernt")
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
	_hide_progress_bar()


func _finish_interaction() -> void:
	var result: Dictionary = _on_interaction_complete()
	_is_busy = false
	_hide_progress_bar()
	emit_signal("interaction_completed", self, result)
	_interacting_player = null


func _hide_progress_bar() -> void:
	var bar_root: Node = get_child(get_child_count() - 1)
	if bar_root is Node3D:
		bar_root.visible = false


func _on_interaction_complete() -> Dictionary:
	return {}


func _is_in_range(player: Node3D) -> bool:
	return global_position.distance_to(player.global_position) <= interaction_radius + 0.5


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		if body.has_method("show_interact_hint"):
			body.show_interact_hint(interaction_label)
		# HUD Interact-Button zeigen
		var huds: Array = body.get_tree().get_nodes_in_group("hud") if body.get_tree() else []
		# Direkt via Szenenbaum
		_show_hud_interact(body, interaction_label)


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		cancel_interaction()
		if body.has_method("hide_interact_hint"):
			body.hide_interact_hint()
		_hide_hud_interact(body)


func _show_hud_interact(player: Node3D, label: String) -> void:
	var canvas_layers: Array = player.get_tree().get_nodes_in_group("hud_layer")
	for cl in canvas_layers:
		if cl.has_method("show_interact_button"):
			cl.show_interact_button(label)
			return


func _hide_hud_interact(player: Node3D) -> void:
	var canvas_layers: Array = player.get_tree().get_nodes_in_group("hud_layer")
	for cl in canvas_layers:
		if cl.has_method("hide_interact_button"):
			cl.hide_interact_button()
			return
