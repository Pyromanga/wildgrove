class_name GroundToolComponent extends BaseUIComponent

func build(hud: HUD, ctx: IUIContext) -> GroundToolController:
	var visuals := GroundToolVisuals.new(hud)
	var ctrl := GroundToolController.new()
	# BUGFIX (2026-09-20, "Grab-Symbol erscheint nie"): setup() MUSS vor
	# add_child() laufen. add_child() auf einen bereits im Tree stehenden
	# 'hud' löst _ready() SOFORT synchron aus (Godot 4) — lief das vorher, war
	# _ctx zu diesem Zeitpunkt noch null (setup() kam erst danach), also
	# brach GroundToolController._ready() mit "if not is_instance_valid(_ctx):
	# return" sofort ab. Weder der equipment_changed-Connect noch der initiale
	# _refresh()-Aufruf liefen dadurch je — das Werkzeug-Icon blieb permanent
	# unsichtbar, unabhängig davon ob/wann eine Schaufel ausgerüstet wurde.
	ctrl.setup(visuals, ctx)
	hud.add_child(ctrl)
	return ctrl
