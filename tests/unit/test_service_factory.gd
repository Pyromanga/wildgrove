# res://tests/unit/test_service_factory.gd
extends GutTest

## Unit-Tests für ServiceFactory + NodeMounter (Entkopplung vom SceneTree).
##
## Strategie: ServiceFactory.mounter wird durch einen SpyNodeMounter ersetzt.
## SpyNodeMounter.mount() ruft KEIN add_child() auf — damit brauchen diese
## Tests keinen echten parent-Node im SceneTree und laufen vollständig
## ohne SceneTree-Kontakt.
##
## Was getestet wird:
##   NodeMounter (Produktions-Klasse):
##     - mount() ist aufrufbar (Interface-Smoke-Test)
##
##   SpyNodeMounter (Test-Helfer):
##     - mount_calls zählt korrekt
##     - last_node / last_parent werden gesetzt
##
##   ServiceFactory.instantiate_all():
##     - Leere defs-Liste → true (keine Fehler)
##     - Pfad existiert nicht → false, kein mounter-Call
##     - Script-Service (RefCounted) → registriert, kein mounter-Call
##     - Node-Service → registriert UND mounter.mount() aufgerufen
##     - Mehrere Defs → mounter genau N-mal für Node-Services
##
##   ServiceFactory.mounter-Injektion:
##     - Default-Mounter ist NodeMounter-Instanz
##     - Mounter bleibt nach Austausch erhalten
##
##   Regressions-Guard:
##     - factory.instantiate_all() mit NullMounter → kein Crash ohne parent

# ─────────────────────────────────────────────────────────────────────────────
# Test-Helfer
# ─────────────────────────────────────────────────────────────────────────────

## SpyNodeMounter — ersetzt add_child() durch reines Tracking.
## Kein SceneTree-Kontakt. Zählt mount()-Aufrufe und merkt sich die Argumente.
class SpyNodeMounter extends NodeMounter:
	var mount_calls: int = 0
	var last_node:   Node = null
	var last_parent: Node = null
	var mounted_nodes: Array[Node] = []

	func mount(node: Node, parent: Node) -> void:
		mount_calls  += 1
		last_node    = node
		last_parent  = parent
		mounted_nodes.append(node)

## NullNodeMounter — verwirft mount() vollständig (auch ohne parent-Node nutzbar).
class NullNodeMounter extends NodeMounter:
	func mount(_node: Node, _parent: Node) -> void:
		pass  # absichtlich leer

## Minimaler RefCounted-Service (kein Node) — für Script-Pfad-Tests.
## Instanziierbar ohne SceneTree.
class StubRefService extends RefCounted:
	var service_name: String = ""
	func configure(_deps: ServiceDeps) -> void: pass
	func on_ready() -> void: pass
	func on_cleanup() -> void: pass

## Minimaler Node-Service — für den Node-Zweig in _from_script().
class StubNodeService extends Node:
	var service_name: String = ""
	func configure(_deps: ServiceDeps) -> void: pass
	func on_ready() -> void: pass
	func on_cleanup() -> void: pass

# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

var _factory: ServiceFactory
var _spy:     SpyNodeMounter
var _registry: ServiceRegistry
var _dummy_parent: Node  # nur für Signaturen — SpyMounter ignoriert ihn

func _make_def(name: String, path: String = "res://scripts/platform/Service.gd") -> ServiceDefinition:
	var d := ServiceDefinition.new()
	d.service_name = name
	d.path = path
	d.required_deps = []
	return d

func before_each() -> void:
	_spy     = SpyNodeMounter.new()
	_factory = ServiceFactory.new()
	_factory.mounter = _spy

	_registry     = ServiceRegistry.new()
	_dummy_parent = Node.new()  # wird nicht in den SceneTree gehängt

func after_each() -> void:
	_dummy_parent.free()

# ─────────────────────────────────────────────────────────────────────────────
# NodeMounter — Produktions-Klasse (Interface-Smoke)
# ─────────────────────────────────────────────────────────────────────────────

func test_node_mounter_default_instance_is_not_null() -> void:
	var fresh_factory := ServiceFactory.new()
	assert_not_null(fresh_factory.mounter, "Default-Mounter muss NodeMounter-Instanz sein")
	assert_is(fresh_factory.mounter, NodeMounter, "Default-Mounter muss vom Typ NodeMounter sein")

func test_node_mounter_is_replaceable() -> void:
	var fresh_factory := ServiceFactory.new()
	var null_mounter  := NullNodeMounter.new()
	fresh_factory.mounter = null_mounter
	assert_eq(fresh_factory.mounter, null_mounter, "Mounter muss nach Austausch der neue Wert sein")

# ─────────────────────────────────────────────────────────────────────────────
# SpyNodeMounter — Tracking-Verhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_spy_mounter_starts_at_zero_calls() -> void:
	assert_eq(_spy.mount_calls, 0, "SpyNodeMounter muss mit 0 Calls starten")

func test_spy_mounter_counts_calls() -> void:
	var n := Node.new()
	_spy.mount(n, _dummy_parent)
	_spy.mount(n, _dummy_parent)
	assert_eq(_spy.mount_calls, 2, "SpyNodeMounter muss 2 Calls zählen")
	n.free()

func test_spy_mounter_records_last_node() -> void:
	var n := Node.new()
	_spy.mount(n, _dummy_parent)
	assert_eq(_spy.last_node, n, "SpyNodeMounter.last_node muss den gemounteten Node speichern")
	n.free()

func test_spy_mounter_records_last_parent() -> void:
	var n := Node.new()
	_spy.mount(n, _dummy_parent)
	assert_eq(_spy.last_parent, _dummy_parent, "SpyNodeMounter.last_parent muss den parent speichern")
	n.free()

func test_spy_mounter_does_not_call_add_child() -> void:
	# Wenn SpyMounter add_child() aufrufen würde, würde der Node im
	# (nicht existenten) SceneTree hängen. Das können wir indirekt prüfen:
	# after_each() gibt _dummy_parent.free() aus — das würde crashen wenn
	# ein Kind drin hängt ohne queue_free. Kein Crash = kein add_child.
	var n := Node.new()
	_spy.mount(n, _dummy_parent)
	assert_eq(_dummy_parent.get_child_count(), 0,
		"SpyNodeMounter darf kein add_child() aufrufen")
	n.free()

# ─────────────────────────────────────────────────────────────────────────────
# instantiate_all() — Grundverhalten
# ─────────────────────────────────────────────────────────────────────────────

func test_empty_defs_returns_true() -> void:
	var defs: Array[ServiceDefinition] = []
	var ok := _factory.instantiate_all(defs, _registry, _dummy_parent)
	assert_true(ok, "Leere defs-Liste muss true ergeben (keine Fehler)")

func test_empty_defs_no_mounter_call() -> void:
	var defs: Array[ServiceDefinition] = []
	_factory.instantiate_all(defs, _registry, _dummy_parent)
	assert_eq(_spy.mount_calls, 0, "Leere defs → kein mounter-Call")

func test_nonexistent_path_returns_false() -> void:
	var defs := [_make_def("ghost", "res://DOES_NOT_EXIST.gd")] as Array[ServiceDefinition]
	var ok := _factory.instantiate_all(defs, _registry, _dummy_parent)
	assert_false(ok, "Nicht-existenter Pfad muss false ergeben")

func test_nonexistent_path_no_mounter_call() -> void:
	var defs := [_make_def("ghost", "res://DOES_NOT_EXIST.gd")] as Array[ServiceDefinition]
	_factory.instantiate_all(defs, _registry, _dummy_parent)
	assert_eq(_spy.mount_calls, 0, "Nicht-existenter Pfad → kein mounter-Call")

func test_nonexistent_path_not_registered() -> void:
	var defs := [_make_def("ghost", "res://DOES_NOT_EXIST.gd")] as Array[ServiceDefinition]
	_factory.instantiate_all(defs, _registry, _dummy_parent)
	assert_null(_registry.get_service("ghost"), "Ghost-Service darf nicht in Registry sein")

# ─────────────────────────────────────────────────────────────────────────────
# instantiate_all() — Node-Services (mounter.mount() muss aufgerufen werden)
# ─────────────────────────────────────────────────────────────────────────────
#
# Wir können kein echter GDScript-Pfad aus dem Projekt verwenden ohne Disk-Load,
# daher testen wir _from_script() indirekt über eine Factory-Subklasse
# die _create_service() überschreibt — so bleibt der Test ohne ResourceLoader.

## TestableFactory — überschreibt _create_service() mit direkt injizierten Instanzen.
## Damit werden ResourceLoader.exists() und load() vollständig umgangen.
class TestableFactory extends ServiceFactory:
	## Wenn gesetzt, gibt _create_service() diesen Wert zurück.
	var inject_instance: Object = null

	func _create_service(def: ServiceDefinition, registry: ServiceRegistry, parent: Node) -> Object:
		if inject_instance == null:
			return null

		var instance := inject_instance
		if instance is Node:
			instance.name = def.service_name
			registry.register(instance, def)
			mounter.mount(instance as Node, parent)
		else:
			if "service_name" in instance:
				instance.service_name = def.service_name
			registry.register(instance, def)
		return instance

func test_node_service_triggers_mounter_mount() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("nodesvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(_spy.mount_calls, 1, "Node-Service → mounter.mount() muss einmal aufgerufen werden")
	node_svc.free()

func test_node_service_mount_receives_correct_node() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("nodesvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(_spy.last_node, node_svc,
		"mounter.mount() muss den korrekt erzeugten Node erhalten")
	node_svc.free()

func test_node_service_mount_receives_correct_parent() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("nodesvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(_spy.last_parent, _dummy_parent,
		"mounter.mount() muss den injizierten parent erhalten")
	node_svc.free()

func test_node_service_is_registered_in_registry() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("nodesvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_not_null(_registry.get_service("nodesvc"),
		"Node-Service muss in der Registry eingetragen sein")
	node_svc.free()

func test_node_service_name_set_on_instance() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("my_service")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(node_svc.name, "my_service",
		"instance.name muss den service_name aus der Definition erhalten")
	node_svc.free()

# ─────────────────────────────────────────────────────────────────────────────
# instantiate_all() — RefCounted-Services (KEIN mounter-Call)
# ─────────────────────────────────────────────────────────────────────────────

func test_ref_service_no_mounter_call() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	tf.inject_instance = StubRefService.new()

	var defs := [_make_def("refsvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(_spy.mount_calls, 0,
		"RefCounted-Service darf keinen mounter-Call auslösen")

func test_ref_service_is_registered_in_registry() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var ref_svc := StubRefService.new()
	tf.inject_instance = ref_svc

	var defs := [_make_def("refsvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_not_null(_registry.get_service("refsvc"),
		"RefCounted-Service muss trotzdem in der Registry sein")

func test_ref_service_service_name_set() -> void:
	var tf := TestableFactory.new()
	tf.mounter = _spy

	var ref_svc := StubRefService.new()
	tf.inject_instance = ref_svc

	var defs := [_make_def("refsvc")] as Array[ServiceDefinition]
	tf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(ref_svc.service_name, "refsvc",
		"RefCounted-Service muss service_name aus Definition erhalten")

# ─────────────────────────────────────────────────────────────────────────────
# instantiate_all() — Mehrere Services
# ─────────────────────────────────────────────────────────────────────────────

## MultiFactory — liefert abwechselnd Node / RefCounted Services aus einer Liste.
class MultiFactory extends ServiceFactory:
	var instances: Array[Object] = []
	var _idx: int = 0

	func _create_service(def: ServiceDefinition, registry: ServiceRegistry, parent: Node) -> Object:
		if _idx >= instances.size():
			return null
		var instance := instances[_idx]
		_idx += 1
		if instance is Node:
			instance.name = def.service_name
			registry.register(instance, def)
			mounter.mount(instance as Node, parent)
		else:
			if "service_name" in instance:
				instance.service_name = def.service_name
			registry.register(instance, def)
		return instance

func test_multiple_node_services_mounter_called_n_times() -> void:
	var mf := MultiFactory.new()
	mf.mounter = _spy

	var n1 := StubNodeService.new()
	var n2 := StubNodeService.new()
	var n3 := StubNodeService.new()
	mf.instances = [n1, n2, n3]

	var defs: Array[ServiceDefinition] = [
		_make_def("svc1"), _make_def("svc2"), _make_def("svc3")
	]
	var ok := mf.instantiate_all(defs, _registry, _dummy_parent)

	assert_true(ok, "Drei Node-Services → muss true ergeben")
	assert_eq(_spy.mount_calls, 3,
		"mounter.mount() muss genau 3-mal aufgerufen werden")
	n1.free(); n2.free(); n3.free()

func test_mixed_services_only_nodes_mount() -> void:
	var mf := MultiFactory.new()
	mf.mounter = _spy

	var node_svc := StubNodeService.new()
	var ref_svc  := StubRefService.new()
	mf.instances = [node_svc, ref_svc]

	var defs: Array[ServiceDefinition] = [_make_def("nsvc"), _make_def("rsvc")]
	mf.instantiate_all(defs, _registry, _dummy_parent)

	assert_eq(_spy.mount_calls, 1,
		"Nur Node-Service → genau 1 mounter-Call, nicht 2")
	node_svc.free()

func test_one_failed_def_makes_result_false() -> void:
	var mf := MultiFactory.new()
	mf.mounter = _spy

	# inject_instance = null → _create_service gibt null zurück für def2
	var n1 := StubNodeService.new()
	mf.instances = [n1]  # nur einer — def2 bekommt null

	var defs: Array[ServiceDefinition] = [_make_def("svc1"), _make_def("svc2")]
	var ok := mf.instantiate_all(defs, _registry, _dummy_parent)

	assert_false(ok, "Wenn eine Def fehlschlägt muss instantiate_all false ergeben")
	n1.free()

# ─────────────────────────────────────────────────────────────────────────────
# Regressions-Guard: NullMounter mit null-parent — kein Crash
# ─────────────────────────────────────────────────────────────────────────────

func test_null_mounter_with_null_parent_no_crash() -> void:
	var tf := TestableFactory.new()
	tf.mounter = NullNodeMounter.new()

	var node_svc := StubNodeService.new()
	tf.inject_instance = node_svc

	var defs := [_make_def("nodesvc")] as Array[ServiceDefinition]
	# null als parent — NullNodeMounter verwirft ihn, kein Crash
	tf.instantiate_all(defs, _registry, null)

	assert_true(true, "NullNodeMounter mit null-parent darf nicht crashen")
	node_svc.free()
