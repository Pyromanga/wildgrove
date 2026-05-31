extends ServiceBase
class_name UIFactory

const COLOR_BG = Color(0, 0, 0, 0.6)
const COLOR_ACCENT = Color(0.2, 0.8, 0.3)

func show_context_menu(actions: Array) -> void:
    var hud_nodes = get_tree().get_nodes_in_group("hud")
    if hud_nodes.is_empty():
        Logger.log_error("Kein HUD für Kontextmenü gefunden!", "UIFactory")
        return
        
    ContextMenuController.new().show(hud_nodes[0], actions)

func show_popup(text: String) -> void:
    var hud_nodes = get_tree().get_nodes_in_group("hud")
    if hud_nodes.is_empty(): return
    
    NotificationController.new().show(hud_nodes[0], text)

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

func create_label_box(text: String) -> PanelContainer:
    var pc := PanelContainer.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = COLOR_BG
    sb.set_content_margin_all(10)
    sb.set_corner_radius_all(6)
    pc.add_theme_stylebox_override("panel", sb)
    var lbl := Label.new()
    lbl.text = text
    lbl.add_theme_font_size_override("font_size", 18)
    pc.add_child(lbl)
    return pc

func create_button(text: String, callback: Callable) -> Button:
    var btn := Button.new()
    btn.text = text
    btn.custom_minimum_size = Vector2(150, 40)
    btn.pressed.connect(callback)
    return btn
    
func setup_inventory_controller(hud: HUD) -> void:
    var controller = InventoryUIController.new()
    controller.setup(hud, Kernel.inventory)
    

func setup_interaction_ui(hud: HUD) -> void:
    var controller = InteractionUIController.new()
    controller.setup(hud)

func setup_joystick(hud: HUD) -> void:
    var players = hud.get_tree().get_nodes_in_group("player")
    if players.is_empty(): return
    
    var controller = JoystickController.new()
    controller.setup(hud, players[0])