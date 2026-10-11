class_name MenuScopeInitializer extends Node

## MenuScopeInitializer — Sitzt in MainMenu.tscn als Child-Node.
##
## Einzige Verantwortung: signalisiert wenn der MainMenu-Root bereit ist.
## Kein AutoLoad-Zugriff. Kein EventBus. Kein Pull.
##
## ServiceOrchestrator lauscht dauerhaft auf 'menu_ready' (siehe
## _watch_for_menu_initializer()) — anders als beim World-Pendant, das nur
## einmal pro Session gebootet wird, wird MainMenu.tscn bei jedem
## 'main_menu_requested' (Rückkehr ins Hauptmenü) komplett neu geladen, also
## erzeugt jeder Ladevorgang eine neue MenuScopeInitializer-Instanz.
##
## Push-Pattern: dieser Node pushed Existenz nach oben, niemand pollt ihn.
## Schließt BUG-21: MainMenuController.inject_save_system() existierte als
## DI-Punkt, hatte aber nie einen Aufrufer.

## Emittiert einmalig wenn dieser Node im SceneTree bereit ist.
## get_parent() ist zu diesem Zeitpunkt der MainMenu-Root (Control).
signal menu_ready(menu_root: Control)

func _ready() -> void:
	var root := get_parent()
	if not root is Control:
		push_error(
			"MenuScopeInitializer: Parent ist kein Control — in MainMenu.tscn direkt unter Root einsetzen."
		)
		return
	# BUG-FIX (analog WorldScopeInitializer._emit_world_ready(), Round 55):
	# synchrones emit() in _ready() ist NICHT garantiert nach dem Connect in
	# ServiceOrchestrator._on_node_added_check_menu() — insbesondere beim
	# allerersten Laden von run/main_scene folgt die Engine hier einem
	# anderen Timing als bei einem normalen Laufzeit-add_child(). Ohne Fix
	# verhallt menu_ready(), niemand hört zu, IAppContext/SaveSystem/
	# SessionManager werden nie injiziert (sichtbar als dauerhaftes "Kein
	# IAppContext injiziert" bei jedem Button-Klick, nicht nur transient).
	# call_deferred garantiert: der node_added-Listener ist zu diesem
	# Zeitpunkt in jedem Fall schon verbunden.
	call_deferred("_emit_menu_ready", root as Control)

func _emit_menu_ready(root: Control) -> void:
	menu_ready.emit(root)
	## Nach emit ist dieser Node fertig. Er bleibt im SceneTree für die Lebensdauer
	## des MainMenu-Screens, hat aber keine weitere aktive Rolle.
