# res://scripts/platform/NodeMounter.gd
class_name NodeMounter extends RefCounted

## NodeMounter — Kapselt add_child() als injizierbaren Coupling-Punkt.
##
## Warum diese Klasse?
##   ServiceFactory musste bisher parent.add_child(instance) direkt aufrufen.
##   Das ist der einzige Coupling an den SceneTree innerhalb der Factory —
##   alles andere (load, instantiate, register) ist SceneTree-unabhängig.
##
##   Durch Injektion eines NodeMounters kann ServiceFactory in Unit-Tests
##   vollständig ohne SceneTree getestet werden:
##     - Produktion:  NodeMounter.new()  → echter add_child()-Call
##     - Tests:       NullNodeMounter.new() → kein add_child(), kein parent nötig
##
## API:
##   mount(node, parent) — hängt `node` als Kind in `parent` ein.
##
## Hinweis: Diese Klasse selbst ist trivial. Der Wert liegt in der
##   Substituierbarkeit — ein Mock-/Null-Mounter ersetzt sie im Test.

func mount(node: Node, parent: Node) -> void:
	parent.add_child(node)
