class_name InventorySystem extends ServiceNode

signal inventory_changed

var _items: Dictionary = {}
var _item_registry: Dictionary = {} # Hier laden wir die .tres Dateien rein

func init() -> void:
    # 1. Lade alle Item-Definitionen aus einem Ordner
    _load_item_database("res://data/items/")
    
    # 2. Lade hier dein Savegame (wie besprochen)
    var saved_data = Kernel.get_service("savesystem").get_state()
    _items = saved_data.get("inventory", {})

func _load_item_database(path: String) -> void:
    var dir = DirAccess.open(path)
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if file_name.ends_with(".tres"):
                var item = load(path + file_name) as ItemDefinition
                if item: _item_registry[item.id] = item
            file_name = dir.get_next()
    Logger.log_info("Item-DB geladen mit %d Einträgen." % _item_registry.size(), _log_cat())

func get_item_info(item_id: String) -> ItemDefinition:
    return _item_registry.get(item_id)