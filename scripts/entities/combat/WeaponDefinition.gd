extends ItemDefinition
class_name WeaponDefinition

## WeaponDefinition — Resource für Waffen-Items.
##
## Erbt id, display_name, icon, max_stack von ItemDefinition.
## Ergänzt Kampf-Attribute und Visual-Hints für WeaponVisual3D.
##
## Warum weapon_type als Enum statt String:
##   WeaponVisual3D und CombatSystem branchen darüber — typsicherer Enum
##   ist billiger als String-Vergleiche und fängt Tippfehler zur Ladezeit.
##
## on_hit_effect: optionale StatusEffect.Kind-Konstante (z.B. POISON).
##   -1 = kein Effekt. CombatSystem.player_melee_damage() liest diesen
##   Wert und ruft apply_poison()/apply_burn() wenn gesetzt.

enum WeaponType {
	DAGGER,
	SWORD,
	AXE,
	STAFF,
}

## Bonus-Schaden der auf den Basis-Schaden addiert wird (flat, vor Resistenz).
@export var damage_bonus: float = 0.0

## Schadens-Typ den diese Waffe verursacht.
@export var damage_type: int = 0   # DamageRecord.DamageType.PHYSICAL

## StatusEffect.Kind der beim Treffer ausgelöst wird. -1 = kein Effekt.
@export var on_hit_effect: int = -1

## Ticks + Schaden pro Tick für on_hit_effect (nur relevant wenn on_hit_effect >= 0).
@export var on_hit_ticks:        int   = 4
@export var on_hit_damage_per_tick: float = 3.0
@export var on_hit_tick_interval: float = 1.0

## Waffentyp — steuert Mesh-Größe in WeaponVisual3D und spätere Animations-Clips.
@export var weapon_type: WeaponType = WeaponType.SWORD

## Visueller Offset relativ zum hand_r-Bone (world-units).
## Wird in WeaponVisual3D.attach_to() übernommen.
@export var visual_offset:   Vector3 = Vector3(0.0, -0.15, 0.2)
@export var visual_rotation: Vector3 = Vector3(0.0, 0.0, 0.0)
