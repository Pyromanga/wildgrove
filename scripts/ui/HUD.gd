extends CanvasLayer
class_name HUD

var _inventory_label: Label
var _interact_button: Button = null
var _context_button: Button = null
var _player: Node = null   # Node statt Player, vermeidet Typ-Fehler

func _ready() -> void:
    add_to_group("hud")
    _build_ui()
    Logger.log_debug("HUD bereit", "HUD")
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
        _player = players[0]

func _process(_delta: float) -> void:
    if not _interact_button or not _context_button:
        return
    if not _player:
        _find_player()
        if not _player:
            return

    var target: Node = null
    if _player.has_method("_get_closest_interactable"):
        target = _player._get_closest_interactable()

    var has_target = target != null

    # Buttons nur deaktivieren, wenn kein Ziel – so bleiben sie immer klickbar
    _interact_button.disabled = not has_target
    _context_button.disabled = not has_target

func update_inventory_display(items: Array) -> void:
    var text = "Inventar:\n"
    for item in items:
        text += "- " + item["name"] + ": " + str(item["quantity"]) + "\n"
    _inventory_label.text = text