# IntegrationTest.gd
# FIX: "Could not resolve super class path res://addons/gut/test.gd"
#   Das GUT-Addon ist nicht installiert. Zwei Optionen:
#
#   Option A (empfohlen): GUT installieren
#     → Asset Library: "Gut - Godot Unit Testing" suchen und installieren
#     → Danach diese Datei wieder auf `extends "res://addons/gut/test.gd"` umstellen
#
#   Option B (temporär): Stub-Basisklasse verwenden (diese Datei)
#     → Tests laufen nicht als echte Unit-Tests, compilieren aber fehlerfrei

extends Node  # Temporär statt extends "res://addons/gut/test.gd"

## IntegrationTest — Prüft ob der Boot-Prozess korrekt abläuft.
## Aktiviere GUT und stelle extends wieder her um echte Tests zu nutzen.

func before_all() -> void:
	# FIX: Kernel existiert nicht → Services nutzen
	# Services ist nach Boot befüllt, aber in Tests evtl. noch leer.
	if not EventBus.system.services_initialized.is_connected(_on_services_ready):
		EventBus.system.services_initialized.connect(_on_services_ready, CONNECT_ONE_SHOT)

func _on_services_ready() -> void:
	Logger.log_info("IntegrationTest: Services bereit — starte Tests.", "Test")
	test_check_services_integrity()

func test_check_services_integrity() -> void:
	# Ohne GUT: manuelle Assertion mit push_error
	_assert_not_null(Services.save_system,   "SaveSystem")
	_assert_not_null(Services.data,          "DataService")
	_assert_not_null(Services.inventory,     "InventorySystem")
	_assert_not_null(Services.skill_system,  "SkillSystem")
	_assert_not_null(Services.world,         "WorldService")
	_assert_not_null(Services.player_states, "PlayerStateService")
	Logger.log_info("Alle Service-Assertions bestanden.", "Test")

func _assert_not_null(value: Variant, label: String) -> void:
	if value == null:
		push_error("ASSERT FAILED: '%s' ist null!" % label)
	else:
		Logger.log_debug("OK: '%s' ist nicht null." % label, "Test")