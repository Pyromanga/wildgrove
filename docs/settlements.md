# Dörfer, Straßen und Siedlungsgebäude (Stand 2026-10-10)

Ziel: Gebäude stehen nicht mehr isoliert im Gelände, sondern gehören zu **Dörfern**, die durch
**Straßen** verbunden sind. Dörfer sind auf der **Karte** als solche gekennzeichnet (Fläche,
Haus-Symbol, Name, Typ). Alles wird aus **kleinen Bauteilen** zusammengesetzt.

## Schichten (von klein nach groß)

| Ebene | Datei | Aufgabe |
|---|---|---|
| Primitive | `settlement/parts/PartBatch.gd` | Box/Zylinder/Kegelstumpf/Giebeldach/Pyramide/schräges Brett → **ein** Mesh (Vertex-Farben) + Kollisionsformen pro Gebäude (kein Node-pro-Brett). `push_group(origin, yaw)`/`pop_group()` verschieben/drehen alles dazwischen — so stehen vorhandene Bauteile (Haus, Laterne …) auf Plattformen in der Luft. |
| Bauteile | `settlement/parts/StructureParts.gd` | Wandlauf mit Tür-/Fensteröffnungen, `box_house`, Dächer, Schornstein, Zaun, Laterne, Fass, Bank, Marktstand, Brunnen, Beet, Grabstein, Mühlenflügel … |
| Gebäude | `settlement/parts/BuildingRecipes.gd` | Katalog + Rezepte des **Bodendorfs** (`CATALOG`: Grundstücksgröße, Bodenplatten-Farbe, NPC-Slots) und Fassade für **alle** Typen (`entry`, `half_extents`, `npc_slots`, `build`). |
| Planung | `SettlementSites` → `RoadPaths` → `VillageKind.plan` | Standort → Straßen → Layout; das Layout (Straßen/Grundstücke/Typen/Wege) plant die **Dorf-Art** (siehe unten). |
| Zugriff | `SettlementRegistry` (`TerrainField.get_settlements()`) | Cache + alle Abfragen (Färbung, Chunk-Gebäude, Vegetation, Karte). |
| Chunk | `chunks/ChunkSettlementBuilder.gd` | Geometrie der Gebäude, deren Mittelpunkt im Chunk liegt. NPCs über `ChunkEntitySpawner._spawn_settlement`. |

## Dorf-Arten (`settlement/kinds/`)

Standort, Straßen, Registry, Chunk-Bau und Karte sind für alle Dörfer gleich. Verschieden ist nur, **wo** eine Art
siedelt, **wie groß** sie ist, **wie** sie geplant wird, **welche Gebäudetypen** sie hat und **wie diese aussehen**.
Das steht pro Art in einer Unterklasse von `VillageKind`; `VillageKinds` ist das Register.

| Art | ID | Klasse | Wo | Stufen |
|---|---|---|---|---|
| Bodendorf | `ground` | `GroundVillageKind` (Adapter auf `VillageLayout` + `BuildingRecipes`) | Wiese/Wald/Winter, flach | Weiler / Dorf / Stadt |
| Baumdorf | `canopy` | `CanopyVillageKind` + `CanopyLayout` + `CanopyTree` | Wald (`forest`, `dense_forest`), ≥ 70 % der Probepunkte | Baumweiler / Baumdorf / Baumstadt |

Ablauf in `SettlementSites.find_site`: Der Würfel `kind_roll` (nach den Kandidaten gezogen, damit bestehende Welten
ihre Standorte behalten) wählt, welche Art **zuerst** versucht wird (`VillageKinds.ids_for_roll`). Passt der Ort nicht
zur Art (z. B. Baumdorf auf der Wiese), fällt der Standort deterministisch auf `ground` zurück. Der Standort trägt
`kind`; `SettlementRegistry._ensure_layout` ruft `VillageKinds.kind_of_site(site).plan(...)`.

### Baumdorf (Stand: klein angefangen, ausbaubar)

Ein **Riesenbaum ist ein Gebäude** (ein Mesh + ein Körper, gehört dem Chunk seiner Mitte). Er besteht aus Stamm
(35–45 m), **Wendelrampe** um den Stamm (15°, begehbar), runden **Plattformen** (7 / 13,5 / 20 / 26,5 m) mit Geländer,
**Hütten** im Ring (Tür nach außen), optional **Versammlungshalle** und **Hängebrücken** zu Nachbarbäumen.
Jede Brücke wird von beiden Bäumen je zur Hälfte gebaut (`CanopyTree.bridge_points`) und trifft sich exakt in der Mitte.

| Stufe | Bäume | Ebenen Altbaum | Hütten | Brücken |
|---|---|---|---|---|
| Baumweiler (Radius 34 m) | 1 | 2 | 4 | – |
| Baumdorf (56 m) | 3 | 3 + Halle | ~14 | 2 (Spannbaum ab Altbaum) |
| Baumstadt (78 m) | 5 | 4 + Halle | ~25 | 4 |

**Ausbauen:** Werte in `CanopyLayout.plan` (Bäume je Stufe, Ebenen, Hütten, Halle) bzw. Maße in `CanopyTree`
(Konstanten oben). Weitere Ebenen: `CanopyTree.LEVELS` verlängern. Neue Bauteile am Baum (Aufzug, Marktstand in der
Krone …): als `_funktion` in `CanopyTree.build` ergänzen, begehbare Teile mit Kollision.

**Begehbarkeit ist getestet** (echte Physik in `tests/unit/test_village_kinds.gd`): vom Boden die Rampe hoch, über den
Steg aufs Deck, über eine Brücke zwischen zwei verschieden hohen Bäumen. Dabei gelernt (steht im Code kommentiert):
Kanten über ~12 cm blockieren die Spielerkapsel → der Zufahrtssteg liegt flach auf Deckhöhe, Brücken laufen mit
Steigung 0 in die Decks (smoothstep + sin²), die Rampenphase wird so gewählt, dass Rampe und Brücke sich nicht kreuzen.

### Neue Dorf-Art hinzufügen (Fischer-, Schnee-, Pilz-, Wolken-, Höhlendorf …)

1. `settlement/kinds/<art>/<Art>VillageKind.gd` (`extends VillageKind`): `id()`, `chance()`, `icon()`, `tier_radius()`,
   `tier_label()`, `name_suffixes()`, `site_score()` (Hilfe: `SettlementSites.score_site` mit Biomen/Spreizung),
   `plan()`, `catalog()`, `build_type()`.
2. In `VillageKinds._ensure()` instanziieren und die ID **am Ende** von `SPECIAL_ORDER` anhängen (Reihenfolge nie ändern —
   sie verteilt die Würfelbereiche; die Summe der `chance()` darf 1 nicht überschreiten, der Test prüft das).
3. Gebäudetypen im `catalog()` (`half`, optional `slab` = Bodenplatte, `max_spread`, `npcs`); Typ-IDs müssen über alle Arten
   eindeutig sein (Test). Geometrie über `PartBatch` (+ `push_group` für Höhe/Drehung), Bausteine aus `StructureParts`.
4. Karte: Symbol in `WorldMapView._draw_site_icon` ergänzen (unbekannte Symbole zeigen ein Haus).
5. Tests: Katalog baut Geometrie (Test läuft automatisch über alle Arten), Standort-/Layout-Test analog `test_village_kinds.gd`,
   Begehbarkeit mit dem Physiktest als Vorlage.

Was spätere Arten voraussichtlich brauchen (noch **nicht** gebaut, bewusst erst bei Bedarf):

| Art | Besonderheit | Voraussichtlicher Erweiterungspunkt |
|---|---|---|
| Fischerdorf (Stelzen im/am Wasser) | Standort **am/im** Wasser, Basis = Wasserspiegel statt Gelände | `site_score` eigene Regel; `VillageLayout.make_building` prüft heute „kein Wasser" → Höhenbezug (`anchor`) pro Art/Typ konfigurierbar machen |
| Schneedorf (Iglus, Burgen, Schlösser) | Biom `winter`; Kuppeln/Zinnen | `PartBatch` um Halbkugel/Kuppel erweitern; Burg/Schloss = große Typen (`MAX_FOOTPRINT_RADIUS` anheben) |
| Pilzdorf (in/auf Riesenpilzen) | wie Baumdorf: Stiel + Hut, Plattformen auf dem Hut | `CanopyTree` ist die Vorlage; Rampe/Brücken-Mathematik lässt sich als gemeinsame Klasse herausziehen, sobald die zweite Art sie braucht |
| Wolkendorf | Standort in der Luft über dem Gelände | `anchor`-Höhe (s. o.), Zugang per Rampe/Brücke vom Baumdorf |
| Höhlendorf | Standort unter der Oberfläche | eigener Planer; `ChunkSettlementBuilder` ist an die Oberfläche gebunden → Höhlen-Chunk-Pfad nötig |

## Wie "logisch verknüpft" umgesetzt ist

1. Die Welt ist in **Makro-Zellen** (`SettlementSites.CELL` = 448 m) geteilt; jede hat per Hash höchstens ein Dorf
   (Weiler 38 m / Dorf 58 m / Stadt 80 m Radius) am flachsten trockenen Kandidaten. Nur erlaubte Biome
   (`meadow`, `forest`, `winter`). Das handgebaute Startdorf (**Hainau**) ist ein fester Knoten (`fixed`) ohne generierte Häuser.
2. Jedes Dorf verbindet sich mit seinen 1–2 nächsten Nachbarn (3×3 Zellen) per **Fernstraße** (`RoadPaths`):
   leicht geschwungen, weicht Wasser seitlich aus. Die Straße ist im Dorf zugleich **Hauptstraße**.
3. `VillageLayout`: Zentrum (Marktplatz mit Brunnen bzw. nur Brunnen im Weiler) im Straßenknoten → Querstraße(n) →
   Grundstücke **beidseitig der Straßen, Front zur Straße** → Typen nach Lage (Gasthaus/Kapelle/Handwerk innen,
   Höfe/Scheunen/Ställe außen, Felder hinter Höfen, Friedhof neben der Kapelle, Mühle am Wasser, Wachposten/Wegkreuz an
   den Ortseingängen) → **Hauswege** von jeder Tür zur nächsten Straße.
4. Entlang der Fernstraßen stehen **Wegkreuze und Rasthäuser** (`SettlementRegistry._add_waysides`), Front zur Straße.
5. **Straßenfarbe**: `TerrainChunkBuilder._biome_color()` mischt Weg-/Straßenfarbe in die Vertex-Farbe
   (`SettlementRegistry.road_tint`). Gras/Blumen/Büsche/Props meiden Straßen und Grundstücke (`blocks_vegetation`).
6. Die alten Zufalls-Einzelgebäude (`ChunkStructurePlanner`) weichen Dörfern und Straßen aus.

## Determinismus (Multiplayer)

Alles hängt nur von `world_seed` und der **Basis**-Geländehöhe (`get_base_height_at`, ohne Spieler-Änderungen) ab.
Kanten-/Layout-Reihenfolge ist unabhängig von der Anfrage-Reihenfolge (Kanten werden nach Schlüssel sortiert; Test
`test_layout_is_independent_of_query_order`). Es wird nichts übertragen; jeder Peer berechnet dasselbe.

## Neuen Gebäudetyp hinzufügen (Bodendorf)

1. Konstante + `CATALOG`-Eintrag (`half`, `slab`, `npcs`) in `BuildingRecipes`.
2. `_dein_typ(b, …)` aus `StructureParts` zusammensetzen, `match`-Zweig in `BuildingRecipes.build()`.
3. In `VillageLayout` in eine `QUEUE_*` einreihen (und ggf. `OUTER_ONLY`/`INNER_ONLY`).
`test_every_catalog_type_builds_geometry` prüft Geometrie, Slots im Grundstück und erlaubte NPC-Typen.

## Berufe

Seit 2026-10-10 haben viele Gebäude einen echten Beruf (Töpferei, Weberei, Färberei, Brauhaus, Gerberei, Käserei,
Salzsiederei, Glashütte, Wagnerei, Schreibstube, Fischerei; Schmiede/Bäckerei/Mühle bekommen Schmied/Bäcker/Müller).
Verdrahtung, Quellen und Skripte: `docs/professions.md`. Ortsrand-Typen (Gerberei, Salzsiederei, Käserei) stehen in
`VillageLayout.OUTER_ONLY`, Stadt-Typen in `INNER_ONLY`; die Fischerei braucht wie die Mühle Wasser in 32 m
(`_place_waterside`).

## Karte

`WorldMapView._draw_settlements`: Straßen (Linie), Dörfer (Fläche = Radius, Haus-Symbol, Name, Typ bei Zoom ≤ 900 m).
Geplant wird progressiv (`SETTLEMENT_PREP_PER_FRAME` Zellen/Frame), bereits berechnete Dörfer erscheinen sofort.

## Bekannte Grenzen

- Straßen folgen dem Gelände nur als **Färbung** (kein Einebnen, keine Brücken; Wasser wird umgangen, sonst Furt).
- Gebäude gehören dem Chunk ihres Mittelpunkts; ragt ein Gebäude über die Kante, fehlt dort Boden, solange der Nachbar nicht geladen ist.
- Erste Planung einer Zelle kostet einige hundert Höhenabfragen (einmalig, danach gecacht).
- Getestet mit Godot 4.6.3 + GUT (`tests/unit/test_settlements.gd`, `tests/unit/test_village_kinds.gd`); die **Optik** (Dachwinkel,
  Türen, Mühlenflügel, Baumkronen) ist noch nicht im Spiel angesehen worden.
