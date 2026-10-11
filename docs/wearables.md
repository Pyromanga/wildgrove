# Geschlecht & echte Kleidung

Zwei Dinge: Figuren sind **Frau oder Mann** (eigene Körperform), und **alles, was jemand trägt, ist ein
echtes Item**, das sich an- und ausziehen lässt — bei Spielern und bei NPCs.

## Geschlecht
- Look-Feld `sex` (`male`/`female`, Default `male`), im Aussehens-Editor ganz oben unter „Körper“.
- Körperform steht in `CharacterLook.SEX_PARAMS` (Schulterbreite, Hüftbreite, Gliedmaßen, Hals, Brust,
  Größenfaktor). `CharacterPartBuilder` setzt das um: Frauen haben schmalere Schultern, breiteres Becken,
  dünnere Arme/Beine, Brust und sind ~4 % kleiner (`CharacterLook.body_scale()` = Größenstufe × Geschlecht).
- Zufalls-NPCs (`from_seed`) würfeln das Geschlecht mit; zufällige Frauen tragen keinen Bart.
  Story-NPC-Presets in `NPCLook.PRESETS` haben `sex` fest gesetzt.

## Echte Kleidung
Getragenes ist im **Look** gespeichert (Felder mit `"worn": true` in `CharacterLook.FIELDS`). Der Look ist
schon gespeichert, an den Besitzer zurückgemeldet und an alle Peers gebroadcastet — so sehen alle dieselbe
Kleidung, Spawn-Payload und Save brauchten keine Änderung. Alt-Spielstände funktionieren ohne Migration:
was im Look stand, ist jetzt „getragen“.

| Kategorie | Slots | Item-Klasse |
|---|---|---|
| Kleidung | `hat glasses scarf shoulders back shirt belt pouch pants shoes` | `WearableDefinition` (`cl_<slot>_<werte>`) |
| Rüstung | `helmet chest legs boots` | `ArmorDefinition` (bestehend, mit Schutzwert) |

Rüstung wird **über** der Kleidung gezeichnet; ein Helm verdeckt Haare und Hut.
Ohne Oberteil/Hose/Schuhe: nackte Haut, Unterhose (bei Frauen zusätzlich ein Brustband), blanke Füße.

### Ablauf (Spieler)
1. Inventar / Equipment-Panel → **👕 Anziehen** → `EquipmentService.request_equip(slot, item_id, pid)`.
2. Autorität (`on_equip_confirmed`): Item bekannt? Passt es in den Slot (`_slot_accepts`)? Besitzt der Spieler es?
3. Kleidung: `_wear_confirmed()` → `CharacterCreationService.set_worn()` schreibt die Look-Felder, das Item
   verlässt das Inventar, das vorher getragene Teil kommt zurück. Ausziehen (`❌` im Panel) umgekehrt;
   bei vollem Inventar bleibt das Teil am Körper.
4. Rüstung: bleibt im `EquipmentService` die Wahrheit (Stats, Save) und wird per `set_armor_mirror()` in die
   `armor_*`-Look-Felder gespiegelt (auch beim Laden: `inject_wearables()`).
5. Look-Änderung → `PlayerVisuals.apply_look()` baut den Körper neu (Waffen hängen an Slots und überleben das).

**Sicherheit:** Editor-Updates laufen durch `CharacterLook.sanitize_body()` — Körper-Felder darf der Spieler
setzen, getragene nie. Anziehen geht nur über den EquipmentService mit Besitz-Prüfung.

### Neue Kleidung / Rüstung
- Neue Farbe oder neuer Schnitt: Eintrag in `CharacterLook.CATALOG` (+ Bauanleitung im `CharacterPartBuilder`
  bei neuem Schnitt) → `WearableCatalog` erzeugt das Item automatisch, `DataService` registriert es.
- Neue Rüstung: `.tres` in `data/items/armor/` **und** Eintrag in `CharacterLook.CATALOG["armor_<slot>"]`
  (mit `tier`). `test_wearable_catalog.gd` schlägt an, wenn eins von beiden fehlt.

## NPCs
Derselbe Körperbau, dieselben Items. `NPCLook`-Presets setzen Kleidung/Zubehör als Look-Felder
(z. B. Talia: `armor_helmet: steel_helmet`, `shoulders: steel`). Zur Laufzeit:
`NPCVisualBuilder.wear(npc, item_id)`, `take_off(npc, slot)`, `get_outfit(npc)` (nur Optik, lokal).

## Bausteine
| Datei | Aufgabe |
|---|---|
| `scripts/entities/player/appearance/CharacterLook.gd` | `sex`, worn-Felder, `sanitize_body()`, `body_scale()` |
| `…/CharacterPartBuilder.gd` | Körperform, Nacktzustände |
| `…/WornGearBuilder.gd` | Schal, Rucksack/Umhang, Beutel, Schulterplatten, Rüstung |
| `scripts/economy/equipment/WearableDefinition.gd`, `WearableCatalog.gd` | Items aus dem Look-Katalog, Item ↔ Slot ↔ Look |
| `scripts/economy/equipment/EquipmentService.gd` | Anziehen/Ausziehen, Slot-Prüfung, Rüstungs-Spiegel |
| `scripts/onboarding/CharacterCreationService.gd` | `set_worn()`, `set_armor_mirror()`, `get_worn_item_id()` |
| `scripts/entities/npc/NPCVisualBuilder.gd`, `NPCLook.gd` | NPC-Outfit, `wear()`/`take_off()` |

## Bekannte Grenzen
- **Neue Kleidung beschaffen:** Es gibt (noch) keine Quelle im Spiel — Spieler starten bekleidet und können nur
  tauschen, was sie ausgezogen haben. Admin-Menü kann alle `cl_*`-Items vergeben. Shop/Loot/Handwerk: offen.
- Kleidung hat keinen Stat, kein Icon (Emoji pro Slot im Panel), keine Haltbarkeit.
- Die Optik ist aus Primitiven gebaut und nur im Code geprüft, nicht visuell abgenommen (Frauen-Proportionen,
  Brustband, Rüstung über Brust/Becken sind Startwerte).
