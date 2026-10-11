# WildGrove — Quest-Writing-Guide

> **Zielgruppe:** Jede Person (menschlich oder Agent), die eine neue Quest oder einen neuen
> Quest-NPC anlegt.
> **Kurzfassung:** Die Mechanik ist ernst gemeint (siehe `QuestDefinition.gd`,
> `content_forge.py`). Der **Ton** ist es nicht. WildGrove ist ein Fantasy-Sammelsurium aus
> echten Mythologien, aber jede Figur weiß selbst, dass sie in einem Spiel steckt, in dem man
> für drei Eicheln durch den Wald rennt.

---

## 1. Die Grundidee: "Pantheon-Chaos, aber mit Absicht"

WildGrove hat keine einzelne, in sich geschlossene Fantasy-Mythologie (kein "Tolkien-Klon").
Stattdessen ist die Welt ein **Marktplatz der Götter** — Figuren, Flüche, Artefakte und Ängste
aus nordischer, germanischer, römischer, griechischer, orientalischer, asiatischer und
afrikanischer Überlieferung leben nebeneinander, oft im selben Dorf, und **kommentieren das
gegenseitig**. Das ist kein Bug, das ist der Witz: Ein isländischer Wiedergänger beschwert sich
beim römischen Grenzgott über Bürokratie. Genau diese Reibung ist die Humorquelle.

**Faustregel:** Jede Kultur bekommt eine **Rolle**, keine Deko. Bevor du eine neue Figur
schreibst, frag dich: *Welche mythologische Funktion übernimmt sie in einem Handwerker-/
Sammel-/Überlebens-Spiel?* (Nicht: "welcher Gott klingt cool".)

| Kulturkreis | Zugewiesene Rolle in WildGrove | Bereits genutzt für |
|---|---|---|
| **Nordisch/Germanisch** | Handwerk, Wald, Ahnen, Wetter, Ehre-Codes | Waldläufer Erik, Bergarbeiterin Mira, Holzfäller-/Bergbau-Quests, Zeidlerin Gerlinde (fränkische Zeidlerei, `quest_gerlinde_*`), Orakel Sigrun (Runen-Orakel, `quest_sigrun_*`) |
| **Römisch** | Verwaltung, Recht, Grenzen, Bürokratie, Militär-Rang | Wachposten, Zoll-/Bank-/Auktionshaus-Flavor, Feldmesser Lucius (Agrimensor + Maulwurf, `quest_lucius_*`) |
| **Griechisch** | Rätsel, Hybris-Lektionen, Orakel, moralische Zwickmühlen | Quest-Abschluss-Dialoge mit "Prophezeiungs"-Gimmick, Ameisenfrau Myrmex (Hybris-Lektion, `quest_myrmex_*`) |
| **Orientalisch (Nahost/Nordafrika)** | Handel, Wüste, Dschinn-Logik ("drei Wünsche, aber mit Kleingedrucktem"), Gastfreundschaft als Waffe | Kräuterkundige Senna → Wüsten-/Kaktus-Questchain |
| **Asiatisch (breit: ostasiatisch, südasiatisch, südostasiatisch)** | Meisterschaft/Prüfungslinien ("erst wenn der Schüler bereit ist"), Geister der Natur, Balance-Konzepte | Kampfmeisterin Wei (chinesische Wudang-Tradition) → `quest_wei_patience`/`quest_wei_mastery`, Papiermeisterin Lian (chinesische Papiermacher-Tradition, `quest_lian_*`) |
| **Afrikanisch (breit, pan-kontinental, Kultur explizit benennen statt "Afrika" pauschal)** | Ahnengeister als Questgeber (Vorfahre erteilt Aufgabe posthum), Trickster-Figuren, orale Erzähltradition ("die Geschichte, die dir keiner glaubt") | Ahnengeist Babatunde (Yoruba-Egungun-Tradition) → `quest_babatunde_tale`/`quest_babatunde_legacy`, Baumeisterin Rudo (Shona-Handwerkstradition, Simbabwe, `quest_rudo_*`) |

⚠️ **Sensibilität:** "Orientalisch/Asiatisch/Afrikanisch" sind Platzhalter-Oberbegriffe für
diese Tabelle — beim Schreiben einer konkreten Figur immer eine **spezifische** Kultur/Region
nennen (z. B. "westafrikanische Anansi-Tradition", nicht "afrikanischer Trickster"; "persische
Dschinn-Tradition", nicht "orientalisch"). Stereotype vermeiden, **Funktion** aus der Mythologie
übernehmen, keine Kostüm-Klischees. Wenn du unsicher bist, ob etwas eine Karikatur statt ein
liebevoller Verweis ist: kurz nachfragen statt raten.

---

## 2. Der Ton: "Community-Theater inszeniert eine Edda"

Zielbild: Stell dir vor, ein enthusiastisches Laientheater hat sich vorgenommen, die
Nibelungensage, "1001 Nacht" und griechische Tragödien **gleichzeitig** aufzuführen, mit
Pappmaschee-Requisiten und offensichtlich zu wenig Probenzeit — aber mit vollem Herzblut.
Alle Figuren nehmen ihre eigene Mythologie *innerhalb der Spielwelt* todernst. Der Bruch mit
der Realität des Spielers (Inventar, Skill-Level, "5 Eisenerz") ist die Pointe.

**Drei Ton-Ebenen, die sich mischen dürfen:**

1. **Episch (Substanz):** Die Mythologie selbst wird nicht verspottet. Odin bleibt Odin,
   Anansi bleibt clever, ein Dschinn hält sich an die Regeln seiner eigenen Überlieferung.
2. **Anachronistisch (Reibung):** Die Figur trifft auf Spielmechanik oder Moderne und
   reagiert *im eigenen Charakter* darauf ("Ein Bergtroll, der Steuerformulare hasst, weil
   Formulare 'zu viele Runen für zu wenig Gold' sind").
3. **Slapstick (Ventil):** Kurze, körperliche oder situative Gags — nichts Ausschweifendes,
   ein Satz reicht ("Der Nornen-Faden ist gerissen. Schon wieder. Norn Nummer 2 gibt Norn
   Nummer 1 die Schuld.").

**Was WildGrove-Humor NICHT ist:**
- Keine Popkultur-Referenzen, die die Illusion sprengen (kein "wie in [echter Film]").
- Kein Zynismus/Sarkasmus gegenüber dem Spieler — die Figuren lachen mit der Welt, nicht
  über die Person am Bildschirm.
- Keine Ironie auf Kosten einer echten Kultur/Religion — die Reibung entsteht zwischen
  **Mythologie und Spielmechanik**, nicht zwischen "dumme alte Sage" und "cleverer moderner
  Blick".

---

## 3. Running Gags — die feste Requisite

Ein Running Gag lebt davon, dass er **wiedererkennbar**, aber **nie identisch** ist. Nutze
diese Liste als Fundus, erfinde neue nach demselben Muster (kleine Variation, gleicher Kern),
und trag neue Gags hier ein, sobald du sie irgendwo einbaust.

| Gag | Kern | Beispiel-Variante |
|---|---|---|
| **Das Nornen-Beschwerde-Amt** | Die drei nordischen Schicksalsnornen sind eigentlich eine überlastete Behörde. Jede erwähnt Formulare, Wartezeiten oder "das ist nicht meine Abteilung". | Mira (Bergbau): "Wenn dein Schicksal ist, hier zu sterben, sag den Nornen, sie sollen das schriftlich einreichen. Zweitschrift für mich." |
| **Der pensionierte Halbgott** | Irgendwo im Spiel taucht eine mythologische A-Liga-Figur (Herkules, Þór, ein kleinerer Gott) auf, die **in Rente** ist und jetzt einen bodenständigen Beruf ausübt — und das nie ganz erklärt, nur andeutet. | Ein Schmied erwähnt beiläufig "früher hab ich andere Sachen gehoben", ohne Namen zu nennen. |
| **Der Dschinn mit Kleingedrucktem** | Wünsche/Belohnungen aus orientalischer Tradition kommen technisch korrekt, aber mit einem bewusst unerwarteten Haken (der spielmechanisch trotzdem fair bleibt — kein echter Nachteil, nur Flavor). | "Der Wunsch wurde erfüllt. Anmerkung: 'Reich an Holz' war spielmechanisch als +10 % Holz-Ertrag gemeint, nicht als Adelstitel. Der Dschinn bedauert das Missverständnis nicht." |
| **Anansi hat's zuerst versucht** | Eine Trickster-Figur (Anansi-Tradition oder Äquivalent) behauptet bei JEDER cleveren Spieler-Lösung, sie hätte das schon vor Jahrhunderten genauso gemacht — unbelegt, selbstbewusst. | "Fünf Eisenerz gegen einen Goblin-Angriff getauscht? Klassisch. Hab ich mit einem Löwen gemacht. Frag nicht wie." |
| **Das Orakel, das nur Ja/Nein-Fragen falsch versteht** | Griechisches Orakel-Flavor bei Quest-Abschlüssen: kryptische "Prophezeiung", die sich im Nachhinein banal erfüllt (z. B. genau auf das nächste Quest-Reward hindeutet). | "Die Pythia sieht: Metall wird dich reich machen." (Reward: 5 Stein.) |
| **Die verwaltete Grenze** | Römisches Verwaltungs-Flavor: Zoll-/Bank-/Auktionshaus-NPCs sprechen in Amtsdeutsch, das für die Fantasy-Welt leicht overengineered wirkt. | "Formular XVII-b: Ich bestätige hiermit den Eingang von 5 (fünf) Einheiten Eisenerz zwecks Weiterverarbeitung." |
| **Nicht meine Abteilung (Nest-Edition)** | Die Nest-NPCs (Gerlinde, Lian, Sigrun) verweisen bei Fragen zu einem fremden Nest-Typ an die jeweils zuständige Kollegin — wie ein kleines Amt, nur freundlicher. Verwandt mit dem Nornen-Beschwerde-Amt, aber ohne Frust. | Gerlinde (Bienen): "Wespen? Nicht meine Abteilung – frag Papiermeisterin Lian." Lian: "Hornissen? Frag Orakel Sigrun." Umgesetzt in `ZeidlerNPC.gd`/`PapermakerNPC.gd`/`HornetOracleNPC.gd` (siehe `docs/nests.md`). |
| **Der Ahnengeist mit Nachrichten-Rückstand** | Ahnengeister (afrikanische Ahnentradition als Vorbild) erteilen Aufgaben, wissen aber erkennbar nicht, wie viel Zeit vergangen ist ("ist der Krieg mit den Nachbardörfern schon vorbei?"). | Ein Ahnengeist erwähnt eine längst vergessene Fehde als aktuelles Problem. Umgesetzt in `AncestorSpiritNPC.gd` (Ahnengeist Babatunde, Yoruba-Egungun-Tradition, `quest_babatunde_tale`/`_legacy`): hält eine seit drei Generationen beigelegte Dorf-Fehde für aktuell. |
| **Der Schüler, der schneller sein will als die Prüfung erlaubt** | Asiatische Meister/Schüler-Tradition: Ein Meister-NPC verweigert Abkürzungen konsequent, mit ruhiger Ironie statt Wut. | "Du hast Stufe 3 erreicht in der Zeit, die andere für Stufe 1 brauchen. Das ist kein Kompliment." Umgesetzt in `WudangMasterNPC.gd` (Kampfmeisterin Wei, `quest_wei_mastery`): "Stufe 2 in halber Zeit? Kein Kompliment. Zeig mir Stufe 4 — richtig geübt." |

**Regel für neue Gags:** Maximal 1–2 Sätze pro Auftreten, nie erklärend ("das war jetzt ein
Insider-Witz über X"), nie zweimal im selben Dialog. Der Gag muss auch funktionieren, wenn die
Person die referenzierte Mythologie **nicht** kennt — er darf ein Extra-Lacher für Kenner sein,
aber kein Rätsel für alle anderen.

---

## 4. Figuren-Archetypen pro Kulturkreis (Startpunkte, kein Zwang)

Diese Tabelle ist ein Steinbruch für neue NPCs — sie legt fest, welche mythologische
**Funktion** eine Figur erfüllt, nicht ihren genauen Namen oder ihr Aussehen.

| Kulturkreis | Archetyp | Spielmechanischer Anknüpfungspunkt | Sprachlicher Tonfall |
|---|---|---|---|
| Nordisch/Germanisch | Wanderndes Orakel/Rune-Ritzer | CUSTOM-Trigger, Lore-Erkundung | Karg, wettergegerbt, trockener Humor |
| Römisch | Grenz-/Zollbeamter, Legionsveteran | Bank/Shop/Auktionshaus, Handel | Formell, Amtsdeutsch, unerschütterlich |
| Griechisch | Orakel, Sophist, gefallener Held | Quest-Abschluss-Flavor, Rätsel-Objectives | Kryptisch, dozierend, leicht überheblich |
| Orientalisch (Region konkret nennen) | Wüstenhändler, Geschichtenerzähler:in, Dschinn | Foraging/Handel in Wüsten-Biom (Kaktus etc.) | Blumig, gastfreundlich, verhandlungsfreudig |
| Asiatisch (Region konkret nennen) | Kampf-/Handwerksmeister:in, Naturgeist | SKILL-Objectives, Prüfungsketten | Ruhig, sparsam, sentenzhaft |
| Afrikanisch (Region/Tradition konkret nennen) | Ahnengeist, Trickster, Dorfälteste:r | TALK-/CUSTOM-Objectives, mündliche Questgabe | Erzählerisch, warm, mit Seitenhieben |

**Beide vorherigen Lücken sind jetzt gefüllt** (siehe Tabelle in Abschnitt 1): Kampfmeisterin
Wei (`WudangMasterNPC.gd`) und Ahnengeist Babatunde (`AncestorSpiritNPC.gd`). Babatundes Kette
nutzt dabei zwei `TALK`-Objectives auf Erik/Mira statt des ursprünglich vorgeschlagenen
CUSTOM-Triggers — siehe Warnung direkt unten.

⚠️ **CUSTOM-Objectives aktuell mit Vorsicht einsetzen:** `QuestCustomTrigger` (Area3D) wird
im laufenden World-Setup nirgends instanziiert (nur in Tests referenziert) — ein CUSTOM-
Objective ohne manuell in `World.tscn`/`WorldSpawner` platzierten Trigger ist unsichtbar/
unerreichbar, genau wie es `quest_erik_friendship.obj_explore_camp` aktuell schon ist. Vor
dem Einsatz von CUSTOM entweder selbst einen Trigger verdrahten (siehe
`QuestCustomTrigger.gd` Klassenkommentar für die Einbindung) oder auf TALK/SKILL/INTERACT
ausweichen.

---

## 5. Technischer Ablauf — vom Konzept zur `.tres`-Datei

Die Kreativ-Ebene (Abschnitt 1–4) und die Daten-Ebene sind strikt getrennt — genau wie überall
sonst im Projekt (siehe `docs/principles.md`). Ablauf für eine neue Quest:

### 5.1 Konzept festlegen
- Kulturkreis + konkrete Tradition wählen (Abschnitt 1/4)
- Mind. 1 Running Gag oder neuer Gag nach demselben Muster einbauen (Abschnitt 3)
- Prüfen: Passt die Quest zu einer **bestehenden** Spielmechanik (`QuestObjective.Type`:
  `COLLECT`/`SKILL`/`INTERACT`/`KILL`/`TALK`/`CUSTOM`)? Neue Mechanik = eigenes Ticket, keine
  Quest-Aufgabe.

### 5.2 Quest-Kette planen
- Solo-Quest oder 2-stufige Kette? Seit ADR-051 Stufe 3 (2026-09-27) laufen **alle** NPCs über
  `DialogueTreeController` statt des alten Slot-Systems — siehe `MinerNPC.gd`/`HerbalistNPC.gd`
  als Referenz für den Standardfall (`DialogueTreeController.build_quest_giver()`, unterstützt
  genau wie vorher eine Quest oder eine feste 2-Stufen-Kette aus denselben Parametern).
  Für mehr als 2 Stufen oder mehrere UNABHÄNGIGE Themen am selben NPC (z.B. Talia:
  "Der Dieb im Pelz" + "Friedhofswache" gleichzeitig) den Baum von Hand bauen statt der
  Factory — siehe `GuardNPC.gd` für das Muster (mehrere Unter-Router unter einem gemeinsamen
  Themen-Menü).
- Ein NPC kann jetzt außerdem auf den Status einer **fremden** Quest reagieren
  (`"quest_completed:<id>"` etc. als `condition` an `add_choice()`) — siehe `VillageElderNPC.gd`.
  Das lohnt sich nur für echte Querverweise zwischen Geschichten, nicht als Standard.
- IDs konsequent benennen: `quest_<npc-thema>_<beschreibung>`, Objective-IDs `obj_<verb>_<ziel>`.

### 5.3 Schnellweg: `quest_npc_scaffold.py` — Quest + NPC in einem Schritt

Für den Standardfall (Solo-Quest oder feste 2-Stufen-Kette, ein NPC) automatisiert dieses Tool
5.3+5.4 zusammen: es ruft `content_forge.py` für die Quest(s) intern selbst auf UND generiert die
passende `_build_dialogue_tree()`-NPC-Datei nach dem `build_quest_giver()`-Muster — siehe
Moduldoc in `scripts/agent/build/quest_npc_scaffold.py` für die Spec-Feldreferenz.

```bash
# Dry-Run zeigt Quest-Diff(s) UND den vollen generierten NPC-Dateitext
python3 scripts/agent/build/quest_npc_scaffold.py --spec meinen_npc.json

# Erst wenn das wie erwartet aussieht → tatsächlich schreiben
python3 scripts/agent/build/quest_npc_scaffold.py --spec meinen_npc.json --apply
```

**Spec-Vorlage** (eine Quest, optional `stage2` für eine Kette):

```json
{
  "npc_id": "beispiel_npc",
  "npc_class_name": "BeispielNPC",
  "npc_display_name": "Anzeigename im Spiel",
  "body_color": [0.3, 0.3, 0.35],
  "culture_note": "Ein Satz Kontext für den Klassenkommentar (optional).",
  "spawn": { "x": 32.0, "z": -9.0 },
  "stage1": {
    "id": "quest_beispiel_thema",
    "title": "Kurzer, einprägsamer Titel",
    "description": "Ein bis zwei Sätze In-World-Kontext.",
    "objectives": [
      { "id": "obj_verb_ziel", "label": "Anzeige-Text", "type": "COLLECT", "target_id": "item_id", "required": 3 }
    ],
    "reward_xp": { "skill_name": 20 },
    "tracked_obj_id": "obj_verb_ziel",
    "tracked_required": 3,
    "offer_text": "Was der NPC beim Anbieten sagt.",
    "encourage_format": "Fortschritt: %d/%d.",
    "completed_text": "Was der NPC nach Abschluss sagt."
  }
}
```

Das Tool druckt am Ende die zwei Zeilen, die danach noch VON HAND in
`WorldEntityRegistry.gd`/`WorldSpawner.gd` ergänzt werden müssen (bewusst nicht automatisiert —
siehe Moduldoc dort: kein stabiler Texanker in diesen beiden, häufig von anderer Seite
gleichzeitig bearbeiteten Dateien).

Für alles, was über den Standardfall hinausgeht (mehrere unabhängige Themen, Reaktion auf
fremde Quests, mehr als 2 Stufen) bleibt Handarbeit nach dem Muster aus `GuardNPC.gd`/
`VillageElderNPC.gd` nötig — das Tool deckt bewusst nur den häufigen Fall ab.

### 5.4 Daten einzeln mit `content_forge.py` erzeugen (Handarbeit / Spezialfälle)

Wenn `quest_npc_scaffold.py` nicht passt (z.B. Quest ohne neuen NPC, oder ein bestehender NPC
bekommt eine weitere Quest dazu wie bei Talia/Rasmus) — NIEMALS `.tres` von Hand tippen:

```bash
# Schema ansehen, falls Felder unklar sind
python3 scripts/agent/build/content_forge.py schema quest

# Vorhandene IDs prüfen (Kollisionen vermeiden)
python3 scripts/agent/build/content_forge.py list quest

# Spec schreiben (siehe Vorlage unten), dann validieren
python3 scripts/agent/build/content_forge.py validate --spec meine_quest.json

# Erst wenn "ok": true → tatsächlich schreiben + Manifest registrieren
python3 scripts/agent/build/content_forge.py create --spec meine_quest.json --apply
```

**Spec-Vorlage** (ein Objekt pro neuer Quest, siehe `QuestReward.gd`/`QuestObjective.gd` für
Feldbedeutung):

```json
{
  "type": "quest",
  "fields": {
    "id": "quest_beispiel_thema",
    "title": "Kurzer, einprägsamer Titel",
    "description": "Ein bis zwei Sätze In-World-Kontext.",
    "category": "side",
    "objectives": [
      { "id": "obj_verb_ziel", "label": "Anzeige-Text", "type": "COLLECT", "target_id": "item_id", "required": 3 }
    ],
    "reward_xp": { "skill_name": 20 },
    "reward_items": {},
    "prerequisites": [],
    "auto_start": false,
    "repeatable": false
  }
}
```

⚠️ **Wichtig, weil schon einmal schiefgegangen:** `content_forge.py create --apply` trägt die
neue Datei automatisch in `DataManifest.QUESTS` ein. Wird die Quest stattdessen von Hand
angelegt, **wird sie ohne manuellen Manifest-Eintrag nie geladen** (`DataService._load_quests()`
liest ausschließlich aus `DataManifest.QUESTS`, kein Verzeichnis-Scan — siehe Klassenkommentar
dort). Das war genau der Bug, der `quest_erik_friendship`, `quest_miner_defense` und
`quest_woodcutter_master` unsichtbar gemacht hat, bevor er behoben wurde.

### 5.5 NPC anlegen (falls neu, und `quest_npc_scaffold.py` nicht passt)
- Neue Klasse `extends QuestNPC` in `scripts/progression/quests/`, Muster: `MinerNPC.gd`
  (`_build_dialogue_tree()` + `DialogueTreeController.build_quest_giver()`)
- Eigene `_get_body_color()` für Wiedererkennbarkeit
- In `WorldEntityRegistry.register_all()` registrieren
- In `WorldSpawner.spawn_all()` an einer freien Position spawnen lassen (nicht mit
  bestehenden NPCs überlappen — siehe Kommentare dort zu den bereits belegten Koordinaten)

### 5.6 Checkliste vor dem Commit

- [ ] Kulturkreis + konkrete Tradition benannt, keine Pauschal-Exotisierung
- [ ] Mindestens ein Running Gag oder neuer Gag nach dem Muster aus Abschnitt 3
- [ ] Dialogtexte kurz genug für `Label3D` (Faustregel: 3 Zeilen à ~25 Zeichen)
- [ ] `content_forge.py validate` lief ohne Fehler, bevor `--apply` genutzt wurde (entfällt bei
      `quest_npc_scaffold.py` — ruft dieselbe Validierung intern auf)
- [ ] Neue IDs folgen der Namenskonvention (`quest_…`, `obj_…`, `npc_id` in snake_case)
- [ ] NPC (falls neu) in `WorldEntityRegistry` **und** `WorldSpawner` verdrahtet
- [ ] Neuer Running Gag in Abschnitt 3 dieser Datei ergänzt, falls einer erfunden wurde
- [ ] Offene Kulturkreis-Lücken (Abschnitt 1) aktualisiert, falls eine davon bedient wurde

---

## 6. Ideen-Backlog (unverbindlich, zum Weiterspinnen)

- **Nornen-Beschwerdeamt als eigener NPC:** Kein Quest-Geber, sondern reiner Flavor-NPC in
  Bank-/Auktionshaus-Nähe, der auf Zuruf (`sendPrompt`-artige Interaktion) absurde
  Amtsvorgänge zu Schicksalsfragen erzählt.
- **Wettbewerb zwischen Mira (nordisch/Bergbau) und einem noch zu schreibenden
  Wüstenhändler:** Beide behaupten, ihr Erz/ihre Ware sei die eigentliche Grundlage von
  Wohlstand — leichte Running-Gag-Rivalität über mehrere Quests hinweg, ohne dass Spieler:in
  Partei ergreifen muss.
- **Ein Fluch, der von KEINER Kultur beansprucht wird:** Alle mythologischen NPCs schieben ihn
  sich gegenseitig zu ("nicht meiner, frag den Ahnengeist" / "nicht meiner, frag die Nornen").
  Guter Rahmen für eine spätere Multi-NPC-CUSTOM-Trigger-Quest.
