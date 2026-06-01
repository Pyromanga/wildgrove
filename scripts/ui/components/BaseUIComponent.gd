# scripts/ui/components/BaseUIComponent.gd
class_name BaseUIComponent extends RefCounted

func build(_hud: HUD) -> Object:
    assert(false, "build() muss in der Subklasse implementiert werden")
    return null