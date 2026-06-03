class_name GameSaveService extends ServiceNode

var _save_system: SaveSystem
var _providers: Array = []

func configure(deps: Dictionary) -> void:
    _save_system = deps.get("savesystem")
    # Registriere dich beim SaveSystem als "Master-Provider"
    _save_system.register_save_provider(self)

func collect_all_data() -> Dictionary:
    var final_data = {}
    for provider in _providers:
        final_data[provider.get_save_key()] = provider.get_save_data()
    return final_data