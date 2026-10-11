## tests/unit/test_health_component_max_health_contract.gd
## Spezifikation für den HealthComponent.max_health-Kontrakt
## (Fix 2026-09-25, siehe TODO-offene-probleme.md und
## scripts/agent/health_contract_check.py für die Godot-freie
## Verhaltens-Simulation desselben Kontrakts).
##
## VORHER: der Setter hat current_health bei JEDEM Setzen von max_health auf
## den neuen Wert synchronisiert — im Widerspruch zum eigenen Klassenkommentar
## ("Sync current mit max beim ERSTEN Setzen"). Jede spätere max_health-
## Änderung an einer bereits laufenden Komponente (Buff, Admin-Befehl,
## künftiges Level-Up-System) hat das aktuelle Leben also stillschweigend
## auf das neue Maximum gesetzt/geheilt.
##
## NACHHER: is_node_ready() unterscheidet "erstes Setzen" (vor add_child(),
## Konstruktions-Pattern von PlayerSetup/EnemyNPC) von "Live-Änderung"
## (Komponente bereits im Baum). Live-Änderungen klemmen current nur noch
## nach unten, heilen aber nie implizit.
##
## Hinweis (siehe Makefile "test-gd"-Target): kein GUT/gdUnit4-Runner in
## dieser Sandbox installiert — diese Datei ist lauffähige Spezifikation,
## aber aktuell nicht automatisiert ausführbar. Bis dahin ist
## scripts/agent/health_contract_check.py die tatsächlich lauffähige,
## Godot-freie Verifikation derselben Kontraktlogik.

extends GutTest

var _hc: HealthComponent

func before_each() -> void:
	_hc = HealthComponent.new()

func after_each() -> void:
	_hc.free()
	_hc = null

# ─────────────────────────────────────────────
# Erstes Setzen (Konstruktion, vor add_child()/_ready())
# ─────────────────────────────────────────────

func test_first_set_before_ready_syncs_current() -> void:
	# Konstruktions-Pattern von PlayerSetup._build_health()/
	# EnemyNPC._setup_health(): max_health VOR add_child() setzen.
	_hc.max_health = 30
	assert_eq(_hc.current_health, 30, "Erstes Setzen (vor _ready()) muss current mitziehen.")

func test_ready_safety_net_syncs_current() -> void:
	_hc.max_health = 80
	add_child_autofree(_hc)  # löst _ready() aus
	assert_eq(_hc.current_health, 80)

# ─────────────────────────────────────────────
# Live-Änderung (nach _ready(), Komponente bereits "im Spiel")
# ─────────────────────────────────────────────

func test_live_increase_does_not_heal() -> void:
	_hc.max_health = 50
	add_child_autofree(_hc)  # jetzt "ready"
	_hc.take_damage(30)  # 20/50
	_hc.max_health = 80  # Buff/Admin-Befehl: 50 -> 80
	assert_eq(_hc.current_health, 20, "Ein reiner Max-Anstieg darf current NICHT implizit heilen (der eigentliche Bugfix).")
	assert_eq(_hc.max_health, 80)

func test_live_decrease_clamps_current_down() -> void:
	_hc.max_health = 50
	add_child_autofree(_hc)
	_hc.take_damage(10)  # 40/50
	_hc.max_health = 20  # Debuff/Admin-Befehl: 50 -> 20
	assert_eq(_hc.current_health, 20, "current muss auf das neue (kleinere) Maximum geklemmt werden.")

func test_live_decrease_above_current_leaves_current_untouched() -> void:
	_hc.max_health = 50
	add_child_autofree(_hc)
	_hc.take_damage(40)  # 10/50
	_hc.max_health = 30  # weiterhin > current(10)
	assert_eq(_hc.current_health, 10)

func test_explicit_reset_still_fully_heals() -> void:
	# reset() bleibt der bewusste, explizite Weg für "voll heilen auf neues
	# Maximum" — z.B. EnemyNPC-Pool-Reuse nutzt genau diese Kombination.
	_hc.max_health = 50
	add_child_autofree(_hc)
	_hc.take_damage(45)  # 5/50
	_hc.max_health = 80
	assert_eq(_hc.current_health, 5)
	_hc.reset()
	assert_eq(_hc.current_health, 80)

func test_pool_reuse_pattern_matches_enemy_npc() -> void:
	# Nachbildung von EnemyNPC.gd Zeile ~487: max_health setzen + sofort
	# reset() aufrufen -> immer voll geheilt, unabhängig vom
	# is_node_ready()-Zustand.
	_hc.max_health = 40
	add_child_autofree(_hc)
	_hc.take_damage(35)  # 5/40
	_hc.max_health = 40
	_hc.reset()
	assert_eq(_hc.current_health, 40)
