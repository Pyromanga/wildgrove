extends RefCounted
class_name InteractionUIController

const LOG_CAT := "UI/Interaction"

var bar: ProgressBar

func setup(hud: CanvasLayer) -> void:
    Logger.log_debug("Initialisiere InteractionUIController...", LOG_CAT)
    
    # 1. Bar bauen (Visuals)
    bar = ProgressBar.new()
    bar.custom_minimum_size = Vector2(250, 24)
    bar.show_percentage = false
    bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
    bar.offset_top = 100
    bar.visible = false
    bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    
    # Style (kannst du aus UIFactory hierher verschieben)
    var sb_bg = StyleBoxFlat.new()
    sb_bg.bg_color = Color(0, 0, 0, 0.6)
    sb_bg.set_corner_radius_all(4)
    var sb_fg = StyleBoxFlat.new()
    sb_fg.bg_color = Color(0.2, 0.8, 0.3)
    sb_fg.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", sb_bg)
    bar.add_theme_stylebox_override("fill", sb_fg)
    
    hud.add_child(bar)
    
    # 2. Events verbinden
    Kernel.events.world.interaction_started.connect(_on_started)
    Kernel.events.world.interaction_finished.connect(_on_finished)
    Kernel.events.world.interaction_cancelled.connect(_on_cancelled)
    
    Logger.log_debug("InteractionUIController bereit.", LOG_CAT)

func _on_started(label: String, duration: float) -> void:
    Logger.log_debug("Interaktion gestartet: %s (%.1fs)" % [label, duration], LOG_CAT)
    bar.value = 0
    bar.visible = true
    var tween = bar.create_tween()
    tween.tween_property(bar, "value", 100.0, duration)

func _on_finished(_label: String) -> void:
    Logger.log_debug("Interaktion abgeschlossen.", LOG_CAT)
    bar.visible = false

func _on_cancelled(_label: String) -> void:
    Logger.log_warn("Interaktion abgebrochen.", LOG_CAT)
    bar.visible = false
    
func create_progress_bar(width: float = 250.0) -> ProgressBar:
    var bar := ProgressBar.new()
    bar.custom_minimum_size = Vector2(width, 24)
    bar.show_percentage = false
    var sb_bg := StyleBoxFlat.new()
    sb_bg.bg_color = COLOR_BG
    sb_bg.set_corner_radius_all(4)
    var sb_fg := StyleBoxFlat.new()
    sb_fg.bg_color = COLOR_ACCENT
    sb_fg.set_corner_radius_all(4)
    bar.add_theme_stylebox_override("background", sb_bg)
    bar.add_theme_stylebox_override("fill", sb_fg)
    return bar