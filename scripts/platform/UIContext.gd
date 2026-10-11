# res://scripts/platform/UIContext.gd
class_name UIContext extends IUIContext

## UIContext — Produktions-Implementierung von IUIContext.
##
## Wird von HUDBuilder.build_all() erstellt und an alle Controller injiziert.

var _quest:        QuestService    = null
var _skill_system: SkillSystem     = null
var _inventory:    InventorySystem = null
var _equipment:    EquipmentService = null
var _currency:     CurrencyService  = null
var _shop:         ShopService      = null
var _smithing:     SmithingService  = null
var _bank:         BankService      = null
var _trade:         TradeService        = null
var _auction_house: AuctionHouseService = null
var _item_protection: ItemProtectionService = null
var _data:         DataService      = null
var _settings:     SettingsService  = null
var _achievement:  AchievementService = null
var _character_creation: CharacterCreationService = null
var _wiki:          WikiService      = null
var _bus:          IEventBus        = null
var _world:        WorldService     = null

## ADR-015: peer_id DIESES laufenden Prozesses. Aufgelöst über SessionManager,
## nicht über multiplayer.get_unique_id() direkt (siehe IUIContext.get_local_peer_id()).
var _local_peer_id: int = 1

## ADR-029 Plan-Schritt 4: stabile player_id (String) DIESES laufenden
## Prozesses — siehe IUIContext.get_local_player_id().
var _local_player_id: String = ""

## Canonical DI-Pfad — nutzt ServiceRegistry statt AutoLoad.
## HUDManager.set_ui_context_factory() setzt eine Callable die diese Methode aufruft.
## I-02: löst IEventBus aus demselben Registry-Key wie Services (ServiceKeys.EVENT_BUS) —
## identischer EventBusAdapter, keine zweite Produktions-Implementierung.
static func from_registry(registry: ServiceRegistry) -> UIContext:
	var ctx        := UIContext.new()
	ctx._quest        = registry.get_service(ServiceKeys.QUEST)        as QuestService
	ctx._skill_system = registry.get_service(ServiceKeys.SKILL_SYSTEM) as SkillSystem
	ctx._inventory    = registry.get_service(ServiceKeys.INVENTORY)    as InventorySystem
	ctx._equipment    = registry.get_service(ServiceKeys.EQUIPMENT)    as EquipmentService
	ctx._currency     = registry.get_service(ServiceKeys.CURRENCY)     as CurrencyService
	ctx._shop         = registry.get_service(ServiceKeys.SHOP)         as ShopService
	ctx._smithing     = registry.get_service(ServiceKeys.SMITHING)     as SmithingService
	ctx._bank         = registry.get_service(ServiceKeys.BANK)         as BankService
	ctx._trade         = registry.get_service(ServiceKeys.TRADE)          as TradeService
	ctx._auction_house = registry.get_service(ServiceKeys.AUCTION_HOUSE)  as AuctionHouseService
	ctx._item_protection = registry.get_service(ServiceKeys.ITEM_PROTECTION) as ItemProtectionService
	ctx._data         = registry.get_service(ServiceKeys.DATA)         as DataService
	ctx._settings     = registry.get_service(ServiceKeys.SETTINGS_SERVICE) as SettingsService
	ctx._achievement  = registry.get_service(ServiceKeys.ACHIEVEMENT)      as AchievementService
	ctx._character_creation = registry.get_service(ServiceKeys.CHARACTER_CREATION) as CharacterCreationService
	ctx._wiki         = registry.get_service(ServiceKeys.WIKI)         as WikiService
	ctx._bus          = registry.get_service(ServiceKeys.EVENT_BUS)    as IEventBus
	ctx._world        = registry.get_service(ServiceKeys.WORLD)        as WorldService
	var session := registry.get_service(ServiceKeys.SESSION_MANAGER) as SessionManager
	ctx._local_peer_id   = session.get_local_peer_id()   if is_instance_valid(session) else 1
	ctx._local_player_id = session.get_local_player_id() if is_instance_valid(session) else ""
	return ctx

static func for_test() -> UIContext:
	return UIContext.new()

func get_quest()        -> QuestService:    return _quest
func get_skill_system() -> SkillSystem:     return _skill_system
func get_inventory()    -> InventorySystem: return _inventory
func get_equipment()    -> EquipmentService: return _equipment
func get_currency()     -> CurrencyService:  return _currency
func get_shop()         -> ShopService:      return _shop
func get_smithing()     -> SmithingService:  return _smithing
func get_bank()         -> BankService:      return _bank
func get_trade_service() -> TradeService:        return _trade
func get_auction_house() -> AuctionHouseService: return _auction_house
func get_item_protection() -> ItemProtectionService: return _item_protection
func get_data()         -> DataService:      return _data
func get_world()        -> WorldService:     return _world
func get_settings()     -> SettingsService:  return _settings
func get_achievement_service() -> AchievementService: return _achievement
func get_character_creation_service() -> CharacterCreationService: return _character_creation
func get_wiki_service() -> WikiService: return _wiki
func bus()              -> IEventBus:        return _bus
func get_local_peer_id() -> int:             return _local_peer_id
func get_local_player_id() -> String:        return _local_player_id
