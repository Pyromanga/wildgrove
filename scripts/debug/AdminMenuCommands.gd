class_name AdminMenuCommands
extends RefCounted

## AdminMenuCommands — In-Game "Admin-Menü" als Befehlserweiterung für den
## bestehenden SimpleTerminal (scripts/debug/).
##
## BEWUSST an SimpleTerminal angehängt statt eigenes UI/Autoload:
## SimpleTerminal ist bereits genau das gewünschte Zugriffsmodell — lokal,
## auth-frei, NUR im Debug-Build (OS.is_debug_build()-Gate sitzt in
## SimpleTerminal._ready(), siehe dortiger Kommentar) — und bringt bereits
## Toggle-Button + Texteingabe fürs Touch-Display mit (TerminalController).
## Ein zweites, eigenständiges UI hätte dieselbe Gating-Logik + Ein-/Ausgabe
## duplizieren müssen. Eigene Datei statt Erweiterung von
## SimpleTerminal.gd direkt: hält die (sicherheitsrelevanten!) Cheat-Befehle
## von der allgemeinen Log/Diagnose-Konsole getrennt und leicht auffindbar.
##
## SCOPE (bewusst): nur lokal, Solo/Host (Tier 1/2) — kein neuer
## Netzwerk-Endpunkt. "Andere Spieler" meint hier andere Peers, die im
## selben Host-Prozess laufen (der Host IST hier die Autorität, siehe
## CurrencyService/InventorySystem-Kommentare "Server vertraut niemandem" —
## diese Services dürfen nur auf der Autorität mutiert werden, was hier
## automatisch erfüllt ist, weil SimpleTerminal ohnehin nur lokal läuft).
## Ein echtes Remote-Admin-Menü für einen entfernten Tier-3-Dedicated-Server
## bräuchte einen eigenen, auth-gesicherten RPC-Kanal (analog AdminConsole/
## AdminConsoleTcpServer) — absichtlich NICHT Teil dieser Datei.
##
## Befehle: players, gold, item, giveall, speed, heal, sethealth, maxhealth,
##          kill, revive, role, kick, tp, bring, weather, time, tick, setskilllevel

const LOG_CAT := "AdminMenu"
const SPEED_SOURCE_ID := "admin_speed_boost"

var _terminal: Node  # SimpleTerminal-Instanz (Autoload), für register_command()/get_tree()

func _init(terminal: Node) -> void:
	_terminal = terminal
	_register_commands()

# ─────────────────────────────────────────────
# Registrierung
# ─────────────────────────────────────────────

func _register_commands() -> void:
	_terminal.register_command("players", "Verbundene Spieler mit id + Rolle anzeigen", func(args): _cmd_players(args))
	_terminal.register_command("gold", "gold <betrag> [spieler|me] — Gold geben/abziehen (negativ = abziehen)", func(args): _cmd_gold(args))
	_terminal.register_command("item", "item <item_id> [menge=1] [spieler|me] — Item vergeben", func(args): _cmd_item(args))
	_terminal.register_command("giveall", "giveall [menge=1] [spieler|me] — je 1x (oder <menge>x) von JEDEM bekannten Item vergeben", func(args): _cmd_giveall(args))
	_terminal.register_command("speed", "speed <multiplikator> [spieler|me] — Lauftempo skalieren (1 = zurücksetzen)", func(args): _cmd_speed(args))
	_terminal.register_command("heal", "heal [spieler|me] — komplett heilen", func(args): _cmd_heal(args))
	_terminal.register_command("sethealth", "sethealth <wert> [spieler|me] — aktuelles Leben exakt setzen", func(args): _cmd_sethealth(args))
	_terminal.register_command("maxhealth", "maxhealth <wert> [spieler|me] — Maximal-Leben setzen (setzt auch aktuelles Leben neu)", func(args): _cmd_maxhealth(args))
	_terminal.register_command("kill", "kill [spieler|me] — Spieler töten", func(args): _cmd_kill(args))
	_terminal.register_command("revive", "revive [spieler|me] — vollständig wiederbeleben", func(args): _cmd_revive(args))
	_terminal.register_command("role", "role [<spieler|me> <rolle>] — Rolle setzen, ohne Argumente: bekannte Rollen auflisten", func(args): _cmd_role(args))
	_terminal.register_command("kick", "kick <spieler> — Spieler vom Server trennen", func(args): _cmd_kick(args))
	_terminal.register_command("tp", "tp <spieler> — dich zu diesem Spieler teleportieren", func(args): _cmd_tp(args))
	_terminal.register_command("bring", "bring <spieler> — diesen Spieler zu dir teleportieren", func(args): _cmd_bring(args))
	_terminal.register_command("weather", "weather [clear|rain|storm|fog|snow] — Wetter setzen, ohne Argument: aktuelles Wetter + Liste anzeigen", func(args): _cmd_weather(args))
	_terminal.register_command("time", "time [morgen|mittag|abend|mitternacht|<Stunde 0-23.9>] — Tageszeit setzen, ohne Argument: aktuelle Uhrzeit anzeigen", func(args): _cmd_time(args))
	_terminal.register_command("tick", "tick [<faktor>|reset] — Zeitgeschwindigkeit setzen, ohne Argument: aktuellen Wert anzeigen", func(args): _cmd_tick(args))
	_terminal.register_command("setskilllevel", "setskilllevel <skill_id> <level> [spieler|me] — Skill-Level direkt setzen (setzt XP dabei auf 0)", func(args): _cmd_setskilllevel(args))

# ─────────────────────────────────────────────
# Befehle
# ─────────────────────────────────────────────

func _cmd_players(_args: Array) -> void:
	var session := _session()
	if session == null:
		return
	var perms := _perms()
	var slots: Dictionary = session.get_all_slots()
	if slots.is_empty():
		_out_info("Keine Spieler verbunden.")
		return
	var lines: Array[String] = ["Verbundene Spieler (%d):" % slots.size()]
	for peer_id in slots:
		var pid: String = slots[peer_id]
		var role_id := (perms.get_role_id(pid) if is_instance_valid(perms) else "?")
		var marker := "  ← du" if pid == session.get_local_player_id() else ""
		lines.append("  peer=%s  id=%s  rolle=%s%s" % [str(peer_id), pid, role_id, marker])
	_out_info("\n".join(lines))

func _cmd_gold(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: gold <betrag> [spieler|me]  (negativer Betrag zieht ab)")
		return
	if not args[0].is_valid_int():
		_out_warn("Betrag muss eine Zahl sein.")
		return
	var amount := int(args[0])
	if amount == 0:
		_out_warn("Betrag darf nicht 0 sein.")
		return
	var player_id := _resolve_player(args, 1)
	var currency := _svc(ServiceKeys.CURRENCY)
	if currency == null:
		return
	var ok: bool = currency.request_add_gold(player_id, amount) if amount > 0 else currency.request_remove_gold(player_id, -amount)
	if ok:
		_out_info("Gold von '%s': %+d → jetzt %d." % [player_id, amount, currency.get_gold(player_id)])
	else:
		_out_warn("Gold-Änderung abgelehnt (siehe Log — z.B. MAX_GOLD oder nicht genug Guthaben).")

func _cmd_item(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: item <item_id> [menge=1] [spieler|me]")
		return
	var item_id: String = args[0]
	var qty := 1
	var player_idx := 1
	if args.size() > 1 and args[1].is_valid_int():
		qty = int(args[1])
		player_idx = 2
	if qty <= 0:
		_out_warn("Menge muss > 0 sein.")
		return
	var player_id := _resolve_player(args, player_idx)
	var inventory := _svc(ServiceKeys.INVENTORY)
	if inventory == null:
		return
	if inventory.get_item_info(item_id) == null:
		_out_warn("Unbekannte item_id: '%s'." % item_id)
		return
	if inventory.request_add_item(item_id, player_id, qty):
		_out_info("'%s' x%d an '%s' vergeben." % [item_id, qty, player_id])
	else:
		_out_warn("Item konnte nicht vergeben werden (Inventar voll/zu schwer?).")

## Vergibt EIN Exemplar (oder <menge>x) jedes Items aus dem kompletten
## Katalog (get_all_item_definitions()) — dieselbe Quelle, die auch
## AdminPanelUI._refresh_item_catalog() für seine Dropdowns nutzt, damit
## "alle Items" hier wirklich alle im Spiel bekannten Items meint statt einer
## separat gepflegten Liste, die mit neuen Items veralten könnte. Einzelne
## Ablehnungen (Slot voll, Item nicht stapelbar über max_stack hinaus etc.)
## brechen den Durchlauf NICHT ab — werden gesammelt und am Ende gemeldet,
## damit ein einzelnes Problem-Item nicht die restlichen ~40 blockiert.
func _cmd_giveall(args: Array) -> void:
	var qty := 1
	var player_idx := 0
	if args.size() > 0 and args[0].is_valid_int():
		qty = int(args[0])
		player_idx = 1
	if qty <= 0:
		_out_warn("Menge muss > 0 sein.")
		return
	var player_id := _resolve_player(args, player_idx)
	var inventory := _svc(ServiceKeys.INVENTORY)
	if inventory == null:
		return
	var defs: Dictionary = inventory.get_all_item_definitions()
	if defs.is_empty():
		_out_warn("Item-Katalog leer — noch keine Session/DataService geladen?")
		return
	var given := 0
	var failed: Array[String] = []
	for item_id in defs.keys():
		if inventory.request_add_item(item_id, player_id, qty):
			given += 1
		else:
			failed.append(item_id)
	_out_info("giveall: %d/%d Item-Typen x%d an '%s' vergeben." % [given, defs.size(), qty, player_id])
	if not failed.is_empty():
		_out_warn("Abgelehnt (Inventar voll/zu schwer?): %s" % str(failed))

func _cmd_speed(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: speed <multiplikator> [spieler|me]  (1 = zurücksetzen)")
		return
	if not args[0].is_valid_float() and not args[0].is_valid_int():
		_out_warn("Multiplikator muss eine Zahl sein.")
		return
	var mult := float(args[0])
	if mult <= 0.0:
		_out_warn("Multiplikator muss > 0 sein.")
		return
	var player_id := _resolve_player(args, 1)
	var stat_mods := _svc(ServiceKeys.STAT_MODIFIERS)
	if stat_mods == null:
		return
	if is_equal_approx(mult, 1.0):
		stat_mods.remove_modifier(SPEED_SOURCE_ID, player_id)
		_out_info("Speed-Boost für '%s' entfernt (zurückgesetzt)." % player_id)
		return
	var mod := StatModifier.permanent(SPEED_SOURCE_ID, "move_speed", StatModifier.Operation.PERCENT_MULTIPLY, mult)
	stat_mods.add_modifier(mod, player_id)
	_out_info("Speed für '%s' auf ×%.2f gesetzt." % [player_id, mult])

func _cmd_heal(args: Array) -> void:
	var player_id := _resolve_player(args, 0)
	var hc := _health_of(player_id)
	if hc == null:
		return
	hc.heal(hc.max_health)
	_out_info("'%s' geheilt: %d/%d." % [player_id, hc.current_health, hc.max_health])

func _cmd_sethealth(args: Array) -> void:
	if args.is_empty() or not args[0].is_valid_int():
		_out_warn("Verwendung: sethealth <wert> [spieler|me]")
		return
	var player_id := _resolve_player(args, 1)
	var hc := _health_of(player_id)
	if hc == null:
		return
	var amount: int = clampi(int(args[0]), 0, hc.max_health)
	var delta := amount - hc.current_health
	if delta > 0:
		hc.heal(delta)
	elif delta < 0:
		hc.take_damage(-delta)
	_out_info("Leben von '%s' auf %d/%d gesetzt." % [player_id, hc.current_health, hc.max_health])

func _cmd_maxhealth(args: Array) -> void:
	if args.is_empty() or not args[0].is_valid_int():
		_out_warn("Verwendung: maxhealth <wert> [spieler|me]")
		return
	var value := int(args[0])
	if value <= 0:
		_out_warn("Wert muss > 0 sein.")
		return
	var player_id := _resolve_player(args, 1)
	var hc := _health_of(player_id)
	if hc == null:
		return
	# HealthComponent.max_health-Setter (siehe dortiger Kontrakt-Kommentar,
	# 2026-09-25 gefixt): auf einer bereits laufenden Komponente wird das
	# aktuelle Leben NICHT mehr automatisch mit hochgesetzt/geheilt — es
	# bleibt erhalten und wird nur nach unten geklemmt, falls es über dem
	# neuen Maximum läge. Für einen vollen Heil-auf-neues-Maximum bewusst
	# den separaten 'heal'-Befehl danach aufrufen.
	hc.max_health = value
	_out_info("Maximal-Leben von '%s' auf %d gesetzt (aktuelles Leben: %d, unverändert außer Deckelung)." % [player_id, value, hc.current_health])

func _cmd_kill(args: Array) -> void:
	var player_id := _resolve_player(args, 0)
	var hc := _health_of(player_id)
	if hc == null:
		return
	hc.take_damage(hc.current_health + 999999)
	_out_info("'%s' getötet." % player_id)

func _cmd_revive(args: Array) -> void:
	var player_id := _resolve_player(args, 0)
	var hc := _health_of(player_id)
	if hc == null:
		return
	hc.reset()
	_out_info("'%s' wiederbelebt: %d/%d." % [player_id, hc.current_health, hc.max_health])

func _cmd_role(args: Array) -> void:
	var perms := _perms()
	if perms == null:
		return
	if args.is_empty():
		_out_info("Bekannte Rollen: %s" % str(perms.list_role_ids()))
		return
	if args.size() < 2:
		_out_warn("Verwendung: role <spieler|me> <rolle>  (ohne Argumente: Rollen auflisten)")
		return
	var player_id := _resolve_player(args, 0)
	var role_id: String = args[1]
	if perms.assign_role(player_id, role_id):
		_out_info("Rolle '%s' für '%s' gesetzt." % [role_id, player_id])
	else:
		_out_warn("Unbekannte Rolle '%s'. Bekannte Rollen: %s" % [role_id, str(perms.list_role_ids())])

func _cmd_kick(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: kick <spieler>")
		return
	var session := _session()
	if session == null:
		return
	if session.kick_player(args[0]):
		_out_info("'%s' getrennt." % args[0])
	else:
		_out_warn("Konnte '%s' nicht trennen (nicht verbunden?)." % args[0])

func _cmd_tp(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: tp <spieler>  — teleportiert dich zu diesem Spieler")
		return
	var target := _find_player_node(args[0])
	if target == null:
		_out_warn("Spieler '%s' nicht gefunden (nicht verbunden/gespawnt?)." % args[0])
		return
	var me := _find_local_player_node()
	if me == null:
		_out_warn("Eigener Spieler-Node nicht gefunden.")
		return
	me.teleport_to(target.global_position)
	_out_info("Zu '%s' teleportiert." % args[0])

func _cmd_bring(args: Array) -> void:
	if args.is_empty():
		_out_warn("Verwendung: bring <spieler>  — teleportiert diesen Spieler zu dir")
		return
	var target := _find_player_node(args[0])
	if target == null:
		_out_warn("Spieler '%s' nicht gefunden (nicht verbunden/gespawnt?)." % args[0])
		return
	var me := _find_local_player_node()
	if me == null:
		_out_warn("Eigener Spieler-Node nicht gefunden.")
		return
	target.teleport_to(me.global_position)
	_out_info("'%s' zu dir teleportiert." % args[0])

## Wetter direkt setzen (siehe WorldService.admin_set_weather()/WeatherService.
## force_weather()) — betrifft die ganze Welt, kein Ziel-Spieler-Argument
## anders als die meisten übrigen Befehle hier (siehe Klassenkommentar
## "SCOPE": ohnehin nur lokal, gilt also automatisch nur für den eigenen
## Host-Prozess, nicht für ferne Peers).
func _cmd_weather(args: Array) -> void:
	var world := _svc(ServiceKeys.WORLD)
	if world == null:
		return
	if args.is_empty():
		_out_info(
			"Aktuelles Wetter: '%s'. Verfügbar: %s" %
			[world.current_weather, str(world.admin_get_weather_types())]
		)
		return
	var requested: String = args[0].to_lower()
	if world.admin_set_weather(requested):
		_out_info("Wetter gesetzt: '%s'." % requested)
	else:
		_out_warn("Unbekanntes Wetter '%s'. Verfügbar: %s" % [requested, str(world.admin_get_weather_types())])

## Benannte Uhrzeiten fürs Admin-Menü — reine Bequemlichkeit, WorldTimeService
## selbst kennt nur die reine Fließkomma-Stunde (siehe admin_set_time_of_day()).
## Eine rohe Stunde (z.B. "time 14.5") funktioniert immer zusätzlich, siehe
## unten.
const TIME_PRESETS: Dictionary = {
	"morgen": 7.0, "morning": 7.0,
	"mittag": 13.0, "tag": 13.0, "day": 13.0, "noon": 13.0,
	"abend": 19.0, "evening": 19.0, "dusk": 19.0,
	"nacht": 23.0, "night": 23.0,
	"mitternacht": 0.0, "midnight": 0.0,
}

## Tageszeit direkt setzen (siehe WorldService.admin_set_time_of_day()) —
## global wie "weather", kein Ziel-Spieler-Argument.
func _cmd_time(args: Array) -> void:
	var world := _svc(ServiceKeys.WORLD)
	if world == null:
		return
	if args.is_empty():
		_out_info("Aktuelle Uhrzeit: %.1f Uhr. Presets: %s" % [world.day_time, str(TIME_PRESETS.keys())])
		return
	var raw: String = args[0].to_lower()
	var hour: float
	if TIME_PRESETS.has(raw):
		hour = TIME_PRESETS[raw]
	elif raw.is_valid_float():
		hour = float(raw)
	else:
		_out_warn("Unbekannte Zeitangabe '%s'. Presets: %s, oder eine Stunde (z.B. 14.5)." % [raw, str(TIME_PRESETS.keys())])
		return
	world.admin_set_time_of_day(hour)
	_out_info("Uhrzeit gesetzt: %.1f Uhr." % hour)

## Zeitgeschwindigkeit direkt setzen (siehe WorldService.admin_set_time_speed())
## — zum schnellen Durchspulen (Tag/Nacht, Wetter-Rollover, Baum-Wachstum über
## Spieltage). "reset"/"normal" statt der nackten Zahl, weil WorldTimeService.
## DEFAULT_TIME_SPEED (0.05) sonst an zwei Stellen gepflegt werden müsste.
func _cmd_tick(args: Array) -> void:
	var world := _svc(ServiceKeys.WORLD)
	if world == null:
		return
	if args.is_empty():
		_out_info("Aktuelle Zeitgeschwindigkeit: %.2f Spielstunden/Sekunde." % world.admin_get_time_speed())
		return
	var raw: String = args[0].to_lower()
	var speed: float
	if raw == "reset" or raw == "normal":
		speed = WorldTimeService.DEFAULT_TIME_SPEED
	elif raw.is_valid_float():
		speed = float(raw)
	else:
		_out_warn("Verwendung: tick <faktor>|reset (z.B. 'tick 0.5', 'tick reset').")
		return
	world.admin_set_time_speed(speed)
	_out_info("Zeitgeschwindigkeit gesetzt: %.2f Spielstunden/Sekunde." % speed)

## Setzt das Level eines einzelnen Skills direkt (siehe SkillSystem.
## request_set_level()-Kommentar für die Begründung "Level statt XP-Menge").
func _cmd_setskilllevel(args: Array) -> void:
	if args.size() < 2:
		_out_warn("Verwendung: setskilllevel <skill_id> <level> [spieler|me]")
		return
	var skill_id: String = args[0]
	if not args[1].is_valid_int():
		_out_warn("Level muss eine Zahl sein.")
		return
	var level := int(args[1])
	if level <= 0:
		_out_warn("Level muss > 0 sein.")
		return
	var player_id := _resolve_player(args, 2)
	var skills := _svc(ServiceKeys.SKILL_SYSTEM)
	if skills == null:
		return
	if not skills.has_skill(skill_id, player_id):
		_out_warn("Unbekannter Skill '%s'. Bekannte Skills: %s" % [skill_id, str(skills.get_skill_ids(player_id))])
		return
	if skills.request_set_level(skill_id, level, player_id):
		_out_info("Skill '%s' von '%s' auf Level %d gesetzt." % [skill_id, player_id, skills.get_level(skill_id, player_id)])
	else:
		_out_warn("Level konnte nicht gesetzt werden (siehe Log).")

# ─────────────────────────────────────────────
# Helfer
# ─────────────────────────────────────────────

## Löst Index idx in args zu einer player_id auf. Fehlt das Argument, oder ist
## es leer/"me", wird die eigene player_id (lokaler Spieler) verwendet.
func _resolve_player(args: Array, idx: int) -> String:
	var session := _session()
	var local_id: String = (session.get_local_player_id() if is_instance_valid(session) else "")
	if args.size() <= idx:
		return local_id
	var raw: String = args[idx]
	if raw.is_empty() or raw.to_lower() == "me":
		return local_id
	return raw

func _health_of(player_id: String) -> HealthComponent:
	var node := _find_player_node(player_id)
	if node == null:
		_out_warn("Spieler '%s' nicht gefunden (nicht verbunden/gespawnt?)." % player_id)
		return null
	var hc: HealthComponent = node.health
	if not is_instance_valid(hc):
		_out_warn("HealthComponent für '%s' nicht verfügbar." % player_id)
		return null
	return hc

## Sucht den Player-Node (Gruppe "player", siehe Player._ready()) zur
## übergebenen player_id über die peer_id → player_id-Zuordnung von
## SessionManager (analog Player._resolve_player_uuid()).
func _find_player_node(player_id: String) -> Node:
	if player_id.is_empty():
		return null
	var session := _session()
	if session == null:
		return null
	for node in _terminal.get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(node):
			continue
		if session.get_player_id_for_peer(node.get_owner_peer_id()) == player_id:
			return node
	return null

func _find_local_player_node() -> Node:
	var session := _session()
	if session == null:
		return null
	return _find_player_node(session.get_local_player_id())

func _orch() -> Node:
	var orch := _terminal.get_node_or_null("/root/ServiceOrchestrator")
	if orch == null:
		_out_warn("ServiceOrchestrator nicht verfügbar.")
	return orch

func _svc(key: String) -> Object:
	var orch := _orch()
	if orch == null:
		return null
	var svc: Object = orch.get_service(key)
	if not is_instance_valid(svc):
		_out_warn("Service '%s' nicht verfügbar." % key)
		return null
	return svc

func _session() -> SessionManager:
	return _svc(ServiceKeys.SESSION_MANAGER)

func _perms() -> PermissionService:
	return _svc(ServiceKeys.PERMISSION_SERVICE)

func _out_info(msg: String) -> void:
	AppLogger.log_info(msg, LOG_CAT)

func _out_warn(msg: String) -> void:
	AppLogger.log_warn(msg, LOG_CAT)
