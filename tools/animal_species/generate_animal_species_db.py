#!/usr/bin/env python3
"""generate_animal_species_db.py — erzeugt scripts/entities/animals/AnimalSpeciesDB.gd.

Wunsch "nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen": VORHER brauchte
jede neue Tierart eine eigene .gd-Datei (extends AnimalBase, _on_ready_extended() mit
Farbe/Größe/Speed/Silhouette von Hand getippt) PLUS einen Eintrag in
WorldEntityRegistry.register_all() PLUS einen Eintrag in ChunkEntitySpawner.ANIMAL_TYPES —
für "massiv viele" Tiere (40+) wäre das 40+ fast identische Dateien und ein Diff über drei
Dateien pro Tier gewesen.

JETZT: EIN generischer AnimalBase-Unterklasse (GenericAnimal.gd) liest ihre Statistiken aus
EINER zentralen Datentabelle (AnimalSpeciesDB.gd), geschlüsselt über die species_id — siehe
GenericAnimal.gd-Klassenkommentar für den genauen Mechanismus (species_id steckt bereits im
deterministischen Node-Namen, den EntityOrchestrator.spawn_entity() vergibt, BEVOR _ready()
feuert). WorldEntityRegistry.register_all() und ChunkEntitySpawner iterieren seitdem über
AnimalSpeciesDB.SPECIES.keys() statt über hartkodierte Zeilen pro Tier.

Diese Datei hier ist die EINZIGE Stelle, an der eine neue Tierart als Code-Änderung
entsteht: ein neuer SPECIES-Eintrag unten (meist 3-6 Zeilen, Rest kommt aus DEFAULTS) +
`python3 tools/animal_species/generate_animal_species_db.py` ausführen, um
AnimalSpeciesDB.gd neu zu erzeugen. AnimalSpeciesDB.gd selbst NIE von Hand editieren (siehe
Kopfkommentar dort) — Änderungen gehen beim nächsten Lauf dieses Skripts verloren.

Kein Abhängigkeits-Zoo nötig: reines stdlib-Python, kein Godot/GDScript-Parser — das Skript
rendert einfach Text in Godots GDScript-Syntax.
"""

from __future__ import annotations

import pathlib

# ─────────────────────────────────────────────
# Defaults — jede Spezies unten überschreibt nur, was vom "generischen Standardtier"
# abweicht (identisch zum AnimalBase/AnimalVisualProfile-Default, siehe dortige Klassen-
# kommentare: QUADRUPED, ROUND/STUB/SHORT/NONE, tail_scale 1.0, nicht aquatisch).
# ─────────────────────────────────────────────
DEFAULTS: dict = {
    "color": (0.6, 0.5, 0.4),
    "body_size": (0.4, 0.6, 0.4),
    "speed": 3.5,
    "flee_radius": 5.0,
    "idle_time": 2.0,
    "wander_range": 7.0,
    "ear_style": "ROUND",
    "tail_style": "STUB",
    "snout_style": "SHORT",
    "headgear_style": "NONE",
    "tail_scale": 1.0,
    "body_plan": "QUADRUPED",
    "wing_style": "NONE",
    "back_style": "NONE",
    "body_shape": "NORMAL",
    "leg_style": "NORMAL",
    "pattern_style": "NONE",
    "pattern_color": (0.12, 0.10, 0.09),
    "accent_style": "NONE",
    "aquatic": False,
}

# ─────────────────────────────────────────────
# SPECIES — id (einzelnes Wort, KEIN "_": siehe GenericAnimal.gd für den Grund) ->
# { display_name, inspect_text, ...nur die vom DEFAULTS-Dict abweichenden Felder }.
# Wunsch "mehr Körper für Tiere ... Insekten, Spinnen, Schlangen, Fische, große
# Säugetiere" (vorherige Runde) + "massiv viele Tiere hinzufügen" (diese Runde) — die
# bereits vorhandenen Handarbeit-Tiere (Deer/Rabbit/Boar/Fox/Squirrel/Sheep/Bee/Spider/
# Snake/Fish/Bear, je eigene .gd-Datei) bleiben UNVERÄNDERT bestehen (siehe
# WorldEntityRegistry-Kommentar) — die IDs hier dürfen sich deshalb nicht mit deren Typ-IDs
# überschneiden.
# ─────────────────────────────────────────────
SPECIES: dict = {
    # ---- Große Säugetiere (QUADRUPED, Rückenmerkmal/Kopfschmuck für die Silhouette) ----
    "wolf": dict(
        display_name="Wolf", color=(0.45, 0.45, 0.47), body_size=(0.5, 0.6, 0.65),
        speed=5.0, flee_radius=4.0, wander_range=10.0,
        ear_style="POINTY", tail_style="BUSHY", snout_style="LONG", back_style="MANE",
                body_shape="SLENDER", leg_style="LONG",
inspect_text="Ein Wolf. Beobachtet dich aufmerksam, hält aber Abstand.",
    ),
    "moose": dict(
        display_name="Elch", color=(0.30, 0.22, 0.15), body_size=(1.0, 1.3, 1.1),
        speed=4.0, flee_radius=2.5, wander_range=10.0,
        ear_style="LONG", snout_style="LONG", headgear_style="BROAD_ANTLERS", back_style="HUMP",
                body_shape="STOCKY", leg_style="LONG",
inspect_text="Ein Elch. Das Schaufelgeweih allein ist breiter als ein Mensch.",
    ),
    "bison": dict(
        display_name="Bison", color=(0.26, 0.19, 0.13), body_size=(1.05, 1.1, 1.0),
        speed=3.2, flee_radius=2.0, wander_range=8.0,
        ear_style="ROUND", snout_style="SHORT", back_style="HUMP",
                body_shape="STOCKY", leg_style="THICK",
inspect_text="Ein Bison. Massiger Vorderkörper, kleiner Blick für so viel Tier.",
    ),
    "goat": dict(
        display_name="Ziege", color=(0.82, 0.80, 0.74), body_size=(0.42, 0.5, 0.5),
        speed=4.2, flee_radius=3.0, wander_range=6.0,
        ear_style="FLOPPY", headgear_style="HORNS",
                body_shape="NORMAL", leg_style="THIN",
inspect_text="Eine Ziege. Klettert auch dort, wo es eigentlich keinen Halt gibt.",
    ),
    "mountain_goat": dict(
        display_name="Steinbock", color=(0.68, 0.64, 0.58), body_size=(0.46, 0.55, 0.52),
        speed=4.4, flee_radius=4.0, wander_range=7.0,
        ear_style="ROUND", headgear_style="HORNS",
                body_shape="NORMAL", leg_style="THIN",
inspect_text="Ein Steinbock. Wirkt auf steilem Fels sicherer als auf flachem Boden.",
    ),
    "elk": dict(
        display_name="Rothirsch", color=(0.52, 0.36, 0.20), body_size=(0.62, 0.95, 0.6),
        speed=5.2, flee_radius=6.5, wander_range=10.0,
        ear_style="LONG", snout_style="LONG", headgear_style="ANTLERS",
                body_shape="SLENDER", leg_style="LONG",
inspect_text="Ein Rothirsch. Das Geweih trägt er mit sichtbarem Stolz.",
    ),
    "horse": dict(
        display_name="Wildpferd", color=(0.42, 0.28, 0.16), body_size=(0.6, 1.0, 0.75),
        speed=6.5, flee_radius=6.0, wander_range=12.0,
        ear_style="POINTY", tail_style="FLUFFY", snout_style="LONG",
                body_shape="SLENDER", leg_style="LONG",
inspect_text="Ein Wildpferd. Bei der kleinsten Unruhe sofort im Galopp.",
    ),
    "donkey": dict(
        display_name="Wildesel", color=(0.52, 0.47, 0.42), body_size=(0.5, 0.85, 0.65),
        speed=5.0, flee_radius=5.0, wander_range=10.0,
        ear_style="POINTY", tail_style="STUB", snout_style="LONG",
                body_shape="NORMAL", leg_style="NORMAL",
inspect_text="Ein Wildesel. Trittsicher, genügsam und störrisch — als Lasttier und Reittier beliebt.",
    ),
    "lynx": dict(
        display_name="Luchs", color=(0.58, 0.46, 0.34), body_size=(0.4, 0.42, 0.52),
        speed=5.4, flee_radius=5.5, wander_range=8.0,
        ear_style="POINTY", tail_style="STUB", snout_style="SHORT",
                body_shape="NORMAL", leg_style="THIN",
inspect_text="Ein Luchs. Die Pinselohren zucken bei jedem Geräusch.",
    ),
    "coyote": dict(
        display_name="Kojote", color=(0.58, 0.48, 0.34), body_size=(0.38, 0.46, 0.55),
        speed=5.6, flee_radius=6.0, wander_range=10.0,
        ear_style="POINTY", tail_style="BUSHY", snout_style="LONG",
                body_shape="SLENDER", leg_style="THIN",
inspect_text="Ein Kojote. Schlau genug, um dich zuerst zu bemerken.",
    ),
    "badger": dict(
        display_name="Dachs", color=(0.35, 0.33, 0.32), body_size=(0.4, 0.38, 0.5),
        speed=2.6, flee_radius=3.0, wander_range=5.0,
        ear_style="ROUND", tail_style="STUB", snout_style="LONG",
                body_shape="STOCKY", leg_style="SHORT",
inspect_text="Ein Dachs. Gräbt lieber, als wegzulaufen.",
    ),
    "otter": dict(
        display_name="Otter", color=(0.36, 0.26, 0.18), body_size=(0.26, 0.26, 0.55),
        speed=4.0, flee_radius=4.0, wander_range=6.0,
        ear_style="ROUND", tail_style="BUSHY", tail_scale=1.3,
                body_shape="SLENDER", leg_style="SHORT",
inspect_text="Ein Otter. Immer in der Nähe von Wasser unterwegs.",
    ),
    "raccoon": dict(
        display_name="Waschbär", color=(0.42, 0.40, 0.38), body_size=(0.32, 0.32, 0.42),
        speed=3.8, flee_radius=4.5, wander_range=6.0,
        ear_style="ROUND", tail_style="FLUFFY", tail_scale=1.2,
                body_shape="NORMAL", leg_style="SHORT",
inspect_text="Ein Waschbär. Untersucht alles mit erstaunlich geschickten Pfoten.",
    ),
    "hedgehog": dict(
        display_name="Igel", color=(0.40, 0.34, 0.28), body_size=(0.18, 0.16, 0.22),
        speed=1.4, flee_radius=1.5, wander_range=2.5,
        ear_style="ROUND", tail_style="NONE",
                body_shape="ROUND", leg_style="SHORT",
inspect_text="Ein Igel. Rollt sich bei Gefahr lieber ein, als zu rennen.",
    ),
    "weasel": dict(
        display_name="Wiesel", color=(0.62, 0.42, 0.22), body_size=(0.14, 0.14, 0.34),
        speed=5.8, flee_radius=4.5, wander_range=6.0,
        ear_style="ROUND", tail_style="STUB", snout_style="LONG",
                body_shape="SLENDER", leg_style="SHORT",
inspect_text="Ein Wiesel. Verschwindet blitzschnell im Unterholz.",
    ),
    "mink": dict(
        display_name="Nerz", color=(0.18, 0.16, 0.16), body_size=(0.16, 0.16, 0.38),
        speed=5.0, flee_radius=4.0, wander_range=5.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="LONG",
                body_shape="SLENDER", leg_style="SHORT",
inspect_text="Ein Nerz. Glänzendes, fast schwarzes Fell.",
    ),
    "wild_boar_sow": dict(
        display_name="Bache", color=(0.32, 0.24, 0.17), body_size=(0.58, 0.52, 0.6),
        speed=3.6, flee_radius=3.5, wander_range=10.0,
        ear_style="ROUND", snout_style="LONG",
                body_shape="STOCKY", leg_style="NORMAL",
inspect_text="Eine Bache. Ohne Hauer, aber nicht weniger entschlossen.",
    ),

    # ---- Insekten (INSECT-Bauplan, Flügelstil variiert die Silhouette) ----
    "beetle": dict(
        display_name="Käfer", color=(0.12, 0.30, 0.16), body_size=(0.14, 0.12, 0.16),
        speed=1.6, flee_radius=2.0, idle_time=1.5, wander_range=2.5,
        body_plan="INSECT", wing_style="SHELL",
        inspect_text="Ein Käfer. Die Deckflügel glänzen metallisch grün.",
    ),
    "butterfly": dict(
        display_name="Schmetterling", color=(0.90, 0.55, 0.15), body_size=(0.10, 0.09, 0.12),
        speed=3.8, flee_radius=3.0, idle_time=0.6, wander_range=5.0,
        body_plan="INSECT", wing_style="BROAD",
        inspect_text="Ein Schmetterling. Taumelt scheinbar ziellos von Blüte zu Blüte.",
    ),
    "dragonfly": dict(
        display_name="Libelle", color=(0.20, 0.55, 0.60), body_size=(0.10, 0.09, 0.26),
        speed=5.5, flee_radius=4.0, idle_time=0.5, wander_range=6.0,
        body_plan="INSECT", wing_style="TRANSLUCENT",
        inspect_text="Eine Libelle. Steht förmlich in der Luft, bevor sie blitzartig abdreht.",
    ),
    "wasp": dict(
        accent_style="STRIPES",
        display_name="Wespe", color=(0.95, 0.80, 0.10), body_size=(0.13, 0.12, 0.17),
        speed=4.6, flee_radius=3.0, idle_time=0.7, wander_range=5.0,
        body_plan="INSECT", wing_style="TRANSLUCENT",
        inspect_text="Eine Wespe. Besser nicht zu nah herankommen.",
    ),
    "ladybug": dict(
        accent_style="SPOTS",
        display_name="Marienkäfer", color=(0.85, 0.12, 0.10), body_size=(0.09, 0.08, 0.10),
        speed=1.2, flee_radius=1.5, idle_time=1.8, wander_range=1.5,
        body_plan="INSECT", wing_style="SHELL",
        inspect_text="Ein Marienkäfer. Rote Flügeldecken mit schwarzen Punkten.",
    ),
    "ant": dict(
        display_name="Ameise", color=(0.15, 0.11, 0.08), body_size=(0.06, 0.05, 0.08),
        speed=2.0, flee_radius=1.0, idle_time=0.4, wander_range=2.0,
        body_plan="INSECT",
        inspect_text="Eine Ameise. Trägt ein Vielfaches ihres eigenen Gewichts.",
    ),
    "cricket": dict(
        display_name="Grille", color=(0.30, 0.38, 0.18), body_size=(0.09, 0.08, 0.13),
        speed=2.8, flee_radius=2.5, idle_time=1.0, wander_range=2.5,
        body_plan="INSECT",
        inspect_text="Eine Grille. Verstummt sofort, sobald du näher kommst.",
    ),
    "moth": dict(
        display_name="Nachtfalter", color=(0.55, 0.52, 0.48), body_size=(0.10, 0.09, 0.13),
        speed=3.0, flee_radius=2.5, idle_time=0.8, wander_range=4.0,
        body_plan="INSECT", wing_style="BROAD",
        inspect_text="Ein Nachtfalter. Unscheinbares Grau, erstaunlich große Flügel.",
    ),

    # ---- Spinnen (SPIDER-Bauplan) ----
    "wolf_spider": dict(
        display_name="Wolfsspinne", color=(0.34, 0.26, 0.18), body_size=(0.18, 0.12, 0.18),
        speed=3.0, flee_radius=2.5, wander_range=3.5,
        body_plan="SPIDER",
        inspect_text="Eine Wolfsspinne. Jagt aktiv statt im Netz zu warten.",
    ),
    "tarantula": dict(
        accent_style="STOUT",
        display_name="Vogelspinne", color=(0.20, 0.14, 0.10), body_size=(0.34, 0.18, 0.34),
        speed=1.8, flee_radius=2.0, wander_range=2.5,
        body_plan="SPIDER",
        inspect_text="Eine Vogelspinne. Groß, behaart, und erstaunlich gemächlich.",
    ),
    "garden_spider": dict(
        accent_style="ABDOMEN_MARK",
        display_name="Gartenkreuzspinne", color=(0.70, 0.58, 0.18), body_size=(0.16, 0.10, 0.16),
        speed=1.6, flee_radius=1.8, wander_range=2.0,
        body_plan="SPIDER",
        inspect_text="Eine Kreuzspinne. Das namensgebende Kreuz zeichnet sich auf dem Hinterleib ab.",
    ),
    "jumping_spider": dict(
        accent_style="BIG_EYES",
        display_name="Springspinne", color=(0.16, 0.16, 0.18), body_size=(0.09, 0.07, 0.09),
        speed=2.6, flee_radius=1.5, wander_range=1.5,
        body_plan="SPIDER",
        inspect_text="Eine Springspinne. Winzig, aber mit auffällig wachen Augen.",
    ),

    # ---- Schlangen (SNAKE-Bauplan, body_size.z = Gesamtlänge) ----
    "viper": dict(
        accent_style="TRIANGLE_HEAD",
        display_name="Kreuzotter", color=(0.36, 0.30, 0.20), body_size=(0.11, 0.08, 0.7),
        speed=2.0, flee_radius=3.0, wander_range=3.5,
        body_plan="SNAKE",
        inspect_text="Eine Kreuzotter. Das Zickzackmuster ist aus der Nähe gut zu erkennen.",
    ),
    "cobra": dict(
        accent_style="HOOD",
        display_name="Kobra", color=(0.22, 0.30, 0.20), body_size=(0.13, 0.10, 1.0),
        speed=2.4, flee_radius=4.0, wander_range=4.0,
        body_plan="SNAKE",
        inspect_text="Eine Kobra. Richtet sich bei Störung drohend auf.",
    ),
    "grass_snake": dict(
        display_name="Ringelnatter", color=(0.28, 0.40, 0.24), body_size=(0.09, 0.07, 0.75),
        speed=2.2, flee_radius=3.0, wander_range=4.0,
        body_plan="SNAKE",
        inspect_text="Eine Ringelnatter. Völlig harmlos, aber sieht trotzdem beeindruckend aus.",
    ),
    "python": dict(
        display_name="Python", color=(0.30, 0.28, 0.18), body_size=(0.20, 0.16, 1.8),
        speed=1.4, flee_radius=2.0, wander_range=3.0,
        body_plan="SNAKE",
        inspect_text="Ein Python. Beeindruckend lang und völlig lautlos unterwegs.",
    ),
    "rattlesnake": dict(
        accent_style="RATTLE",
        display_name="Klapperschlange", color=(0.48, 0.40, 0.26), body_size=(0.12, 0.09, 0.65),
        speed=2.0, flee_radius=4.5, wander_range=3.5,
        body_plan="SNAKE",
        inspect_text="Eine Klapperschlange. Das charakteristische Rasseln ist unverkennbar.",
    ),

    # ---- Fische (FISH-Bauplan, aquatic — spawnen im Wasser, siehe ChunkEntitySpawner) ----
    "trout": dict(
        display_name="Forelle", color=(0.46, 0.55, 0.42), body_size=(0.12, 0.18, 0.34),
        speed=2.4, flee_radius=3.0, wander_range=4.0,
        body_plan="FISH", aquatic=True,
        inspect_text="Eine Forelle. Gesprenkelte Flanken, immer in Bewegung.",
    ),
    "salmon": dict(
        display_name="Lachs", color=(0.55, 0.42, 0.42), body_size=(0.15, 0.22, 0.5),
        speed=2.8, flee_radius=3.5, wander_range=5.0,
        body_plan="FISH", aquatic=True,
        inspect_text="Ein Lachs. Kräftiger Körperbau, auf dem Weg stromaufwärts.",
    ),
    "pike": dict(
        accent_style="LONG_JAW",
        display_name="Hecht", color=(0.30, 0.38, 0.28), body_size=(0.13, 0.16, 0.55),
        speed=1.8, flee_radius=2.5, wander_range=3.5,
        body_plan="FISH", aquatic=True,
        inspect_text="Ein Hecht. Reglos im Schilf, bis er blitzschnell zuschnappt.",
    ),
    "catfish": dict(
        accent_style="BARBELS",
        display_name="Wels", color=(0.24, 0.24, 0.26), body_size=(0.18, 0.20, 0.6),
        speed=1.4, flee_radius=2.0, wander_range=3.0,
        body_plan="FISH", aquatic=True,
        inspect_text="Ein Wels. Dämmerig gefärbt, hält sich am liebsten am Grund auf.",
    ),
    "carp": dict(
        display_name="Karpfen", color=(0.62, 0.50, 0.24), body_size=(0.18, 0.30, 0.42),
        speed=1.2, flee_radius=2.5, wander_range=3.0,
        body_plan="FISH", aquatic=True,
        inspect_text="Ein Karpfen. Gemächlich, fast schon träge unterwegs.",
    ),
    "eel": dict(
        accent_style="RIBBON",
        display_name="Aal", color=(0.20, 0.20, 0.20), body_size=(0.07, 0.08, 0.9),
        speed=2.0, flee_radius=3.0, wander_range=4.0,
        body_plan="FISH", aquatic=True,
        inspect_text="Ein Aal. Schlängelt sich fast wie eine Schlange durchs Wasser.",
    ),

    # ---- Wunsch "weitere Tiere hinzufügen" + "Textur von Tieren" — diese Runde bringt vor
    # allem gemusterte Säugetiere (pattern_style), für die sich STRIPES/SPOTS/PATCHES auch
    # tatsächlich lohnen (reale Tiere mit markanter Fellzeichnung) + eine Hand voll weiterer
    # unauffälliger Kleinsäuger für mehr Dichte/Vielfalt im Unterholz. ----
    "zebra": dict(
        display_name="Zebra", color=(0.88, 0.86, 0.80), body_size=(0.58, 1.0, 0.75),
        speed=5.8, flee_radius=7.0, wander_range=11.0,
        ear_style="LONG", tail_style="FLUFFY", snout_style="LONG",
        body_shape="SLENDER", leg_style="LONG",
        pattern_style="STRIPES", pattern_color=(0.08, 0.07, 0.07),
        inspect_text="Ein Zebra. Kein Tier hier hat ein auffälligeres Streifenmuster.",
    ),
    "tiger": dict(
        display_name="Tiger", color=(0.82, 0.46, 0.14), body_size=(0.72, 0.68, 0.85),
        speed=5.0, flee_radius=2.0, wander_range=9.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="SHORT",
        body_shape="SLENDER", leg_style="THICK",
        pattern_style="STRIPES", pattern_color=(0.06, 0.05, 0.05),
        inspect_text="Ein Tiger. Die schwarzen Streifen brechen seine Silhouette im Unterholz auf.",
    ),
    "leopard": dict(
        display_name="Leopard", color=(0.78, 0.60, 0.30), body_size=(0.52, 0.50, 0.68),
        speed=5.6, flee_radius=2.5, wander_range=9.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="SHORT",
        body_shape="SLENDER", leg_style="THIN",
        pattern_style="SPOTS", pattern_color=(0.10, 0.07, 0.05),
        inspect_text="Ein Leopard. Die Fleckenrosetten tarnen ihn fast perfekt im Schatten.",
    ),
    "cheetah": dict(
        display_name="Gepard", color=(0.80, 0.68, 0.42), body_size=(0.46, 0.52, 0.72),
        speed=7.5, flee_radius=3.0, wander_range=11.0,
        ear_style="ROUND", tail_style="FLUFFY", snout_style="SHORT",
        body_shape="SLENDER", leg_style="LONG",
        pattern_style="SPOTS", pattern_color=(0.12, 0.09, 0.07),
        inspect_text="Ein Gepard. Schlank gebaut, für kurze Sprints unglaublich schnell.",
    ),
    "panda": dict(
        display_name="Panda", color=(0.92, 0.92, 0.90), body_size=(0.65, 0.62, 0.62),
        speed=1.8, flee_radius=2.0, wander_range=5.0,
        ear_style="ROUND", tail_style="STUB", snout_style="SHORT",
        body_shape="STOCKY", leg_style="SHORT",
        pattern_style="PATCHES", pattern_color=(0.08, 0.08, 0.09),
        inspect_text="Ein Panda. Schwarzweiß gefleckt und auffällig gemütlich unterwegs.",
    ),
    "skunk": dict(
        display_name="Stinktier", color=(0.10, 0.09, 0.09), body_size=(0.26, 0.24, 0.38),
        speed=2.0, flee_radius=2.0, wander_range=4.0,
        ear_style="ROUND", tail_style="FLUFFY", tail_scale=1.2,
        pattern_style="STRIPES", pattern_color=(0.90, 0.88, 0.84),
        inspect_text="Ein Stinktier. Der weiße Rückenstreifen ist eine klare Warnung.",
    ),
    "hyena": dict(
        display_name="Hyäne", color=(0.62, 0.54, 0.38), body_size=(0.46, 0.5, 0.58),
        speed=4.8, flee_radius=3.5, wander_range=9.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="LONG",
        body_shape="STOCKY",
        pattern_style="SPOTS", pattern_color=(0.22, 0.17, 0.12),
        inspect_text="Eine Hyäne. Ihr Lachen ist im Wald noch aus der Ferne zu hören.",
    ),
    "chipmunk": dict(
        display_name="Streifenhörnchen", color=(0.62, 0.42, 0.24), body_size=(0.12, 0.12, 0.2),
        speed=4.0, flee_radius=4.0, wander_range=4.0,
        ear_style="ROUND", tail_style="BUSHY", tail_scale=1.1,
        pattern_style="STRIPES", pattern_color=(0.25, 0.16, 0.08),
        inspect_text="Ein Streifenhörnchen. Die Rückenstreifen sind sein Markenzeichen.",
    ),
    "giraffe": dict(
        display_name="Giraffe", color=(0.82, 0.70, 0.42), body_size=(0.6, 1.6, 0.85),
        speed=4.6, flee_radius=6.0, wander_range=10.0,
        ear_style="ROUND", snout_style="LONG",
        body_shape="SLENDER", leg_style="LONG",
        pattern_style="PATCHES", pattern_color=(0.42, 0.26, 0.10),
        inspect_text="Eine Giraffe. Selbst geduckt überragt sie fast alles ringsum.",
    ),
    "jackal": dict(
        display_name="Schakal", color=(0.56, 0.44, 0.28), body_size=(0.32, 0.4, 0.5),
        speed=5.2, flee_radius=5.0, wander_range=9.0,
        ear_style="POINTY", tail_style="BUSHY", snout_style="LONG",
        body_shape="SLENDER",
        inspect_text="Ein Schakal. Vorsichtig, aber niemals wirklich weit weg.",
    ),
    "mongoose": dict(
        display_name="Mungo", color=(0.52, 0.46, 0.36), body_size=(0.13, 0.12, 0.32),
        speed=4.6, flee_radius=3.0, wander_range=4.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="LONG",
        body_shape="SLENDER",
        inspect_text="Ein Mungo. Flink genug, um es sogar mit Schlangen aufzunehmen.",
    ),
    "porcupine": dict(
        display_name="Stachelschwein", color=(0.22, 0.20, 0.18), body_size=(0.3, 0.3, 0.42),
        speed=1.6, flee_radius=1.5, wander_range=3.0,
        ear_style="ROUND", tail_style="STUB",
        body_shape="ROUND", leg_style="SHORT",
        inspect_text="Ein Stachelschwein. Besser nicht anfassen.",
    ),
    "warthog": dict(
        display_name="Warzenschwein", color=(0.34, 0.28, 0.20), body_size=(0.5, 0.48, 0.56),
        speed=4.2, flee_radius=3.0, wander_range=9.0,
        ear_style="ROUND", snout_style="LONG", headgear_style="TUSKS",
        body_shape="STOCKY", leg_style="SHORT",
        inspect_text="Ein Warzenschwein. Flitzt bei Gefahr überraschend flink davon, Schwanz steil nach oben.",
    ),
    "gazelle": dict(
        display_name="Gazelle", color=(0.74, 0.60, 0.42), body_size=(0.34, 0.6, 0.5),
        speed=6.8, flee_radius=8.0, wander_range=11.0,
        ear_style="LONG", snout_style="LONG", headgear_style="HORNS",
        body_shape="SLENDER", leg_style="LONG",
        inspect_text="Eine Gazelle. Bei der kleinsten Bewegung schon im Sprung.",
    ),
    "antelope": dict(
        display_name="Antilope", color=(0.56, 0.40, 0.24), body_size=(0.42, 0.68, 0.58),
        speed=6.0, flee_radius=7.0, wander_range=10.0,
        ear_style="ROUND", tail_style="BUSHY", snout_style="LONG", headgear_style="HORNS",
        back_style="HUMP", body_shape="NORMAL", leg_style="LONG",
        inspect_text="Eine Antilope. Elegant gebaut, immer bereit zur Flucht.",
    ),
    "mole": dict(
        display_name="Maulwurf", color=(0.16, 0.15, 0.16), body_size=(0.1, 0.09, 0.14),
        speed=1.0, flee_radius=1.0, idle_time=1.0, wander_range=1.5,
        ear_style="NONE", tail_style="STUB", snout_style="LONG",
        body_shape="ROUND", leg_style="SHORT",
        inspect_text="Ein Maulwurf. Fast blind, aber an der Oberfläche selten lange zu sehen.",
    ),
    "vole": dict(
        display_name="Wühlmaus", color=(0.40, 0.32, 0.22), body_size=(0.08, 0.08, 0.13),
        speed=2.6, flee_radius=2.5, idle_time=1.0, wander_range=2.5,
        ear_style="ROUND", tail_style="STUB", snout_style="SHORT",
        body_shape="ROUND", leg_style="SHORT",
        inspect_text="Eine Wühlmaus. Verschwindet bei jeder Erschütterung sofort im Bau.",
    ),
    "mouse": dict(
        display_name="Feldmaus", color=(0.56, 0.48, 0.38), body_size=(0.07, 0.07, 0.11),
        speed=3.2, flee_radius=2.5, idle_time=0.8, wander_range=2.5,
        ear_style="ROUND", tail_style="THIN", snout_style="SHORT",
        inspect_text="Eine Feldmaus. Winzig, nervös, immer in Bewegung.",
    ),
    "rat": dict(
        display_name="Ratte", color=(0.30, 0.29, 0.28), body_size=(0.09, 0.09, 0.16),
        speed=3.4, flee_radius=3.0, idle_time=0.8, wander_range=3.0,
        ear_style="ROUND", tail_style="THIN", tail_scale=1.2, snout_style="LONG",
        body_shape="SLENDER", leg_style="THIN",
        inspect_text="Eine Ratte. Hält sich meist in der Nähe von Lagern und Gräbern auf.",
    ),
    "shrew": dict(
        display_name="Spitzmaus", color=(0.34, 0.30, 0.28), body_size=(0.06, 0.06, 0.1),
        speed=3.6, flee_radius=2.0, idle_time=0.6, wander_range=2.0,
        ear_style="NONE", tail_style="THIN", tail_scale=0.7, snout_style="LONG",
        inspect_text="Eine Spitzmaus. Frisst fast ständig, nie lange still.",
    ),
    "ferret": dict(
        display_name="Frettchen", color=(0.86, 0.78, 0.60), body_size=(0.12, 0.12, 0.34),
        speed=4.4, flee_radius=3.5, wander_range=5.0,
        ear_style="ROUND", tail_style="STUB", snout_style="LONG",
        body_shape="SLENDER", leg_style="SHORT",
        inspect_text="Ein Frettchen. Lang, geschmeidig, überraschend verspielt.",
    ),
}


def _gd_bool(v: bool) -> str:
    return "true" if v else "false"


def _gd_color(rgb: tuple) -> str:
    return "Color(%s, %s, %s)" % tuple(rgb)


def _gd_vector3(v: tuple) -> str:
    return "Vector3(%s, %s, %s)" % tuple(v)


def _gd_enum(enum_name: str, value: str) -> str:
    return "AnimalVisualProfile.%s.%s" % (enum_name, value)


def _render_entry(species_id: str, raw: dict) -> str:
    merged = {**DEFAULTS, **raw}
    display_name = merged.get("display_name", species_id.replace("_", " ").title())
    inspect_text = merged.get("inspect_text", "Ein %s." % display_name)
    lines = []
    lines.append('\t"%s": {' % species_id)
    lines.append('\t\t"display_name":   "%s",' % display_name)
    lines.append('\t\t"inspect_text":   "%s",' % inspect_text.replace('"', '\\"'))
    lines.append('\t\t"color":          %s,' % _gd_color(merged["color"]))
    lines.append('\t\t"body_size":      %s,' % _gd_vector3(merged["body_size"]))
    lines.append('\t\t"speed":          %s,' % merged["speed"])
    lines.append('\t\t"flee_radius":    %s,' % merged["flee_radius"])
    lines.append('\t\t"idle_time":      %s,' % merged["idle_time"])
    lines.append('\t\t"wander_range":   %s,' % merged["wander_range"])
    lines.append('\t\t"ear_style":      %s,' % _gd_enum("EarStyle", merged["ear_style"]))
    lines.append('\t\t"tail_style":     %s,' % _gd_enum("TailStyle", merged["tail_style"]))
    lines.append('\t\t"snout_style":    %s,' % _gd_enum("SnoutStyle", merged["snout_style"]))
    lines.append('\t\t"headgear_style": %s,' % _gd_enum("HeadgearStyle", merged["headgear_style"]))
    lines.append('\t\t"tail_scale":     %s,' % merged["tail_scale"])
    lines.append('\t\t"body_plan":      %s,' % _gd_enum("BodyPlan", merged["body_plan"]))
    lines.append('\t\t"wing_style":     %s,' % _gd_enum("WingStyle", merged["wing_style"]))
    lines.append('\t\t"back_style":     %s,' % _gd_enum("BackStyle", merged["back_style"]))
    lines.append('\t\t"body_shape":     %s,' % _gd_enum("BodyShape", merged["body_shape"]))
    lines.append('\t\t"leg_style":      %s,' % _gd_enum("LegStyle", merged["leg_style"]))
    lines.append('\t\t"pattern_style":  %s,' % _gd_enum("PatternStyle", merged["pattern_style"]))
    lines.append('\t\t"pattern_color":  %s,' % _gd_color(merged["pattern_color"]))
    lines.append('\t\t"accent_style":   %s,' % _gd_enum("AccentStyle", merged["accent_style"]))
    lines.append('\t\t"aquatic":        %s,' % _gd_bool(merged["aquatic"]))
    lines.append('\t},')
    return "\n".join(lines)


HEADER = '''class_name AnimalSpeciesDB
extends RefCounted

## AnimalSpeciesDB — AUTO-GENERIERT von tools/animal_species/generate_animal_species_db.py.
## NIEMALS VON HAND EDITIEREN — Änderungen hier gehen beim nächsten Lauf des Skripts
## verloren. Neue Tierart hinzufügen: dortige SPECIES-Tabelle ergänzen, Skript neu laufen
## lassen, siehe Kopfkommentar der Python-Datei für die vollständige Begründung
## ("nachhaltig über ein Skript lösen, massiv viele Tiere hinzufügen").
##
## Wird von GenericAnimal.gd (Statistiken je gespawnter Instanz) und
## WorldEntityRegistry.register_all()/ChunkEntitySpawner (welche species_ids es überhaupt
## gibt, welche davon aquatic sind) gelesen. Reine Daten, kein State, kein Verhalten.

const SPECIES: Dictionary = {
%s
}

## Alle Species-IDs mit body_plan FISH / aquatic == true — spawnen über
## ChunkEntitySpawner._spawn_fish() (Wasser), nicht über die normale Land-Tierliste.
static func aquatic_species_ids() -> Array[String]:
	var result: Array[String] = []
	for id in SPECIES:
		if SPECIES[id].get("aquatic", false):
			result.append(id)
	return result

## Alle Species-IDs OHNE aquatic (siehe oben) — spawnen über die normale Land-Tierliste.
static func land_species_ids() -> Array[String]:
	var result: Array[String] = []
	for id in SPECIES:
		if not SPECIES[id].get("aquatic", false):
			result.append(id)
	return result

static func has(species_id: String) -> bool:
	return SPECIES.has(species_id)

static func get_definition(species_id: String) -> Dictionary:
	return SPECIES.get(species_id, {})
'''


def main() -> None:
    entries = "\n".join(_render_entry(sid, data) for sid, data in SPECIES.items())
    content = HEADER % entries
    out_path = pathlib.Path(__file__).resolve().parents[2] / "scripts" / "entities" / "animals" / "AnimalSpeciesDB.gd"
    out_path.write_text(content, encoding="utf-8")
    print("Geschrieben: %s (%d Spezies)" % (out_path, len(SPECIES)))


if __name__ == "__main__":
    main()
