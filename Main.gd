extends Node
## Main.gd — Der zentrale Einstiegspunkt

func _ready() -> void:
	# 1. Systeme laden (Pfade fixen!)
	# Wir achten auf Kleinschreibung bei Skillsystem.gd
	_add_script_node(Node.new(), "res://scripts/Skillsystem.gd", "SkillSystem")
	_add_script_node(Node.new(), "res://scripts/InventorySystem.gd", "InventorySystem")

	# 2. Welt & Spieler laden
	_add_script_node(Node3D.new(), "res://scripts/World.gd", "World")
	
	# Player bekommt eine eigene Variable für spätere Setups
	var player = _add_script_node(CharacterBody3D.new(), "res://scripts/Player.gd", "Player")

	# 3. UI & Signale (deferred um Viewport-Errors zu vermeiden)
	call_deferred("_build_ui")
	call_deferred("_connect_signals")
	
	# Debug-Verbindung zum Bus
	var ge = get_node_or_null("/root/GameEvents")
	if ge:
		ge.debug_log.connect(_on_debug_log)
		ge.log("System-Bootstrap erfolgreich.")

func _build_ui() -> void:
	# TouchInput laden (Wichtig für Player-Bewegung!)
	_add_script_node(Node.new(), "res://scripts/TouchInput.gd", "TouchInput")

	var hud := CanvasLayer.new()
	hud.name = "HUD"
	hud.set_script(load("res://scripts/HUD.gd"))
	add_child(hud)

	var sett := CanvasLayer.new()
	sett.name = "Settings"
	sett.set_script(load("res://scripts/Settings.gd"))
	add_child(sett)

	# Brücke zwischen HUD und Settings
	if hud.has_signal("settings_requested"):
		hud.settings_requested.connect(sett.toggle)
	if sett.has_signal("ui_offset_changed"):
		sett.ui_offset_changed.connect(hud.apply_ui_offset)

func _connect_signals() -> void:
	# Skill-Signale über den Bus abfangen (Saubere Architektur!)
	var ge = get_node_or_null("/root/GameEvents")
	if ge:
		# Wenn das Skillsystem XP meldet, loggen wir es in der Main
		ge.xp_gained.connect(func(skill, amt): 
			_on_debug_log("+%d %s XP erhalten" % [amt, skill])
		)

func _on_debug_log(msg: String) -> void:
	print_rich("[color=cyan][Main][/color] ", msg)

# Hilfsfunktion zum dynamischen Laden
func _add_script_node(base_node: Node, script_path: String, node_name: String) -> Node:
	base_node.name = node_name
	if ResourceLoader.exists(script_path):
		base_node.set_script(load(script_path))
		add_child(base_node)
	else:
		# Wichtig für dich in der Pipeline: Fehlende Dateien sofort sehen!
		push_error("KRITISCH: Script nicht gefunden unter: " + script_path)
		add_child(base_node) # Node trotzdem laden um Abstürze zu vermeiden
	return base_node