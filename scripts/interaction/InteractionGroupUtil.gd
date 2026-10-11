class_name InteractionGroupUtil

## InteractionGroupUtil — einzige Stelle, die weiß, wie man von einem rohen
## Collider/Area-Treffer (Physics-Body, Area3D, RayCast-Hit) zur eigentlichen
## Entity in der Gruppe "interactable" hochläuft.
##
## Vorher lebte diese Ancestor-Walk-Logik NUR in InteractionSensor.get_closest()
## (Kommentar dort: "Node-Hierarchie bei OakTree/IronOre ... 4 Ebenen hoch
## durchsuchen"). InteractionTargetPicker (Tap-Raycast, siehe dort) braucht
## exakt dieselbe Auflösung für RayCast-Treffer — Kopieren hätte zwei Stellen
## geschaffen, die bei einer künftigen Tiefenänderung (z.B. 5. Verschachtelungs-
## Ebene) auseinanderlaufen können. Reine Funktion, kein State.

const MAX_ANCESTOR_DEPTH := 4

## Läuft von `node` aus bis zu `max_depth` Ebenen nach oben und gibt den ersten
## Vorfahren zurück, der in der Gruppe "interactable" ist — oder null.
## `stop_at`: Abbruch-Node (i.d.R. der eigene Spieler), falls die Kette dort
## endet, ohne dass ein Interactable gefunden wurde (verhindert, dass der
## Spieler sich selbst als Ziel findet, siehe InteractionSensor.get_closest()).
static func resolve_interactable(
	node: Node, stop_at: Node = null, max_depth: int = MAX_ANCESTOR_DEPTH
) -> Node3D:
	var current: Node = node
	var depth := 0
	while is_instance_valid(current) and depth < max_depth:
		if current == stop_at:
			return null
		if current is Node3D and current.is_in_group("interactable"):
			return current as Node3D
		current = current.get_parent()
		depth += 1
	return null
