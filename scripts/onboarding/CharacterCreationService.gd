extends Service
class_name CharacterCreationService

## ADR-048: Charaktererstellung / Onboarding-Fragenreihe.
##
## Vorgabe: eine kurze Fragenreihe (ähnlich Animal Crossing) bestimmt beim
## ersten Login sowohl das Aussehen als auch "Charakterzüge" des Spielers.
## Der Spieler wählt Antworten, NICHT direkt ein Aussehen — das Aussehen wird
## aus den Antworten ABGELEITET (Mehrheitsentscheid über die vier
## `APPEARANCE_ARCHETYPES`, siehe `_derive_appearance()`). Presets sind für
## diese Runde bewusst grob (vier feste Farbtöne) — Feintuning (Slider) ist
## explizit NICHT Teil dieser Runde, siehe unten.
##
## KOSMETISCH-ONLY (bewusste Entscheidung, 2026-08 — noch nicht final):
## Charakterzüge haben in dieser Runde AUSSCHLIESSLICH kosmetische Wirkung
## (Aussehen). Kein Effekt auf Stats/Dialoge. Zwei Ausbaustufen sind als
## Spike vorgemerkt (siehe `TODO-offene-probleme.md`): (a) reine
## Flavor-Wirkung (NPC-Dialoge reagieren auf `get_traits()`), (b) echte
## Stat-Boni über `StatModifierService`. Beides bewusst NICHT in dieser
## Runde entschieden — `get_traits()` existiert bereits jetzt, damit ein
## künftiger Spike ohne Datenmodell-Umbau andocken kann.
##
## AUTORITÄT (Round 106 nachgezogen — vorher exakt der Round-102-Kompromiss
## von `AchievementService`, siehe ADR-048 "Autorität"):
## `on_submit_answers_confirmed()`/`on_skip_creation_confirmed()` laufen nur
## auf der Autorität (`_require_authority()`). `request_submit_answers()`/
## `request_skip_creation()` sind die neuen Client-Einstiegspunkte —
## identisches Verzweigungsmuster wie `ReportService.request_submit_report()`:
## ohne echten Peer oder auf dem Host läuft das direkt in
## `on_*_confirmed()`, ein Nicht-Host-Client schickt stattdessen ein RPC
## (`NetworkBridge.send_character_creation_submit_answers()`/
## `send_character_creation_skip()`).
##
## RÜCKKANAL: anders als bei `ReportService` (reine Einbahnstraße, Meldungen
## sind nie für den Melder selbst relevant) braucht der anfragende Client
## hier das Ergebnis zurück — sein eigenes Aussehen. Die Autorität schickt
## nach `on_*_confirmed()` gezielt an den betroffenen Spieler zurück
## (`send_character_creation_completed_for_player()`/
## `send_character_creation_skipped_for_player()`, überspringt den lokalen
## Peer — identisches Guard-/Skip-Local-Muster wie
## `send_achievement_unlocked_for_player()`). `_on_remote_creation_completed_
## received()`/`_on_remote_creation_skipped_received()` übernehmen das
## Ergebnis clientseitig direkt in `_seen`/`_completed`/`_appearance`/
## `_traits` (ohne `_require_authority()` — hier wird nichts neu
## entschieden, nur gespiegelt, exakt `AchievementService._on_remote_unlock_
## received()`s Kommentar). Beide Pfade emittieren dasselbe neue
## `character_creation_confirmed`-Signal — bewusst NICHT `character_created`/
## `character_creation_skipped` wiederverwendet, weil die laut
## `AchievementService`-Klassenkommentar ("TRIGGER-QUELLEN") nachweislich
## AUSSCHLIESSLICH auf der Autorität feuern dürfen; ein Re-Emit auf dem
## Client würde dort ungewollt `grant_progress()` anstoßen (hinter
## `_require_authority()` zwar folgenlos, aber unnötiger Log-Lärm) und die
## dokumentierte Invariante brechen.
##
## PERSISTENZ: `SAVE_KEY = "character_creation"`, Save-Interface analog
## `StatsService`/`AchievementService`.
##
## TRIGGER-QUELLE für `AchievementService` (Round 105, siehe dort):
## `character_created`/`character_creation_skipped` — fünfte/sechste
## Trigger-Quelle neben PvP-Kill/Auktion/Meldung/Statistiken.
##
## LOOK (Aussehens-Ausbau, nach Round 107): zusätzlich zum groben Archetyp-
## Aussehen hat jeder Spieler einen vollständigen `CharacterLook` (Hautton,
## Frisur, Haarfarbe, Augen, Brauen, Nase, Mund, Statur, Größe, Oberteil,
## Hose — siehe `CharacterLook`). Der Look wird bei Abschluss der Fragenreihe
## aus dem Archetyp abgeleitet (`CharacterLook.from_archetype()`) und kann
## danach jederzeit über `request_set_look()` geändert werden (Editor:
## AppearancePanel). Selbe Autoritäts-/Rückkanal-Mechanik wie die Fragenreihe:
## `request_set_look()` → (RPC) → `on_set_look_confirmed()` (nur Autorität,
## sanitisiert IMMER — der Client ist nie vertrauenswürdig) →
## `send_character_look_updated_for_player()` → `_on_remote_look_updated_
## received()`. Persistenz im selben SAVE_KEY unter "look"; Alt-Spielstände
## ohne "look" bekommen den Look aus ihrem gespeicherten Archetyp abgeleitet
## (`get_look()`), es ist keine Migration nötig. Gameplay-Wirkung: keine —
## kosmetisch, wie die Charakterzüge.
##
## BEWUSST NICHT TEIL DIESER RUNDE:
##   - Die Fragenreihe selbst bleibt unverändert (vier Archetypen); der
##     Feintuning-Editor ist ein eigenes Panel (siehe LOOK oben), nicht Teil
##     des Fragen-Wizards.
##   - Kein Hook von hier in Richtung Tutorial-Guide-NPC — Teil 2 der
##     ursprünglichen Vorgabe ("...danach Spawn + erklärender NPC") ist
##     seit Round 106 als eigenständiger, unabhängig platzierter NPC
##     umgesetzt (`TutorialGuideNPC`, `scripts/onboarding/`), NICHT als
##     Fortsetzung des Charaktererstellungs-Flows — der NPC steht einfach
##     nahe dem Spawnpunkt, kein direkter Übergang vom Willkommens-Toast
##     zum Guide-Dialog.
##   - Keine Gameplay-Wirkung der Charakterzüge — siehe "KOSMETISCH-ONLY".
## BROADCAST AN ANDERE SPIELER (Round 114, schließt die bis dahin offene
## Lücke oben): zwei sich ergänzende Pfade, weil `broadcast_to_all_peers()`
## (ADR-042) explizit KEINEN Sync-Pfad für spät beitretende Peers bietet
## (siehe dortiger Klassenkommentar):
##   1. NEU beigetreten/spät verbunden: `get_look(player_id)` fließt direkt
##      in den Spawn-Payload (`NetworkBridge._register_and_broadcast_player_
##      spawn()` → `_rpc_spawn_remote_player()` → `Player.on_spawn()` config
##      `"look"`) — ein frisch gespawntes entferntes Player-Entity sieht von
##      Anfang an korrekt aus.
##   2. Bereits verbundene Peers, Look ändert sich später (Fragenreihe,
##      Überspringen, Aussehens-Editor): `_broadcast_look()` (neu, aufgerufen
##      am Ende von `on_submit_answers_confirmed()`/`on_skip_creation_
##      confirmed()`/`on_set_look_confirmed()`) schickt den Look über
##      `NetworkBridge.broadcast_to_all_peers()` an jeden anderen aktuell
##      verbundenen Peer (Empfang: `_on_broadcast_event_received()`) UND
##      wendet ihn direkt in der eigenen (Autoritäts-)Szene an — die
##      Autorität nimmt an ihrem eigenen Broadcast nicht teil (siehe
##      `broadcast_to_all_peers()`-Kommentar), muss ihre Sicht auf FREMDE
##      Spieler also separat aktualisieren.
## Beide Pfade wenden den Look über `_apply_look_to_visuals()` an — löst
## `PlayerVisuals` für eine BELIEBIGE player_id über den neu injizierten
## `WorldService` auf (`inject_world_service()`, analog
## `EquipmentService.inject_world_service()`; player_id → peer_id über
## `NetworkBridge.get_peer_id_for_player()`). Ergänzt, ersetzt aber NICHT die
## bestehenden gezielten Rückkanäle (`send_character_*_for_player()`) — jene
## bleiben zuständig für die EIGENE Kopie des betroffenen Spielers.

const LOG_CAT := "CharacterCreationService"
const SAVE_KEY := "character_creation"

## Round 114: `kind`-Wert für NetworkBridge.broadcast_to_all_peers()/
## broadcast_event_received — siehe _broadcast_look()/_on_broadcast_event_received().
const BROADCAST_KIND_LOOK := "character_look"

## preset_id -> { label, color }. Vier bewusst grobe Archetypen —
## Mehrheitsentscheid über die Antworten wählt einen davon.
const APPEARANCE_ARCHETYPES: Dictionary = {
	"sonnig": {"label": "Sonnig",   "trait_id": "lebhaft",        "color": Color(0.95, 0.75, 0.25)},
	"wald":   {"label": "Waldig",   "trait_id": "naturverbunden", "color": Color(0.25, 0.55, 0.25)},
	"flut":   {"label": "Flutig",   "trait_id": "besonnen",       "color": Color(0.25, 0.45, 0.75)},
	"asche":  {"label": "Aschig",   "trait_id": "eigenwillig",    "color": Color(0.55, 0.45, 0.60)},
}

## Default-Aussehen für übersprungene Charaktererstellung — bewusst ein
## neutraler fünfter Farbton statt eines der vier Archetypen, damit
## übersprungene Charaktere sichtbar (aber nicht abwertend) anders aussehen.
const DEFAULT_APPEARANCE_ID := "unbestimmt"
const DEFAULT_APPEARANCE_COLOR := Color(0.6, 0.6, 0.6)

## Vier Fragen, jede mit denselben vier Archetyp-Optionen (Reihenfolge pro
## Frage variiert bewusst, damit es sich nicht wie derselbe Klick viermal
## anfühlt) — hält das Datenmodell trivial: Mehrheit über `preset_id` der
## gegebenen Antworten entscheidet, siehe `_derive_appearance()`.
const QUESTIONS: Array = [
	{
		"id": "free_day",
		"text": "Was tust du lieber an einem freien Tag?",
		"options": [
			{"id": "a", "preset_id": "wald",   "label": "Durch den Wald streifen"},
			{"id": "b", "preset_id": "flut",   "label": "Am Wasser sitzen und nachdenken"},
			{"id": "c", "preset_id": "sonnig", "label": "Mit anderen ein Lagerfeuer machen"},
			{"id": "d", "preset_id": "asche",  "label": "Allein etwas Neues ausprobieren"},
		],
	},
	{
		"id": "challenge",
		"text": "Wie reagierst du auf eine Herausforderung?",
		"options": [
			{"id": "a", "preset_id": "sonnig", "label": "Kopf durch, sofort anpacken"},
			{"id": "b", "preset_id": "flut",   "label": "Erst beobachten, dann handeln"},
			{"id": "c", "preset_id": "wald",   "label": "Geduldig einen eigenen Weg finden"},
			{"id": "d", "preset_id": "asche",  "label": "Eigene Regeln aufstellen"},
		],
	},
	{
		"id": "company",
		"text": "In Gesellschaft bist du eher…",
		"options": [
			{"id": "a", "preset_id": "sonnig", "label": "Der/die Wortführer/in"},
			{"id": "b", "preset_id": "asche",  "label": "Der/die Eigenbrötler/in"},
			{"id": "c", "preset_id": "wald",   "label": "Der/die Zuhörer/in"},
			{"id": "d", "preset_id": "flut",   "label": "Der/die Vermittler/in"},
		],
	},
	{
		"id": "value",
		"text": "Was ist dir am wichtigsten?",
		"options": [
			{"id": "a", "preset_id": "flut",   "label": "Ruhe und Klarheit"},
			{"id": "b", "preset_id": "wald",   "label": "Verbindung zur Natur"},
			{"id": "c", "preset_id": "sonnig", "label": "Gemeinschaft"},
			{"id": "d", "preset_id": "asche",  "label": "Unabhängigkeit"},
		],
	},
]

## Emittiert nach erfolgreichem submit_answers() — die Trigger-Quelle für
## AchievementService (character_creator_complete).
signal character_created(player_id: String, appearance_preset_id: String, traits: Array)

## Emittiert nach skip_creation() — die Trigger-Quelle für AchievementService
## (character_creator_skipped).
signal character_creation_skipped(player_id: String)

## Round 106: emittiert IMMER auf dem anfragenden Peer, sobald das Ergebnis
## von request_submit_answers()/request_skip_creation() feststeht — direkt
## am Ende von on_submit_answers_confirmed()/on_skip_creation_confirmed()
## auf Tier 1/Host, oder nach Empfang des RPC-Rückkanals auf einem
## Nicht-Host-Client. Der UI-Controller hört darauf statt synchron
## anzunehmen, dass request_*() sofort fertig ist (siehe Klassenkommentar
## "AUTORITÄT"). BEWUSST NICHT character_created/character_creation_skipped
## wiederverwendet — siehe Klassenkommentar.
signal character_creation_confirmed(player_id: String)

## Aussehen (Look) von player_id hat sich geändert — feuert auf der Autorität
## nach on_set_look_confirmed()/Abschluss/Überspringen der Fragenreihe und auf
## einem Nicht-Host-Client nach Empfang des Rückkanals. UI-Controller wenden
## darauf den Look auf den lokalen Player an (nur für die lokale player_id).
signal look_changed(player_id: String)

var _save_system: SaveSystem = null
var _network: NetworkBridge = null
## Round 114: Late-Inject analog EquipmentService.inject_world_service() —
## löst PlayerVisuals für eine beliebige player_id auf (siehe
## _apply_look_to_visuals()). Optional: ohne WorldService (Unit-Tests,
## Tier 3 ohne eigenes Player-Entity) wird der Look weiterhin gespeichert
## und broadcastet, nur die Visual-Anwendung entfällt.
var _world: WorldService = null
## Round 106: nur für _local_player_id() auf dem Client — bestimmt, für wen
## ankommende character_creation_completed_received/_skipped_received-RPCs
## lokal übernommen werden. Identisches Muster wie
## AchievementService._session_manager (Round 104).
var _session_manager: SessionManager = null

## player_id -> true, sobald submit_answers() ODER skip_creation() lief.
## Bestimmt, ob die Fragenreihe beim nächsten Login erneut gezeigt wird.
var _seen: Dictionary = {}

## player_id -> true nur bei tatsächlich abgeschlossener Fragenreihe
## (submit_answers()), false/fehlend bei übersprungen.
var _completed: Dictionary = {}

## player_id -> preset_id (Schlüssel in APPEARANCE_ARCHETYPES, oder
## DEFAULT_APPEARANCE_ID bei übersprungener Erstellung).
var _appearance: Dictionary = {}

## player_id -> Array[String] gewählter trait_ids (leer bei übersprungen).
var _traits: Dictionary = {}

## player_id -> CharacterLook-Dictionary (siehe CharacterLook). Fehlt ein
## Eintrag (Alt-Spielstand), leitet get_look() ihn aus `_appearance` ab.
var _look: Dictionary = {}

func configure(deps: ServiceDeps) -> void:
	_save_system     = deps.get_optional(ServiceKeys.SAVE_SYSTEM)     as SaveSystem
	_network         = deps.get_optional(ServiceKeys.NETWORK_BRIDGE)  as NetworkBridge
	_session_manager = deps.get_optional(ServiceKeys.SESSION_MANAGER) as SessionManager
	_connect_network_receive()

	if _save_system:
		_save_system.register_save_provider(self)
		var saved: Variant = _save_system.get_state_for(SAVE_KEY)
		if saved is Dictionary and not (saved as Dictionary).is_empty():
			_restore_from_save(saved)
	else:
		AppLogger.log_error("Abhängigkeit 'savesystem' fehlt!", LOG_CAT)

	AppLogger.log_info("CharacterCreationService initialisiert.", LOG_CAT)

func inject_network_bridge(network: NetworkBridge) -> void:
	_network = network
	_connect_network_receive()

## Round 114: siehe Feldkommentar auf _world. Von BootPipeline Phase C7.5
## aufgerufen, direkt neben der analogen EquipmentService-Injektion.
func inject_world_service(world: WorldService) -> void:
	_world = world

func on_cleanup() -> void:
	if is_instance_valid(_network):
		if _network.character_creation_completed_received.is_connected(_on_remote_creation_completed_received):
			_network.character_creation_completed_received.disconnect(_on_remote_creation_completed_received)
		if _network.character_creation_skipped_received.is_connected(_on_remote_creation_skipped_received):
			_network.character_creation_skipped_received.disconnect(_on_remote_creation_skipped_received)
		if _network.character_look_updated_received.is_connected(_on_remote_look_updated_received):
			_network.character_look_updated_received.disconnect(_on_remote_look_updated_received)
		if _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
			_network.broadcast_event_received.disconnect(_on_broadcast_event_received)

## Round 106: Gegenstück zu on_submit_answers_confirmed()/
## on_skip_creation_confirmed() (beide über _require_authority() für
## Nicht-Autorität gesperrt) — übernimmt Server-Antworten auf dem Client
## OHNE den Authority-Guard, weil hier keine eigene Mutation stattfindet,
## nur Übernahme eines bereits autoritativ entschiedenen Zustands. Exakt
## das Verdrahtungsmuster von AchievementService._connect_network_receive().
func _connect_network_receive() -> void:
	if not is_instance_valid(_network):
		return
	if not _network.character_creation_completed_received.is_connected(_on_remote_creation_completed_received):
		_network.character_creation_completed_received.connect(_on_remote_creation_completed_received)
	if not _network.character_creation_skipped_received.is_connected(_on_remote_creation_skipped_received):
		_network.character_creation_skipped_received.connect(_on_remote_creation_skipped_received)
	if not _network.character_look_updated_received.is_connected(_on_remote_look_updated_received):
		_network.character_look_updated_received.connect(_on_remote_look_updated_received)
	## Round 114: ADR-042-Broadcast-Kanal — Gegenstück zu _broadcast_look()
	## unten, informiert über Look-Änderungen ANDERER Spieler (nicht nur der
	## eigenen player_id, siehe _on_broadcast_event_received()).
	if not _network.broadcast_event_received.is_connected(_on_broadcast_event_received):
		_network.broadcast_event_received.connect(_on_broadcast_event_received)

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────

## true, wenn player_id die Fragenreihe schon gesehen hat (abgeschlossen
## ODER übersprungen) — UI zeigt sie dann nicht erneut.
func has_seen_creation(player_id: String) -> bool:
	return bool(_seen.get(player_id, false))

func get_questions() -> Array:
	return QUESTIONS.duplicate(true)

func get_appearance_archetypes() -> Dictionary:
	return APPEARANCE_ARCHETYPES.duplicate(true)

## Round 106: Client-seitiger Einstiegspunkt — analog
## ReportService.request_submit_report(). Ohne echten Peer (Tier 1) oder auf
## dem Host läuft das direkt in on_submit_answers_confirmed(); ein
## Nicht-Host-Client schickt stattdessen ein RPC an die Autorität.
func request_submit_answers(player_id: String, answers: Dictionary) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_character_creation_submit_answers(player_id, answers)
	else:
		on_submit_answers_confirmed(player_id, answers)

## Reine Ableitung Antworten -> { "appearance_id": String, "traits": Array }
## (Mehrheitsentscheid, siehe _pick_majority_preset()) ohne Zustandsänderung
## und ohne Autoritätsprüfung. Aus on_submit_answers_confirmed() herausgelöst,
## damit die Ableitung einzeln testbar ist.
func derive_from_answers(answers: Dictionary) -> Dictionary:
	var traits: Array = []
	var preset_counts: Dictionary = {}
	for question in QUESTIONS:
		var q: Dictionary = question
		var question_id: String = q["id"]
		if not answers.has(question_id):
			continue
		var chosen_option_id: String = String(answers[question_id])
		for option in (q["options"] as Array):
			var opt: Dictionary = option
			if opt["id"] != chosen_option_id:
				continue
			var preset_id: String = opt["preset_id"]
			preset_counts[preset_id] = int(preset_counts.get(preset_id, 0)) + 1
			var trait_id: String = String((APPEARANCE_ARCHETYPES.get(preset_id, {}) as Dictionary).get("trait_id", ""))
			if not trait_id.is_empty() and trait_id not in traits:
				traits.append(trait_id)
			break
	return {"appearance_id": _pick_majority_preset(preset_counts), "traits": traits}

## answers: Dictionary(question_id -> option_id). Fehlende/unbekannte
## Fragen werden ignoriert (kein harter Fehler — Antwortreihe muss nicht
## vollständig sein, Mehrheitsentscheid funktioniert auch mit weniger
## Antworten, solange mindestens eine gültig ist).
func on_submit_answers_confirmed(player_id: String, answers: Dictionary) -> void:
	if not _require_authority("on_submit_answers_confirmed"):
		return
	if player_id.is_empty():
		AppLogger.log_warn("on_submit_answers_confirmed(): leere player_id — ignoriert.", LOG_CAT)
		return

	var derived := derive_from_answers(answers)
	var appearance_id: String = derived["appearance_id"]
	var traits: Array = derived["traits"]

	_seen[player_id] = true
	_completed[player_id] = true
	_appearance[player_id] = appearance_id
	_traits[player_id] = traits
	var look := _with_current_armor(player_id, CharacterLook.from_archetype(appearance_id))
	_look[player_id] = look

	AppLogger.log_info(
		"on_submit_answers_confirmed('%s'): Aussehen='%s', Charakterzüge=%s." % [player_id, appearance_id, str(traits)],
		LOG_CAT
	)
	character_created.emit(player_id, appearance_id, traits)
	character_creation_confirmed.emit(player_id)
	look_changed.emit(player_id)
	if is_instance_valid(_network):
		_network.send_character_creation_completed_for_player(player_id, {
			"appearance_preset_id": appearance_id,
			"traits": traits,
			"look": look,
		})
	_broadcast_look(player_id, look)

## Round 106: Client-seitiger Einstiegspunkt — analog
## request_submit_answers().
func request_skip_creation(player_id: String) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_character_creation_skip(player_id)
	else:
		on_skip_creation_confirmed(player_id)

## Bricht ohne Fragenreihe ab — Aussehen fällt auf DEFAULT_APPEARANCE_ID
## zurück, keine Charakterzüge gesetzt.
func on_skip_creation_confirmed(player_id: String) -> void:
	if not _require_authority("on_skip_creation_confirmed"):
		return
	if player_id.is_empty():
		AppLogger.log_warn("on_skip_creation_confirmed(): leere player_id — ignoriert.", LOG_CAT)
		return

	_seen[player_id] = true
	_completed[player_id] = false
	_appearance[player_id] = DEFAULT_APPEARANCE_ID
	_traits[player_id] = []
	var skip_look := _with_current_armor(player_id, CharacterLook.default_look())
	_look[player_id] = skip_look

	AppLogger.log_info("on_skip_creation_confirmed('%s'): Charaktererstellung übersprungen." % player_id, LOG_CAT)
	character_creation_skipped.emit(player_id)
	character_creation_confirmed.emit(player_id)
	look_changed.emit(player_id)
	if is_instance_valid(_network):
		_network.send_character_creation_skipped_for_player(player_id, {})
	_broadcast_look(player_id, skip_look)

func get_appearance_preset_id(player_id: String) -> String:
	return String(_appearance.get(player_id, DEFAULT_APPEARANCE_ID))

## Gibt die Godot-Farbe für den aktuellen Preset von player_id zurück —
## direkt konsumierbar von PlayerVisuals.apply_appearance().
func get_appearance_color(player_id: String) -> Color:
	var preset_id := get_appearance_preset_id(player_id)
	if APPEARANCE_ARCHETYPES.has(preset_id):
		return (APPEARANCE_ARCHETYPES[preset_id] as Dictionary)["color"]
	return DEFAULT_APPEARANCE_COLOR

## Vollständiger, gültiger Look von player_id (Kopie, nie null). Fehlt ein
## gespeicherter Look (Alt-Spielstand oder noch keine Erstellung), wird er aus
## dem Archetyp abgeleitet — bei unbekannter player_id also der Default-Look.
func get_look(player_id: String) -> Dictionary:
	var stored: Variant = _look.get(player_id, null)
	if stored is Dictionary:
		return CharacterLook.sanitize(stored)
	return CharacterLook.from_archetype(get_appearance_preset_id(player_id))

## Client-seitiger Einstiegspunkt zum Ändern des Looks — analog
## request_submit_answers(): ohne echten Peer/auf dem Host direkt lokal, ein
## Nicht-Host-Client schickt ein RPC an die Autorität.
func request_set_look(player_id: String, look: Dictionary) -> void:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		_network.send_character_set_look(player_id, look)
	else:
		on_set_look_confirmed(player_id, look)

## Nur Autorität. `look` darf unvollständig/ungültig sein: fehlende oder
## unbekannte Felder behalten den bisherigen Wert (sanitize mit dem aktuellen
## Look als Basis). Wirkt unabhängig davon, ob die Fragenreihe schon gesehen
## wurde, und ändert weder `_seen` noch `_completed` (Achievements hängen an
## der Fragenreihe, nicht am Editor).
func on_set_look_confirmed(player_id: String, look: Dictionary) -> void:
	if not _require_authority("on_set_look_confirmed"):
		return
	if player_id.is_empty():
		AppLogger.log_warn("on_set_look_confirmed(): leere player_id — ignoriert.", LOG_CAT)
		return
	# sanitize_body: Körper-Felder kommen vom Spieler, Getragenes (Kleidung/Rüstung) bleibt
	# unangetastet — das ändert nur EquipmentService (mit Inventar-Prüfung), nie ein Look-Update.
	var clean := CharacterLook.sanitize_body(look, get_look(player_id))
	_look[player_id] = clean
	AppLogger.log_info("on_set_look_confirmed('%s'): Look aktualisiert." % player_id, LOG_CAT)
	look_changed.emit(player_id)
	if is_instance_valid(_network):
		_network.send_character_look_updated_for_player(player_id, {"look": clean})
	_broadcast_look(player_id, clean)

# ─────────────────────────────────────────────
# Getragenes (echte Kleidung/Rüstung) — geschrieben von EquipmentService
# ─────────────────────────────────────────────

## Item-ID, die player_id im Kleidungs-Slot trägt (WearableCatalog.SLOT_ORDER); "" = nichts.
## Funktioniert auch auf Clients (für fremde Spieler aus dem replizierten Look).
func get_worn_item_id(player_id: String, slot: String) -> String:
	return WearableCatalog.item_id_for_slot(slot, get_look(player_id))

## Nur Autorität. Zieht item_id im Kleidungs-Slot an; item_id "" zieht aus (Slot → nackt/leer).
## Inventar/Besitz prüft der Aufrufer (EquipmentService) — hier wird nur der Look geschrieben,
## repliziert (Besitzer-Rückkanal + Broadcast) und angezeigt. false bei ungültigem Slot/ID.
func set_worn(player_id: String, slot: String, item_id: String) -> bool:
	if not _require_authority("set_worn"):
		return false
	if player_id.is_empty():
		AppLogger.log_warn("set_worn(): leere player_id — ignoriert.", LOG_CAT)
		return false
	var patch := WearableCatalog.look_patch(slot, item_id)
	if patch.is_empty():
		AppLogger.log_warn("set_worn(): '%s' passt nicht in Slot '%s'." % [item_id, slot], LOG_CAT)
		return false
	_commit_worn_patch(player_id, patch)
	return true

## Nur Autorität (still: auf Clients no-op). Spiegelt ein Rüstungsteil in den Look (Anzeige +
## Replikation). Wahrheit bleibt EquipmentService; item_id "" = Slot leer.
func set_armor_mirror(player_id: String, armor_slot: String, item_id: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		return false
	var key := WearableCatalog.armor_look_key(armor_slot)
	var value := item_id if not item_id.is_empty() else "none"
	if player_id.is_empty() or key.is_empty() or not CharacterLook.option_ids(key).has(value):
		return false
	_commit_worn_patch(player_id, {key: value})
	return true

## Schreibt `patch` (Look-Felder) in den Look, meldet die Änderung und repliziert sie.
func _commit_worn_patch(player_id: String, patch: Dictionary) -> void:
	var look := get_look(player_id)
	var changed := false
	for key in patch.keys():
		if look.get(key) != patch[key]:
			look[key] = patch[key]
			changed = true
	if not changed:
		return
	var clean := CharacterLook.sanitize(look)
	_look[player_id] = clean
	look_changed.emit(player_id)
	if is_instance_valid(_network):
		_network.send_character_look_updated_for_player(player_id, {"look": clean})
	_broadcast_look(player_id, clean)

## Übernimmt die Rüstungs-Spiegel-Felder des bisherigen Looks in `look` (Neu-Erstellung soll
## angelegte Rüstung nicht unsichtbar machen, solange EquipmentService sie noch führt).
func _with_current_armor(player_id: String, look: Dictionary) -> Dictionary:
	if not _look.has(player_id):
		return look
	var current := get_look(player_id)
	for key in WearableCatalog.ARMOR_LOOK_KEYS.values():
		look[key] = current[key]
	return look

func get_traits(player_id: String) -> Array:
	return (_traits.get(player_id, []) as Array).duplicate()

func is_completed(player_id: String) -> bool:
	return bool(_completed.get(player_id, false))

# ─────────────────────────────────────────────
# Intern
# ─────────────────────────────────────────────

## Höchste Stimmenzahl gewinnt; bei Gleichstand entscheidet die
## Iterationsreihenfolge von APPEARANCE_ARCHETYPES (stabil, weil GDScript-
## Dictionaries Einfüge-Reihenfolge erhalten) — deterministisch statt
## zufällig, damit dasselbe Antwortmuster immer dasselbe Aussehen ergibt.
func _pick_majority_preset(preset_counts: Dictionary) -> String:
	if preset_counts.is_empty():
		return DEFAULT_APPEARANCE_ID
	var best_id := DEFAULT_APPEARANCE_ID
	var best_count := -1
	for preset_id in APPEARANCE_ARCHETYPES.keys():
		var count: int = int(preset_counts.get(preset_id, 0))
		if count > best_count:
			best_count = count
			best_id = preset_id
	return best_id

func _require_authority(caller: String) -> bool:
	if is_instance_valid(_network) and _network.has_peer() and not _network.is_server():
		AppLogger.log_error("%s: Aufruf auf Nicht-Autorität — verweigert." % caller, LOG_CAT)
		return false
	return true

## Round 114: einziger Aufrufort von broadcast_to_all_peers(kind=BROADCAST_
## KIND_LOOK). Nur von den drei _require_authority()-gesicherten on_*_
## confirmed()-Methoden aufgerufen, läuft also immer auf der Autorität.
## broadcast_to_all_peers() erreicht NUR bereits verbundene Peers (siehe
## dortiger Klassenkommentar) — für spät beitretende Peers sorgt stattdessen
## der Spawn-Payload (NetworkBridge._register_and_broadcast_player_spawn())
## für den korrekten Look. Die Autorität selbst nimmt an ihrem eigenen
## Broadcast nicht teil, daher der explizite lokale _apply_look_to_visuals()-
## Aufruf direkt im Anschluss — sonst bliebe FREMDER Spieler in der eigenen
## Szene der Autorität unverändert.
func _broadcast_look(player_id: String, look: Dictionary) -> void:
	if is_instance_valid(_network):
		_network.broadcast_to_all_peers(BROADCAST_KIND_LOOK, {"player_id": player_id, "look": look})
	_apply_look_to_visuals(player_id, look)

## Round 114: Gegenstück zu _broadcast_look() auf jedem ANDEREN, bereits
## verbundenen Peer (broadcast_to_all_peers() überspringt den Sender selbst).
## Übernimmt den Look zusätzlich in _look, damit get_look(player_id) auch
## für fremde Spieler auf einem Nicht-Autoritäts-Client korrekt bleibt.
func _on_broadcast_event_received(kind: String, payload: Dictionary) -> void:
	if kind != BROADCAST_KIND_LOOK:
		return
	var player_id := String(payload.get("player_id", ""))
	if player_id.is_empty():
		return
	var clean := CharacterLook.sanitize(payload.get("look", {}), get_look(player_id))
	_look[player_id] = clean
	look_changed.emit(player_id)
	_apply_look_to_visuals(player_id, clean)

## Round 114: löst PlayerVisuals für player_id über den injizierten
## WorldService auf (player_id → peer_id via NetworkBridge.get_peer_id_for_
## player()) und wendet den Look an. No-op ohne WorldService (Unit-Tests,
## Tier 3 ohne eigenes Player-Entity) oder wenn der Spieler in dieser
## lokalen Szene (noch) kein Player-Entity hat (get_player_visuals()
## liefert dann null, z. B. bevor _rpc_spawn_remote_player() gelaufen ist).
## apply_look() selbst ist ein No-Op bei unverändertem Look — ein
## zusätzlicher Aufruf für die eigene player_id (schon über die
## Aussehens-UI angewendet) ist also unschädlich, kein Sonderfall nötig.
func _apply_look_to_visuals(player_id: String, look: Dictionary) -> void:
	if not is_instance_valid(_network) or not is_instance_valid(_world):
		return
	var peer_id := _network.get_peer_id_for_player(player_id)
	if peer_id == -1:
		return
	var visuals := _world.get_player_visuals(peer_id)
	if is_instance_valid(visuals):
		visuals.apply_look(look)

# ─────────────────────────────────────────────
# Client-Empfang (Round 106) — Gegenstück zu on_submit_answers_confirmed()/
# on_skip_creation_confirmed() auf einem Nicht-Autoritäts-Peer. Übernimmt
# Server-Payloads direkt in _seen/_completed/_appearance/_traits statt über
# on_*_confirmed() zu laufen (die beide _require_authority() erzwingen) —
# hier wird nichts neu entschieden, nur ein bereits von der Autorität
# getroffenes Ergebnis gespiegelt. Exakt AchievementService._on_remote_
# unlock_received().
# ─────────────────────────────────────────────

func _local_player_id() -> String:
	return _session_manager.get_local_player_id() if is_instance_valid(_session_manager) else ""

## Payload enthält keine player_id (siehe NetworkBridge.
## send_character_creation_completed_for_player() — Adressierung läuft
## bereits über rpc_id an den Ziel-Peer) — der Empfänger IST der betroffene
## Spieler.
func _on_remote_creation_completed_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_creation_completed_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	_seen[player_id] = true
	_completed[player_id] = true
	_appearance[player_id] = String(payload.get("appearance_preset_id", DEFAULT_APPEARANCE_ID))
	_traits[player_id] = (payload.get("traits", []) as Array).duplicate()
	_look[player_id] = CharacterLook.sanitize(payload.get("look", null), CharacterLook.from_archetype(String(_appearance[player_id])))
	character_creation_confirmed.emit(player_id)
	look_changed.emit(player_id)

func _on_remote_creation_skipped_received(_payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_creation_skipped_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	_seen[player_id] = true
	_completed[player_id] = false
	_appearance[player_id] = DEFAULT_APPEARANCE_ID
	_traits[player_id] = []
	_look[player_id] = CharacterLook.default_look()
	character_creation_confirmed.emit(player_id)
	look_changed.emit(player_id)

## Look-Rückkanal nach request_set_look() auf einem Nicht-Host-Client — wie
## _on_remote_creation_completed_received(): nur spiegeln, nichts entscheiden
## (daher kein _require_authority()). Sanitisiert trotzdem, weil auch der
## Server-Payload nur ein Dictionary ist.
func _on_remote_look_updated_received(payload: Dictionary) -> void:
	var player_id := _local_player_id()
	if player_id.is_empty():
		AppLogger.log_error("_on_remote_look_updated_received: lokale player_id unbekannt (SessionManager fehlt?).", LOG_CAT)
		return
	_look[player_id] = CharacterLook.sanitize(payload.get("look", null), get_look(player_id))
	look_changed.emit(player_id)

# ─────────────────────────────────────────────
# Save-Interface (analog StatsService/AchievementService)
# ─────────────────────────────────────────────

func get_save_key() -> String:
	return SAVE_KEY

func get_save_data() -> Dictionary:
	return {
		"seen": _seen,
		"completed": _completed,
		"appearance": _appearance,
		"traits": _traits,
		"look": _look,
	}

func _restore_from_save(saved: Dictionary) -> void:
	if saved.get("seen") is Dictionary:
		_seen = saved["seen"]
	if saved.get("completed") is Dictionary:
		_completed = saved["completed"]
	if saved.get("appearance") is Dictionary:
		_appearance = saved["appearance"]
	if saved.get("traits") is Dictionary:
		_traits = saved["traits"]
	if saved.get("look") is Dictionary:
		_look = saved["look"]
