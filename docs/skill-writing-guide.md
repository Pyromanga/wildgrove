# WildGrove — Skill-Writing-Guide

> **Zielgruppe:** Jede Person (menschlich oder Agent), die einen neuen Skill anlegt oder die
> Beschreibung eines bestehenden Skills überarbeitet.
> **Kurzfassung:** Ein Skill ist technisch **eine einzige `.tres`-Datei** (`SkillDefinition.gd`) plus
> ein Manifest-Eintrag. Kreativ ist er ein **Fenster in die echte Welt**: Jeder Skill erzählt ein
> Stück Magie *und* ein Stück Wahrheit — für Kinder zum Staunen, für Erwachsene zum Nachschlagen.
> Ergänzt `docs/quest-writing-guide.md` (Ton, Kulturkreise) — dessen Ton-Regeln gelten hier weiter.
>
> **Stand:** Alle 12 Skills tragen bereits die Zwei-Ebenen-`description`. Die fünf **Hain-Skills**
> (Sturmkunde, Imkerei, Sternkunde, Alchemie, Köhlerei) sind samt Weltobjekt, Loot, Biom-Spawn und
> Respawn umgesetzt — sie dienen als lebende Vorlage für Abschnitt 5.

---

## 1. Die Grundidee: Der Elektro-Hain

WildGrove ist ein **mittelalterlicher Zauberwald, der unter Strom steht**. Die Wurzeln des Hains
laufen wie Leiterbahnen durch den Boden und glimmen grün, wenn jemand etwas Sinnvolles tut. Mana
heißt hier **Lebensstrom**. Skills sind die **Runenschaltkreise**, die er speist: Je öfter du
etwas übst, desto heller leuchtet dein Schaltkreis.

Drei Zutaten, die sich mischen dürfen:

| Zutat | Vokabular zum Bedienen |
|---|---|
| **Mittelalter** | Zunft, Gilde, Meister:in, Lehrling, Grimoire, Skriptorium, Wegzoll, Handwerkerbrief |
| **Magie** | Rune, Bann, Wurzelgeist, Flüstern, Siegel, Lebensstrom, alte Namen |
| **Elektro-Grün** | Funken, Knistern, Glimmen, Leiterbahn-Wurzeln, Kupferadern, Schaltkreis, Spannung, „es summt" |

**Farb-Anker (schon im Projekt vorhanden — nichts Neues erfinden):**

| Zweck | Wert | Fundstelle |
|---|---|---|
| Elektro-Grün (Akzent) | `Color(0.2, 0.8, 0.3)` ≈ `#33CC4D` | `UIUtils.COLOR_ACCENT` |
| Sanftes Rune-Grün (Text/Header) | `Color(0.6, 0.9, 0.6)` / `Color(0.5, 0.8, 0.5)` | `QuestPanelVisuals.gd` |
| Nacht-Untergrund | `Color(0.07, 0.07, 0.10, 0.94)` ≈ `#121219` | `SkillPanelVisuals.gd` |

**Ton-Regeln aus dem Quest-Guide gelten auch für Skills:** keine Popkultur-Referenzen, kein
Sarkasmus gegenüber den Spielenden, keine Ironie auf Kosten einer echten Kultur oder Religion.

---

## 2. Die Zwei-Ebenen-Regel: Magie + Wahrheit

Jede `description` besteht aus **genau zwei Teilen**, die man nie verwechseln kann:

```
[Spielfunktion im Magie-Ton.] Wusstest du? [Ein echter Fakt] (Fachwort).
```

- **Satz 1 (Magie):** Sagt, was der Skill im Spiel tut — verpackt in Hain-Stimmung. Darf erfunden sein.
- **„Wusstest du?" (Wahrheit):** Ein **echter, überprüfbarer** Fakt. Das feste Signalwort zeigt
  Kindern und Erwachsenen: *Ab hier ist es wirklich so.*
- **Fachwort in Klammern:** Suchbegriff für alle, die weiterlesen wollen (Erwachsene, neugierige Kinder).

**Beispiel — gut:**
> Erze und Steine aus dem Boden schlagen, wo grüne Funken durch die Adern tanzen. Wusstest du?
> Kupfer leitet Strom fast so gut wie Silber – darum bestehen Kabel meist aus Kupfer (Leitfähigkeit).

**Beispiel — schlecht** (Magie und Wahrheit vermischt, Fakt nicht überprüfbar):
> Kupfererz macht deine Waffen elektrisch geladen und heilt Müdigkeit.

Der Fehler: Erfundenes steht im selben Satz wie Echtes, und ein Kind kann nicht mehr trennen.

---

## 3. Bildungs-Regeln (damit „lehrreich" auch stimmt)

| Regel | Warum |
|---|---|
| **Ein Fakt pro Skill**, ein Satz, überprüfbar | Ein Fakt bleibt hängen; drei verpuffen. |
| **Zwei unabhängige, seriöse Quellen** (Museum, Universität, Behörde, Fachlexikon) vor der Übernahme | Wir lehren — also muss es stimmen. |
| **Strittige Forschung als strittig markieren** („Forschende vermuten …", nicht „ist so") | Ehrlichkeit ist selbst Bildung. |
| **Keine Pseudowissenschaft als Fakt** (Kristallheilung, Homöopathie, „Heilkräuter heilen X") | Magie ist markierte Fiktion, kein Gesundheitsrat. Betrifft besonders Kräuter-/Sammel-Skills. |
| **Erklären, *warum* — nie *wie man es gefährlich nachmacht*** | Kinder lesen mit. Bei Pilzen, Gewitter, Waffen, Diebstahl: Schutz-Hinweis statt Anleitung. |
| **Kinder-tauglicher Kern, Erwachsenen-Tiefe im Fachwort** | Ein Text, zwei Leseebenen. Satzlänge des Fakts: max. ~25 Wörter. |
| **Metrische Einheiten, keine ungeklärten Abkürzungen** | Ein Kind soll es auch ohne Vorwissen lesen können. |
| **Kulturen konkret benennen** (nicht „die Alten"/„der Orient") | Gleiche Sensibilität wie im Quest-Guide, Abschnitt 1. |
| **Richtwert Länge: ≤ ~250 Zeichen** | Das Wiki bricht Text um (`AUTOWRAP_WORD_SMART`); für das Skill-Panel ist kein Limit im Code verifiziert — Konvention, keine harte Grenze. |

---

## 4. Der Kanon: Fakten-Anker aller Skills

> **Status der Belege:** ✔ = gegen Quellen geprüft (siehe Spalte „Prüfung"), ☐ = aus Allgemeinwissen,
> **noch nicht** mit zwei Quellen belegt — vor einer Überarbeitung nachholen. Eine `description` zu
> ändern ist **sicher für Spielstände** (reine Anzeige) — anders als die `id` (Abschnitt 6).

**Bestehende Skills**

| `id` | Thema | Fakt (Kurzform) | Belegt? | Prüfung |
|---|---|---|---|---|
| `mining` | Metalle & Leitfähigkeit | Kupfer leitet Strom fast so gut wie Silber | ✔ | Nachschlagewerk-Artikel „Copper conductor": Silber ist nur ≈ 6 % besser (IACS-Skala) |
| `woodcutting` | Jahresringe | ~1 Ring pro Jahr, Ringbreite zeigt Dürrejahre | ☐ | Allgemeinwissen (Dendrochronologie) |
| `foraging` | Pilze & Myzel | Pilz = Frucht, Geflecht (Myzel) verbindet mit Wurzeln | ☐ | Allgemeinwissen; Umfang des „Nährstoff-Austauschs" in der Forschung umstritten — bewusst nicht behauptet |
| `farming` | Fruchtfolge & Stickstoff | Erbsen/Bohnen binden Luftstickstoff via Knöllchenbakterien | ☐ | Allgemeinwissen |
| `digging` | Erdschichten | In ungestörtem Boden liegt Älteres unten | ☐ | Allgemeinwissen (Stratigraphie) |
| `combat` | Mythos „Blechritter" | Plattenrüstung ≈ 20–25 kg, verteilt, frei beweglich | ✔ (Sekundärquelle) | 20–25 kg und „Mobilität war nicht eingeschränkt" stammen aus einem Museums-Faktenblatt, das Sekundärtexte zitieren; **das Original vor Übernahme direkt nachladen** |
| `pickpocketing` | Aufmerksamkeit & Schutz | Wer Auffälliges anstarrt, übersieht anderes | ☐ | Allgemeinwissen (Unaufmerksamkeitsblindheit) |

**Hain-Skills (neu, mit Weltobjekt)**

| `id` | Weltobjekt (`type_id`) | Biom(e) | Fakt (Kurzform) | Belegt? | Prüfung |
|---|---|---|---|---|---|
| `stormlore` Sturmkunde | Blitzglas (`fulgurite`) | Wüste | Blitz ≈ 5× heißer als die Sonnenoberfläche; schmilzt Sand zu Glas (Fulgurit) | ✔ | Erklärtexte u. a. UW-Madison SSEC und Weather.com: Blitz mehrfach heißer als die Sonnenoberfläche; Sand schmilzt bei ≈ 1.800 °C |
| `beekeeping` Imkerei | Wilder Bienenstock (`wild_beehive`) | Wiese, Wald | Schwänzeltanz zeigt Richtung + Entfernung | ✔ | Von Frisch (Nobelpreis 1973), Bestätigung u. a. per Radar-Studie in *Nature* |
| `stargazing` Sternkunde | Sternenstein (`meteorite`) | Gebirge, Schnee, Wüste | Meteoriteneisen-Klingen vor der Eisenverhüttung | ✔ | Studie zu Tutanchamuns Dolch (*Meteoritics & Planetary Science*, 2016) |
| `alchemy` Alchemie | Schwefelkruste (`sulfur_crust`) | Gebirge, Sumpf | Alchemisten *verfeinerten* Labormethoden wie Destillation | ✔ | Wissenschaftshistoriker-Aussagen (AIP/JSTOR Daily); „erfunden" wäre falsch — Destillation ist älter |
| `charcoal_burning` Köhlerei | Kohlenmeiler (`charcoal_kiln`) | Wald | Meiler: wenig Luft, Tage; Holzkohle brennt heißer als Holz | ✔ | Faktenblatt zur Holzkohleherstellung (Low Impact Living) + Nachschlagewerk-Artikel: Pyrolyse, wenig Sauerstoff, Erdmeiler ≈ Tage, brennt heißer als Holz |
| `herbalism` Kräuterkunde | Kräuter (`plant_chamomile`, `plant_yarrow`, `plant_nettle`, `plant_dandelion`, `plant_thyme`, `plant_meadowsweet`) | Wiese, Wald, Sumpf, Gebirge | Aspirin trägt den Namen des Mädesüß: A für Acetyl, spir für Spiraea | ✔ | Wörterbuch- und Hochschul-/Lexikon-Quellen zur Namensherkunft (Spiraea ulmaria → Aspirin); Einzelfakten je Pflanze: `docs/herbalism-and-gardening.md` |
| `gardening` Gartenkunde | Blumen (`plant_poppy`, `plant_cornflower`, `plant_calendula`, `plant_lavender`; Felder: + Sonnenblume, Tulpe) | Wiese, Gebirge | Nur junge Sonnenblumen folgen der Sonne, erwachsene blicken nach Osten (Heliotropismus) | ✔ | Studie in *Science* (2016, Atamian et al.) + Erklärtexte; Einzelfakten: `docs/herbalism-and-gardening.md` |
| `entomology` Insektenkunde | Nester: Ameisenhügel (`ant_hill`), Termitenhügel (`termite_mound`), Wespennest (`wasp_nest`), Hornissennest (`hornet_nest`); Maulwurfshügel (`mole_hill`) gibt `digging`-XP, der Bienenstock `beekeeping`-XP | Wald, Wiese, Wüste (Termiten), toter Wald (Hornissen) | Wespen kauen Holz zu Papierbrei; Réaumur kam um 1720 dadurch auf Papier aus Holz | ✔ | Zwei Naturkunde-/Museumstexte (Espace pour la vie: Beobachtung 1720; Universitäts-Radiosendung Engines of Our Ingenuity: Réaumur 1719). Einzelfakten je Nest: `docs/nests.md` |

**Bei moralisch grauen Skills** (`pickpocketing`, `combat`) erklärt der Fakt immer die
**Schutz-/Verstehens-Seite**, nie eine Ausführungs-Anleitung.

**Fach-Logik der Biome ist Teil der Bildung:** Blitzglas gibt es nur im Sand (Wüste), Meiler nur im
Wald, Sternensteine dort, wo dunkle Steine auffallen. Der Test `test_hain_biome_mapping_matches_real_world_logic`
hält das fest.

---

## 5. Technischer Ablauf — vom Konzept zur `.tres`-Datei

Wie bei Quests gilt: Kreativ-Ebene (Abschnitt 1–4) und Daten-Ebene sind getrennt. Ein Skill braucht
**keinen Code** — nur Daten, eine XP-Quelle und einen Manifest-Eintrag.

### 5.1 Konzept festlegen

- **`id`:** englisch, `snake_case`, klein, ohne Leerzeichen (wie `woodcutting`, `mining`). Sie ist
  gleichzeitig Dateiname, Save-Schlüssel und `xp_type`. **Anzeige-Text ist deutsch** (`display_name`).
- **Fakt + Quellen** festlegen (Abschnitt 3), **Magie-Satz** schreiben (Abschnitt 2).
- **XP-Quelle klären, bevor du die Datei anlegst.** Ein Skill ohne Quelle bleibt für immer auf
  Level 1. Was gibt schon XP dafür?
  ```bash
  grep -rn 'xp_type *= *"<skill_id>"' scripts/
  ```
  Direkte Aufrufe (Weg C) findest du mit `grep -rn request_add_xp scripts/`.
  **Neue Aktions-XP immer über `SkillSystem.add_action_xp()`** (nicht `request_add_xp()`): nur dort
  greift der Ausrüstungs-Bonus (`ItemDefinition.xp_bonus`). `request_add_xp()` bleibt für feste
  Belohnungen (Quests, Admin).
  Kommt nichts, ist das eine **neue Mechanik** → eigenes Ticket, keine Skill-Aufgabe.

### 5.2 Daten mit `content_forge.py` erzeugen — NIEMALS `.tres` von Hand tippen

```bash
python3 scripts/agent/build/content_forge.py schema skill     # Felder, Typen, Defaults
python3 scripts/agent/build/content_forge.py list skill       # vorhandene IDs + "registered_in_manifest"
python3 scripts/agent/build/content_forge.py validate --spec mein_batch.json
python3 scripts/agent/build/content_forge.py create   --spec mein_batch.json          # Dry-Run
python3 scripts/agent/build/content_forge.py create   --spec mein_batch.json --apply  # schreibt + registriert
```

Ein Skill mit Interaktion ist **eine Batch aus drei Typen** — Item, LootTable, Skill —, die sich
gegenseitig referenzieren dürfen (Cross-Referenzen werden gegen die ganze Batch geprüft). So wurde
Sturmkunde angelegt (gekürzt; Liste oder Einzelobjekt werden akzeptiert):

```json
[
  { "type": "item",
    "fields": { "id": "lightning_glass", "display_name": "Blitzglas", "max_stack": 99 } },

  { "type": "loot_table", "filename": "loot_fulgurite",
    "fields": { "max_rolls": 1,
      "entries": [ { "item_id": "lightning_glass", "weight": 100.0, "quantity_min": 1, "quantity_max": 1 } ] } },

  { "type": "skill",
    "fields": {
      "id": "stormlore",
      "display_name": "Sturmkunde",
      "description": "Blitzglas aus dem Wüstensand bergen, wo der Hain noch nachglimmt. Wusstest du? Ein Blitz ist mehrfach heißer als die Sonnenoberfläche – heiß genug, um Sand zu Glas zu schmelzen (Fulgurit). Such bei Gewitter nie Schutz unter einem einzelnen Baum.",
      "xp_to_level_up": [100, 220, 400, 650, 1000, 1450, 2000],
      "xp_scaling_factor": 1.2,
      "max_level": 50
    } }
]
```

**Zwei bewusste Abweichungen vom `--apply`-Standardverhalten:**
- **Ernte-LootTables nicht im Manifest lassen.** `--apply` trägt sie in `DataManifest.LOOT_TABLES` ein;
  Weltobjekte laden ihre Tabelle aber per `preload()` (Muster `loot_fern`, `loot_iron_ore`). Registrierte
  Tabellen erscheinen zusätzlich in der Wiki-Kategorie „drops". → Die Zeilen nach `--apply` wieder
  aus `LOOT_TABLES` entfernen (die `.tres` selbst bleibt).
- **`*.bak`-Sicherungen** (z. B. `Sulfur.tres.bak`) entstehen bei jedem `--apply` — vor dem Commit löschen bzw. prüfen.

### 5.3 XP-Quelle anbinden — drei Wege

| Weg | Wo | Beispiel im Projekt |
|---|---|---|
| **A. Interaktion / Ernte** | `InteractableData.xp_type = "<skill_id>"`, `xp_amount = N` → `InteractionResolver` emittiert `xp_gained` → `SkillSystem` | `IronOre.gd`: `mining`, 40 XP · `MapleTree.gd`: `woodcutting`, 60 XP |
| **B. Quest** | `reward_xp: {"<skill_id>": N}` in der Quest-Spec; **SKILL-Objective** mit `target_id = "<skill_id>"` prüft das *Level* | `docs/quest-writing-guide.md`, Abschnitt 5.3 |
| **C. Direktaufruf (Autorität)** | `SkillSystem.request_add_xp(skill_id, amount, player_id)` — **nur serverseitig/autoritativ** | `WorldService.gd`: `digging`, `DIG_XP = 10` · `PickpocketService.gd` (nutzt Konstante `SKILL_ID`) |

**Regeln:**
- Ein Client schickt **nie** selbst eine XP-Menge; `on_xp_add_confirmed()` verweigert Aufrufe auf
  Nicht-Autoritäten (Guard C-02).
- Bei Weg C: die Skill-ID als **Konstante** führen (wie `PickpocketService.SKILL_ID`), nicht als
  loses String-Literal — Tippfehler werden sonst erst zur Laufzeit sichtbar (Abschnitt 6).

**Weg A im Detail — neues Weltobjekt (`extends HarvestableEntity`).** Jedes Glied ist nur über Strings
verbunden; fehlt eines, passiert *nichts Lautes*. Alle sieben Stellen (Beispiel: `Fulgurite`):

| # | Stelle | Was |
|---|---|---|
| 1 | `scripts/world/objects/Fulgurite.gd` | 3 Methoden: `_get_entity_type_id()`, `_build_interactable_data()`, `_build_visuals()` (Muster `IronOre.gd`) |
| 2 | `WorldEntityRegistry.register_all()` | `orchestrator.register_definition("fulgurite", "res://…/Fulgurite.gd", "ores")` |
| 3 | `WorldEntityRegistry.KNOWN_PROP_TYPES` | Typ eintragen — sonst filtert `ChunkEntitySpawner` ihn **still** weg |
| 4 | `BiomeRegistry` (`prop_chances`) | Chance pro Biom, **ans Ende** des Dicts (die Reihenfolge ist die Rollreihenfolge; bestehende Typen behalten Priorität) |
| 5 | `WorldService.configure()` | `respawn.register_config("fulgurite", 600.0)` — ohne das ist jede Interaktion **einmalig** (Skill hätte bald keine XP-Quelle mehr) |
| 6 | `data/items/…` + `data/loot_tables/loot_fulgurite.tres` | Item im Manifest (`ITEMS`), LootTable per `preload()` im Objekt |
| 7 | `data/skills/stormlore.tres` | Skill im Manifest (`SKILLS`), `xp_type` des Objekts == Skill-`id` |

> **Beobachtung (nicht Teil dieses Auftrags):** In `WorldService.configure()` haben nach Code-Lage nur
> Bäume, Erze und Gegner (plus die fünf Hain-Objekte) eine `register_config()`. Farn, Pilze, Kaktus,
> Eiskristall, Fels, Kiefer und umgefallene Bäume haben keine — sie kommen nach dem Ernten vermutlich
> nicht wieder. Das sollte jemand bewusst entscheiden.

### 5.4 XP-Kurve wählen — und dabei etwas über Wachstum lernen

`SkillDefinition.get_xp_required(level)`: Für Level 1…N liest die Formel `xp_to_level_up[level-1]`.
**Darüber hinaus** gilt `letzter Wert × xp_scaling_factor ^ (Level − Tabellenlänge)`.
`max_level = -1` heißt unbegrenzt.

Nachgerechnet mit der Formel aus `SkillDefinition.gd` (Python-Nachbau, **nicht** in Godot gemessen):

| Kurve | Lv 1→2 | Lv 10→11 | Lv 20→21 | Lv 30→31 | Lv 50→51 |
|---|---:|---:|---:|---:|---:|
| **Standard** (10er-Tabelle, ×1,5) — `mining`, `woodcutting`, … | 100 | 6.500 | 374.822 | 21.614.168 | 71.872.660.086 |
| **`combat`** (`[100]`, ×1,15) | 100 | 351 | 1.423 | 5.757 | 94.231 |
| **`pickpocketing`** (`[1000]`, ×1,0, unbegrenzt) | 1.000 | 1.000 | 1.000 | 1.000 | 1.000 |
| **Hain-Skills** (7er-Tabelle bis 2.000, ×1,2, `max_level = 50`) | 100 | 3.455 | 21.398 | 132.494 | (Lv 49→50: 4.232.942) |

**Zum Nachdenken (Design-Beobachtung, keine Vorgabe):** Bei der Standardkurve kostet allein Lv 20→21
rund 9.400 Eisenerz-Ernten (à 40 XP). Das ist exponentielles Wachstum — dasselbe Prinzip wie beim
Zinseszins.

> **🔎 Lehrmoment „Regel der 72":** Wächst etwas um *p* % pro Schritt, verdoppelt es sich nach
> ungefähr **72 ÷ p** Schritten. `combat` wächst um 15 % pro Level → 72 ÷ 15 = **4,8** (exakt: 4,96)
> Level bis zur Verdopplung — und tatsächlich: Lv 10 → 351 XP, Lv 15 → 707 XP, Lv 20 → 1.423 XP.
> Das steckt auch in Bankzinsen und Bevölkerungswachstum. Taugt für einen Wiki-Eintrag oder einen
> Quest-Dialog eines römischen Verwaltungs-NPCs.

**Warum die Hain-Skills sanfter sind:** ×1,2 statt ×1,5 und Deckel bei Lv 50. Lv 20→21 kostet dort
rund 534 Meteorit-Untersuchungen (40 XP) statt der 9.400 Ernten oben — bewusst eine *Vorlage zum
Abgleichen*, keine Vorgabe für alte Skills.

**Faustregeln für neue Kurven:** Faktor 1,0 = linear (gut für „ewig üben"), 1,10–1,25 = spürbar
steiler Anstieg, 1,5 = ab etwa Lv 20 extrem teuer (siehe Tabelle). Immer eine Rechnung
„Level X ÷ XP pro Aktion = Anzahl Aktionen" beilegen.

### 5.5 Was von allein passiert (kein UI-Code nötig)

- **Neue Spielstände & bestehende Saves:** Ein neuer Skill erscheint automatisch mit Level 1 / 0 XP
  (`_init_player_skills` legt alle geladenen Definitionen an, der Save überschreibt nur bekannte).
- **Skill-Panel:** `SkillPanelController` iteriert über `get_skill_ids()`.
- **Wiki (Kategorie „skills"):** Der Eintrag wird beim **ersten XP-Gewinn** entdeckt
  (`skill_changed` → `WikiService.discover`) und zeigt `display_name`, `description`, `max_level`.
  → Die `description` ist **die** Bühne für den Bildungsauftrag.
- **`icon`:** Das Feld existiert, ist aber in keinem vorhandenen Skill gesetzt und wird von Skill-Panel
  und Wiki-UI nach aktuellem Stand **nicht ausgewertet** — keine Zeit in Icons stecken, bis eine UI sie nutzt.

### 5.6 Testen

`tests/unit/test_hain_skill_content.gd` (GUT) macht die stillen Lücken laut — **er läuft für jeden
Skill mit, nicht nur für die Hain-Skills**:

| Test | Fängt |
|---|---|
| `test_every_skill_tres_file_is_registered_in_manifest` | `.tres` ohne Manifest-Eintrag (der `digging`-Fall) |
| `test_every_manifest_skill_loads_with_unique_id` | Ladefehler, doppelte `id`, Dateiname ≠ `id` |
| `test_skill_descriptions_follow_two_layer_rule` | `description` ohne „Wusstest du?" |
| `test_hain_objects_xp_type_is_a_registered_skill` | Tippfehler im `xp_type` |
| `test_hain_objects_loot_items_are_registered` | LootTable verweist auf nicht registriertes Item |
| `test_known_prop_types_are_all_registered_in_register_all` | `KNOWN_PROP_TYPES` ≠ `register_all()` |
| `test_hain_types_spawn_in_at_least_one_biome` | Objekt, das nirgends spawnt |
| `test_hain_types_have_respawn_config` | fehlende `register_config()` |
| `test_hain_skill_xp_curve_is_positive_and_monotonic` | kaputte XP-Kurve |

Neues Weltobjekt? → Eintrag in `HAIN_OBJECTS` ergänzen (eine Zeile), dann prüft der Test alle sieben
Stellen aus 5.3.

Lauf: `make test-gd` (braucht ein Godot-Binary, siehe `make godot-check`). Zusätzlich ohne Godot:
`content_forge.py list skill` — **jede Zeile muss `registered_in_manifest: true` zeigen.**

> **Ehrlicher Stand:** Dieser Test wurde ohne Godot-Binary geschrieben (nur mit dem
> `check_gdscript_syntax.py`-Heuristik-Check und einem Python-Nachbau der Konsistenzprüfungen geprüft).
> Einmal `make test-gd` laufen lassen, bevor er als „grün" gilt.

---

## 6. Stolpersteine (alle schon einmal passiert oder im Code belegt)

| Stolperstein | Folge | Vorbeugung |
|---|---|---|
| **`.tres` angelegt, aber nicht in `DataManifest.SKILLS` eingetragen** | Skill wird nie geladen; `request_add_xp` loggt „Unbekannter Skill" und **verwirft die XP still**. Laut Manifest-Kommentar landen nicht registrierte Ressourcen zudem nicht im Android-APK. | `content_forge.py create --apply` nutzen; `list skill` prüfen; GUT-Test 5.6. |
| **`id` nachträglich umbenannt / Skill gelöscht** | Save-Einträge werden mit „Veralteter Skill im Save … übersprungen" **verworfen — Fortschritt weg**. | `id` ist ein Vertrag mit den Spielständen. Nur `display_name`/`description` ändern. |
| **Tippfehler im `xp_type`** (z. B. `"digging "`) | Die Ernte läuft normal, aber `SkillSystem.request_add_xp` verwirft die XP mit der Warnung „Unbekannter Skill". Kein Absturz — genau deshalb fällt es nicht auf. | Konstante statt Literal; Test aus 5.6; im Log nach „Unbekannter Skill" suchen. |
| **Weltobjekt ohne `register_config()`** | Genau einmal erntbar; danach ist der Skill ohne XP-Quelle. | Punkt 5 der Tabelle in 5.3; Test `test_hain_types_have_respawn_config`. |
| **Typ nicht in `KNOWN_PROP_TYPES`** | `ChunkEntitySpawner` filtert ihn **still** — das Objekt spawnt nirgends. | Punkt 3 in 5.3; Test `test_hain_types_are_known_prop_types`. |
| **Ernte-LootTable im Manifest gelassen** | Taucht zusätzlich als „drop" im Wiki auf. | Abschnitt 5.2, Abweichung 1. |
| **Kein Verzeichnis-Scan** | Neue Dateien allein reichen nie (Godot-PCK erlaubt kein `DirAccess` zur Laufzeit). | Manifest ist die einzige Wahrheit. |
| **Fakt nicht belegt / vermischt mit Magie / zu absolut** („erfunden" statt „verfeinert") | Wir lehren Falsches. | Abschnitt 2 + 3, Spalte „Belegt?" in Abschnitt 4. |

### Fallbeispiel: der vergessene `digging`-Skill (behoben)

`data/skills/digging.tres` existierte, `WorldService` vergibt pro Grabvorgang `DIG_XP = 10` über
`request_add_xp("digging", …)` — **aber `digging.tres` fehlte in `DataManifest.SKILLS`.** Das Graben
selbst funktionierte; nur der **Skill** war unbekannt, die XP verpufften mit der Warnung
„Unbekannter Skill: 'digging'", und der Wiki-Eintrag wurde nie entdeckt. `content_forge.py list skill`
zeigte genau das (`"registered_in_manifest": false`).

**Fix** (einer der seltenen legitimen Handgriffe, weil die Datei schon existierte): eine Zeile in
`scripts/persistence/DataManifest.gd` — `"res://data/skills/digging.tres",`. Bestehende Spielstände sind
nicht betroffen (`digging` erscheint dort mit Level 1). **Regression-Schutz:**
`test_every_skill_tres_file_is_registered_in_manifest` schlägt künftig an.

---

## 7. Checkliste vor dem Commit

**Inhalt**
- [ ] `id` englisch, `snake_case`, eindeutig (`content_forge.py list skill`)
- [ ] `description` folgt der Zwei-Ebenen-Regel: **Magie-Satz + „Wusstest du?" + Fachwort**
- [ ] Fakt mit **zwei seriösen Quellen** belegt; in Abschnitt 4 eingetragen (Spalte „Belegt?" + „Prüfung")
- [ ] Kein Pseudo-Fakt, kein Gesundheitsrat, bei Risiko-Themen ein **Schutz-Hinweis**
- [ ] Länge ≤ ~250 Zeichen, keine Popkultur, kein Sarkasmus
- [ ] Fach-Logik der Biome stimmt (Blitzglas nur im Sand, Meiler im Wald …)

**Technik**
- [ ] `content_forge.py validate` ohne Fehler, danach `--apply`
- [ ] Ernte-LootTables wieder aus `LOOT_TABLES` entfernt, `*.bak` gelöscht
- [ ] Alle **sieben Stellen** aus 5.3 (Klasse, `register_all`, `KNOWN_PROP_TYPES`, Biom, Respawn, Item/Loot, Skill)
- [ ] `xp_type` == Skill-`id`, exakt
- [ ] `list skill`: **alle** Skills `registered_in_manifest: true`
- [ ] XP-Kurve mit Rechnung „Aktionen bis Level X" begründet
- [ ] `HAIN_OBJECTS` im Test ergänzt · `make test-gd` grün

---

## 8. Ideen-Backlog (unverbindlich — jede braucht eine eigene XP-Mechanik = eigenes Ticket)

Umgesetzt sind: Sturmkunde, Imkerei, Sternkunde, Alchemie, Köhlerei (Abschnitt 4). Noch offen:

| Idee (`id`) | Elektro-Hain-Aufhänger | „Wusstest du?"-Kandidat (**vorher belegen!**) | Mechanik-Bedarf |
|---|---|---|---|
| **Schmieden** (`smithing`) | Glut schaltet von Rot über Orange zu Weißglut | Schmiede erkennen an der Glühfarbe die Temperatur des Eisens (Glühfarben / Wärmestrahlung) | Amboss-/Esse-Station mit Crafting — Holzkohle + Meteoriteisen aus den Hain-Skills wären die natürlichen Zutaten |
| **Wetterkunde** (`weatherlore`) | Der Hain spürt Druckwechsel | Luftdruckfall kündigt oft schlechtes Wetter an (Barometer) | Anbindung an `WeatherService` |
| **Höhlenkunde** (`speleology`) | Grüne Adern leuchten im Fels | Tropfsteine wachsen nur Bruchteile eines Millimeters pro Jahr (Speläothemen) | Nutzt `scenes/caves/` |

**Kulturkreis-Bezug:** Wer einen dieser Skills mit einem NPC verknüpft, wählt dafür — wie im
Quest-Guide — **eine konkrete Tradition** und eine **Funktion**, keine Deko.

**Quests:** Die neuen Skills sind über `SKILL`-Objectives (`target_id = "<skill_id>"`) und
`reward_xp` sofort in Quests nutzbar — z. B. ein Kohlenmeiler-Auftrag von Mira (nordisch/Handwerk).

---

## 9. Ausbau-Ticket (nur Idee, nicht Teil dieses Guides)

Aktuell muss der Fakt in `description` stecken, weil `SkillDefinition` nur diese Textfläche bietet.
Ein eigenes Feld `real_world_fact: String` (plus Wiki-Anzeige als „Wusstest du?"-Kasten) würde
Magie und Wahrheit **technisch** trennen und Fakten einzeln prüfbar machen. Das wäre eine
Schema-Änderung (`SkillDefinition.gd`, `content_forge.py` `SCHEMAS`, Wiki-UI) → **eigenes Ticket**,
vorher besprechen.
