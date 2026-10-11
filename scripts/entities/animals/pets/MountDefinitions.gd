class_name MountDefinitions

## MountDefinitions — welche gezähmten Tierarten als Reittier taugen und wie schnell sie machen.
##
## Wunsch "Pferd und Mount hinzufügen, auf denen man reiten kann (schneller als natürliches
## Laufen)". Reiten baut auf dem bestehenden Fangen auf: ein gefangenes Pferd/Esel ist ein Pet
## (PetComponent) mit species_id; ist die Art hier eingetragen, lässt es sich besteigen.
##
## speed_mult:   Faktor auf die effektive Lauf-Geschwindigkeit des Reiters (> 1 = schneller).
## seat_height:  Meter, um die der Reiter über dem Boden sitzt (Visual-Offset, keine Physik).
## follow_speed: Tempo des Tieres, wenn es frei hinter dem Besitzer herläuft.
## label:        Anzeigename für die HUD-Schaltfläche.

const MOUNT_RANGE: float = 4.0

const DEFINITIONS: Dictionary = {
	"horse":  {"label": "Pferd", "speed_mult": 1.9, "seat_height": 0.85, "follow_speed": 9.0},
	"donkey": {"label": "Esel",  "speed_mult": 1.4, "seat_height": 0.60, "follow_speed": 7.5},
}

static func is_mountable(species_id: String) -> bool:
	return DEFINITIONS.has(species_id)

static func label_for(species_id: String) -> String:
	return String((DEFINITIONS.get(species_id, {}) as Dictionary).get("label", ""))

## Geschwindigkeitsfaktor; unbekannte Art → 1.0 (kein Effekt, kein Crash).
static func speed_mult_for(species_id: String) -> float:
	return float((DEFINITIONS.get(species_id, {}) as Dictionary).get("speed_mult", 1.0))

static func seat_height_for(species_id: String) -> float:
	return float((DEFINITIONS.get(species_id, {}) as Dictionary).get("seat_height", 0.0))

static func follow_speed_for(species_id: String) -> float:
	return float((DEFINITIONS.get(species_id, {}) as Dictionary).get("follow_speed", 0.0))
