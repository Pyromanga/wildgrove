# Kräuterkunde (`herbalism`) und Gartenkunde (`gardening`)

Zwölf echte Pflanzen, eine Tabelle: `scripts/world/plants/PlantCatalog.gd`. Daraus lesen wilde Weltobjekte (`WildPlant`), Felder (`FarmCropDefinition`), Shop und Tests.

## Pflanzen, Fakten, Belege

Regeln: ein Fakt, ein Satz, kein Gesundheitsrat (`docs/skill-writing-guide.md`, Abschnitt 3). ✔ = zwei Quellen geprüft, ☐ = Allgemeinwissen, **Quelle vor Übernahme in Marketing/Wiki nachholen**.

| Pflanze (`id`) | Skill | Wächst wild in | Fakt (Kurzform) | Belegt? |
|---|---|---|---|---|
| Kamille (`chamomile`) | herbalism | Wiese | Kamillenöl ist blau, der Farbstoff Chamazulen entsteht erst beim Destillieren | ✔ Fachlexika |
| Schafgarbe (`yarrow`) | herbalism | Wiese, Gebirge | Gattungsname Achillea geht auf Achilles zurück (Sage) | ☐ |
| Brennnessel (`nettle`) | herbalism | Wald, Sumpf | Nesselstoff als Baumwollersatz im Ersten Weltkrieg | ✔ Deutsches Historisches Museum u. a. |
| Löwenzahn (`dandelion`) | herbalism | Wiese, Wald | Russischer Löwenzahn liefert Naturkautschuk | ☐ |
| Thymian (`thyme`) | herbalism | Gebirge, Wiese | Thymol hemmt Keime, steckt in Mundspülungen | ☐ |
| Mädesüß (`meadowsweet`) | herbalism | Sumpf, Wiese | Name „Aspirin“: A + spir(Spiraea) | ✔ Wörterbuch + Hochschulquellen |
| Klatschmohn (`poppy`) | gardening | Wiese | Samen überdauern Jahrzehnte im Boden | ☐ |
| Kornblume (`cornflower`) | gardening | Wiese | Ackerwildkraut, heute vielerorts selten | ☐ |
| Ringelblume (`calendula`) | gardening | Wiese | „Safran des armen Mannes“, essbar | ☐ |
| Lavendel (`lavender`) | gardening | Gebirge | Lippenblütler wie Thymian und Salbei | ☐ |
| Sonnenblume (`sunflower`) | gardening | nur Feld | Nur junge Pflanzen folgen der Sonne | ✔ *Science* 2016 + Erklärtexte |
| Tulpe (`tulip`) | gardening | nur Feld | Preisblase 1636/37, Ausmaß unter Historikern umstritten | ☐ |

Habitat-Logik: Mädesüß feucht (Sumpf), Thymian/Lavendel trocken-felsig (Gebirge), nichts in Schnee und Wüste. Die Farben der dekorativen Wiesenblumen (`BiomeDefinition.flower_colors`) stehen für echte Arten, ihre Form ist stilisiert.

## Ablauf im Spiel

1. **Wild sammeln:** `WildPlant` (10 Arten, Entity-Typ `plant_<id>`), 1,5 s, XP in den Skill der Pflanze, 240 s Nachwachszeit. Loot: Ernte-Item, selten Samen.
2. **Samen:** Shop (`ShopService.BUY_CATALOG`, Preise aus dem Katalog) oder seltener Wildfund.
3. **Felder:** 12 `FarmPlot`s im Dorf (`WorldSpawner`): Kräuter-Reihe z = 6,5, Blumen-Reihe z = 10. Ernte gibt 2–4 Items und XP in den Skill der Pflanze.

## Neue Pflanze hinzufügen

1. Eintrag in `PlantCatalog.PLANTS`.
2. Daten mit `content_forge.py`: Ernte-Item, Samen-Item (danach `plants_crop_id` ergänzen), LootTable `loot_<id>_field` (ins Manifest) und bei wilden Pflanzen `loot_plant_<id>` (nicht ins Manifest), Crop `data/crops/<id>.tres`.
3. Wild: Skript `Plant<Id>.gd` (4 Zeilen), `WorldEntityRegistry` (Registrierung + `KNOWN_PROP_TYPES`), `BiomeRegistry` (Chance ans Ende). Der Respawn läuft automatisch.
4. `test_plants_content.gd` läuft über den Katalog und meldet fehlende Glieder.

## Roadmap („schrittweise“)

- **Jetzt:** Wissen (Untersuchen-Text, Skill-Beschreibung) + Sammeln + Felder.
- **Nächster Schritt:** Zutaten für Alchemie-Rezepte (z. B. Nesselfaser → Seil, Kamille/Thymian → Aufgüsse) über das vorhandene Rezeptsystem.
- **Danach:** verbrauchbare Items mit Effekt — braucht ein neues „Benutzen“-System (heute gibt es keins).
- **Felder:** baubares Beet mit freier Samenwahl (`FarmPlot` hat heute fest eine `crop_id`) ersetzt die festen Dorf-Felder.
- Nicht aufgenommen: Pflanzen mit gefährlichen Wirkstoff-Wechselwirkungen (z. B. Johanniskraut) — erst mit passendem Schutz-Hinweis.

## Sträucher: Pflücken + Roden (2026-10-08)

Vier wilde Sträucher (`BushCatalog`, Entity-Typ `bush_<id>`, Basis `WildBush`) — jeder bietet **zwei Aktionen** auf einer Entity:

| Aktion | Dauer | Skill | Tempo-Stat | Ertrag |
|---|---|---|---|---|
| **Pflücken** (`pick_<id>`) | 1,6 s | foraging | – (kein Werkzeug) | 2–5 Früchte/Nüsse |
| **Roden** (`chop_<id>`) | 2,5 s | woodcutting | `gathering_speed_wood` (Axt-Bonus wie bei Bäumen) | 2–4 Reisig bzw. Haselruten |

| Strauch (`id`) | Wächst in | Pflücken | Roden | Fakt (Kurzform) | Belegt? |
|---|---|---|---|---|---|
| Brombeere (`blackberry`) | Wald, dichter Wald, Wiese, Sumpf | Brombeeren | Reisig | Botanisch keine Beere, sondern Sammelsteinfrucht | ☐ |
| Haselnuss (`hazel`) | Wald, dichter Wald, Wiese | Haselnüsse | Haselruten | Ruten biegsam genug für Flechtzäune und Körbe | ☐ |
| Holunder (`elder`) | Wald, dichter Wald, Sumpf | Holunderbeeren | Reisig | Rohe Beeren leicht giftig, erst Erhitzen macht sie genießbar | ☐ |
| Heckenrose (`dogrose`) | Wald, Wiese, Gebirge | Hagebutten | Reisig | Hagebutten enthalten mehr Vitamin C als Zitronen | ✔ ZDFheute, Berliner Zeitung, Payback-Ratgeber |

- **Beide Aktionen verbrauchen den Strauch** (Despawn, Nachwachsen nach `BushCatalog.RESPAWN_SEC` = 480 s) — wie Farn und Pilz. Ein Strauch, der nach dem Pflücken stehen bleibt und nur die Früchte nachwachsen lässt, braucht ein Netzwerk-Event für den Zustand; bewusst offen.
- **Dekosträucher** (MultiMesh, `bush_per_chunk`) bleiben als Füllmaterial, wurden aber etwa halbiert; die erntbaren Sträucher sind die `bush_*`-Props. Nächster denkbarer Schritt: „Roden“ der Dekosträucher mit der Axt als Bodenaktion (wie das Mähen mit der Sense).
- **Reisig/Haselruten** haben noch keinen Verwendungszweck (sell_price 1/2) — gedacht als Anzündholz und Flechtmaterial für spätere Rezepte.
- Neuer Strauch: Eintrag in `BushCatalog.BUSHES`, Items + zwei LootTables (`loot_bush_<id>_pick/_chop`, nicht ins Manifest) per `content_forge.py`, Skript `Bush<Id>.gd`, `WorldEntityRegistry` (Registrierung + `KNOWN_PROP_TYPES`), Chance in `BiomeRegistry` (Summe je Biom ≤ 1.0).
