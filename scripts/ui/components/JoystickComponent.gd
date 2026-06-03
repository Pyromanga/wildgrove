# scripts/ui/components/joystick_component.gd
class_name JoystickComponent extends BaseUIComponent

func build(hud: HUD) -> JoystickController:
    var visuals = JoystickVisuals.new(hud)
        var ctrl = JoystickController.new()
            
                # NEU: Nutzt den globalen EventBus statt Kernel
                    ctrl.setup(visuals, EventBus.ui) 
                        return ctrl

                        # scripts/ui/components/interaction_button_component.gd
                        class_name InteractionButtonComponent extends BaseUIComponent

                        func build(hud: HUD) -> InteractionButtonController:
                            var pos = LayoutManager.get_action_button_position(0)
                                var visuals = InteractionButtonVisuals.new(hud, pos)
                                    var ctrl = InteractionButtonController.new()
                                        
                                            # WICHTIG: Der Player muss hier übergeben werden, 
                                                # da der Controller ihn im setup() erwartet!
                                                    var player = hud.get_tree().get_first_node_in_group("player")
                                                        ctrl.setup(visuals, player)
                                                            
                                                                return ctrl