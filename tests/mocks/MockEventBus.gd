# res://tests/mocks/MockEventBus.gd
class_name MockEventBus extends IEventBus

## MockEventBus — Test-Double für IEventBus.
##
## Hält lokale Instanzen aller Event-Namespaces.
## Jeder Test bekommt eine frische MockEventBus-Instanz in before_each() —
## kein globales State-Bleeding zwischen Tests, kein laufender AutoLoad nötig.
##
## VERWENDUNG in Tests:
##   var _bus: MockEventBus
##   var _svc: QuestService
##
##   func before_each():
##       _bus = MockEventBus.new()
##       _svc = QuestService.new()
##       _svc.configure(ServiceDeps.from_dict({
##           ServiceKeys.SAVE_SYSTEM: _stub_save,
##           ServiceKeys.EVENT_BUS:   _bus,
##       }))
##       _svc.on_ready()
##
##   func test_quest_started_signal_emitted():
##       watch_signals(_bus.quest())
##       _svc.request_start_quest("quest_intro")
##       assert_signal_emitted(_bus.quest(), "quest_started")

var _player: PlayerEvents
var _world:  WorldEvents
var _system: SystemEvents
var _ui:     UIEvents
var _quest:  QuestEvents
var _persistence: PersistenceEvents
var _session:     SessionEvents
var _networking:  NetworkingEvents
var _zones:       ZoneEvents
var _combat:      CombatEvents
var _bank:        BankEvents
var _auction:     AuctionEvents
var _trade:       TradeEvents
var _shop:        ShopEvents
var _smithing:    SmithingEvents

func _init() -> void:
	_player = PlayerEvents.new()
	_world  = WorldEvents.new()
	_system = SystemEvents.new()
	_ui     = UIEvents.new()
	_quest  = QuestEvents.new()
	_persistence = PersistenceEvents.new()
	_session     = SessionEvents.new()
	_networking  = NetworkingEvents.new()
	_zones       = ZoneEvents.new()
	_combat      = CombatEvents.new()
	_bank        = BankEvents.new()
	_auction     = AuctionEvents.new()
	_trade       = TradeEvents.new()
	_shop        = ShopEvents.new()
	_smithing    = SmithingEvents.new()

func player() -> PlayerEvents: return _player
func world()  -> WorldEvents:  return _world
func system() -> SystemEvents: return _system
func ui()     -> UIEvents:     return _ui
func quest()  -> QuestEvents:  return _quest
func persistence() -> PersistenceEvents: return _persistence
func session()      -> SessionEvents:     return _session
func networking()   -> NetworkingEvents:  return _networking
func zones()         -> ZoneEvents:       return _zones
func combat()         -> CombatEvents:    return _combat
func bank()           -> BankEvents:      return _bank
func auction()        -> AuctionEvents:   return _auction
func trade()          -> TradeEvents:     return _trade
func shop()           -> ShopEvents:      return _shop
func smithing()       -> SmithingEvents:  return _smithing
