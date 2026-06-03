extends ServiceNode
class_name GameManager

var _current_state: GameEnums.State = GameEnums.State.BOOT
var _scene_manager: SceneManager

func configure(deps: Dictionary) -> void:
    _scene_manager = deps.get("scenemanager")
    # Der GameManager registriert sich nicht mehr selbst beim SaveSystem.
    # Ein GameSaveService übernimmt das.

func change_state(new_state: GameEnums.State) -> void:
    if new_state == _current_state: return
    
    # 1. Validierung über den ausgelagerten Validator
    if not StateValidator.is_transition_allowed(_current_state, new_state, config):
        return
        
    _current_state = new_state
    
    # 2. Szenenwechsel via SceneManager (der jetzt auch das Mapping kennt)
    if _scene_manager:
        _scene_manager.transition_to_state(_current_state)
    
    EventBus.system.emit_state_changed(_current_state)