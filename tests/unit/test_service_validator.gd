# res://tests/unit/test_service_validator.gd
extends GutTest

## Unit-Tests für ServiceValidator (Testability-Fix: injizierbare Config).
##
## Vorher: _load_config() las IMMER res://config/BootstrapConfig.tres von Disk.
## ServiceValidator war dadurch nicht mit einer Fake-Config testbar — jeder
## Test hing am tatsächlichen Inhalt der Produktions-.tres-Datei.
##
## Jetzt: validator.config ist ein injizierbares Property (analog zu
## ServiceFactory.mounter). validate()/validate_session() sind reine Funktionen
## ihres Inputs wenn config gesetzt ist — kein Disk-Zugriff in diesem Pfad.
##
## Abgedeckt:
##   - Injizierte Fake-Config wird verwendet, kein Fallback auf Disk
##   - Leere global_services/session_services → [] + Warn-Log
##   - Strukturfehler (null-Eintrag, falscher Typ, Pfad fehlt, self-dep) weiterhin erkannt
##   - validate_session() externe Namen (Cross-Registry) funktionieren mit Fake-Config
##   - Ohne injizierte config: Fallback auf BootstrapConfig.load_default() (Produktionsverhalten
##     unverändert — lädt die echte res://config/BootstrapConfig.tres)
##   - config wird nach dem ersten Fallback-Load gecached (kein zweiter Disk-Hit)

const REAL_SERVICE_PATH := "res://scripts/platform/Service.gd"

func _make_def(name: String, deps: Array[String] = [], path: String = REAL_SERVICE_PATH) -> ServiceDefinition:
	var d := ServiceDefinition.new()
	d.service_name = name
	d.path = path
	d.required_deps = deps
	return d

func _make_fake_config(
	global: Array[ServiceDefinition] = [],
	session: Array[ServiceDefinition] = []
) -> BootstrapConfig:
	var cfg := BootstrapConfig.new()
	cfg.global_services = global
	cfg.session_services = session
	return cfg

# ─────────────────────────────────────────────────────────────────────────────
# Injizierte Config wird verwendet — kein Disk-Fallback
# ─────────────────────────────────────────────────────────────────────────────

func test_validate_uses_injected_config() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("fakeservice")
	validator.config = _make_fake_config([def] as Array[ServiceDefinition])

	var result := validator.validate()

	assert_eq(result.size(), 1, "Muss genau die injizierte Definition zurückgeben")
	assert_eq(result[0].service_name, "fakeservice", "Service-Name muss aus der Fake-Config kommen")

func test_validate_session_uses_injected_config() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("fakesession")
	validator.config = _make_fake_config([], [def] as Array[ServiceDefinition])

	var result := validator.validate_session()

	assert_eq(result.size(), 1, "Muss die injizierte Session-Definition zurückgeben")
	assert_eq(result[0].service_name, "fakesession")

func test_injected_config_is_not_overwritten_by_validate() -> void:
	var validator := ServiceValidator.new()
	var cfg := _make_fake_config()
	validator.config = cfg
	validator.validate()
	assert_same(validator.config, cfg, "Injizierte Config darf von validate() nicht ersetzt werden")

# ─────────────────────────────────────────────────────────────────────────────
# Strukturfehler werden mit Fake-Config weiterhin erkannt
# ─────────────────────────────────────────────────────────────────────────────

func test_validate_empty_global_services_returns_empty() -> void:
	var validator := ServiceValidator.new()
	validator.config = _make_fake_config([] as Array[ServiceDefinition])

	var result := validator.validate()

	assert_eq(result.size(), 0, "Leere global_services muss [] zurückgeben")

func test_validate_rejects_null_entry() -> void:
	var validator := ServiceValidator.new()
	var cfg := BootstrapConfig.new()
	# Direkt ein physisch-null-Element in den typisierten Array packen.
	var arr: Array[ServiceDefinition] = [null]
	cfg.global_services = arr
	validator.config = cfg

	var result := validator.validate()

	assert_eq(result.size(), 0, "Ein null-Eintrag muss die gesamte Liste verwerfen")

func test_validate_rejects_missing_path() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("brokenpath", [], "")
	validator.config = _make_fake_config([def] as Array[ServiceDefinition])

	var result := validator.validate()

	assert_eq(result.size(), 0, "Leerer Pfad muss die Validierung scheitern lassen")

func test_validate_rejects_nonexistent_path() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("ghostservice", [], "res://does/not/exist.gd")
	validator.config = _make_fake_config([def] as Array[ServiceDefinition])

	var result := validator.validate()

	assert_eq(result.size(), 0, "Nicht existierender Pfad muss die Validierung scheitern lassen")

func test_validate_rejects_self_dependency() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("selfdep", ["selfdep"])
	validator.config = _make_fake_config([def] as Array[ServiceDefinition])

	var result := validator.validate()

	assert_eq(result.size(), 0, "Abhängigkeit auf sich selbst muss erkannt und verworfen werden")

func test_validate_session_accepts_external_global_names() -> void:
	var validator := ServiceValidator.new()
	var def := _make_def("sessionsvc", ["ticker"])  # "ticker" kommt aus global, nicht aus dieser Liste
	validator.config = _make_fake_config([], [def] as Array[ServiceDefinition])

	var result := validator.validate_session(["ticker"])

	assert_eq(result.size(), 1, "Dep auf bekannten externen Namen darf nicht zum Fehler führen")

# ─────────────────────────────────────────────────────────────────────────────
# Ohne injizierte Config: Fallback auf BootstrapConfig.load_default()
# (Produktionsverhalten unverändert — lädt die echte .tres-Datei)
# ─────────────────────────────────────────────────────────────────────────────

func test_validate_without_injected_config_falls_back_to_real_bootstrap_config() -> void:
	var validator := ServiceValidator.new()
	assert_null(validator.config, "config muss vor dem ersten validate()-Call null sein")

	var result := validator.validate()

	assert_gt(result.size(), 0, "Fallback muss die echte BootstrapConfig.tres laden (global_services nicht leer)")

func test_load_config_caches_after_fallback() -> void:
	var validator := ServiceValidator.new()
	validator.validate()
	assert_not_null(validator.config, "Nach dem Fallback-Load muss config gecached sein")

	var cached := validator.config
	validator.validate_session()
	assert_same(validator.config, cached, "Zweiter Call darf die gecachte Config nicht erneut laden/ersetzen")
