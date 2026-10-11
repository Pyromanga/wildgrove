class_name EquipmentComponent extends BaseUIComponent

## EquipmentComponent — Baut den Equipment-Tab im Inventar-Panel.
## Verbindet EquipmentVisuals mit EquipmentUIController.

func build(hud: HUD, ctx: IUIContext) -> EquipmentUIController:
	var ctrl := EquipmentUIController.new()
	ctrl.setup(hud, ctx)
	return ctrl
