extends CanvasLayer
class_name HUD

var _inventory_label: Label
var _interact_button: Button = null
var _context_button: Button = null
var _player: Player = null

func _ready() -> void:
    add_to_group("hud")
    _build_ui()
    Logger.log_debug("HUD bereit", "HUD")
    # Player suchen wir später, sobald die Szene vollständig ist
    call_deferred("_find_player")

func _build_ui() -> void:
    _inventory_label = Label.new()
    _inventory_label.name = "InventoryLabel"
    add_child(_inventory_label)

func setup_buttons(interact_btn: Button, context_btn: Button) -> void:
    _interact_button = interact_btn
    _context_button = context_btn

func _find_player() -> void:
    var players = get_tree().get_nodes_in_group("player")
    if players.size() > 0:
        _player = players[0] as Player

func _process(_delta: float) -> void:
    if not _interact_button or not _context_button:
        return
    # Falls Player noch nicht gefunden, erneut suchen
    if not _player:
        _find_player()
        if not _player:
            return

    var target = _player._get_closest_interactable()
    var has_target = target != null

    # Interact-Button aktivieren, wenn ein Ziel mit Default-Aktion existiert
    _interact_button.disabled = not has_target
    _context_button.disabled = not has_target

    # Style für disabled setzen (grau)
    if not has_target:
        var disabled_style = StyleBoxFlat.new()
        disabled_style.bg_color = Color(0.3, 0.3, 0.3, 0.5)
        disabled_style.set_corner_radius_all(40)
        _interact_button.add_theme_stylebox_override("disabled", disabled_style)
        _context_button.add_theme_stylebox_override("disabled", disabled_style)
    else:
        # Zurücksetzen auf den normalen Stil (wird von den ursprünglichen Overrides übernommen)
        _interact_button.remove_theme_stylebox_override("disabled")
        _context_button.remove_theme_stylebox_override("disabled")

func update_inventory_display(items: Array) -> void:
    var text = "Inventar:\n"
    for item in items:
        text += "- " + item["name"] + ": " + str(item["quantity"]) + "\n"
    _inventory_label.text = text