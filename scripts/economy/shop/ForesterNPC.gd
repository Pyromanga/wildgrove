extends ShopNPC
class_name ForesterNPC

## ForesterNPC — "Förster Holgar". Stationärer Händler-NPC für die Försterei
## (Wunsch "Försterei-Skill: Setzlinge kaufen + pflanzen").
##
## Reine ShopNPC-Subklasse, kein eigener Netzwerk-/Handelscode: das Öffnen des
## Shop-Panels und die eigentlichen Kauf-Transaktionen laufen unverändert über
## ShopNPC._on_interacted()/ShopService (siehe dortiger Klassenkommentar).
## Der Shop-Katalog ist projektweit EIN globaler ShopService.BUY_CATALOG
## (siehe ShopUIController._refresh_buy_list()) — Förster Holgar zeigt also
## denselben Katalog wie Händler Toma, in dem jetzt zusätzlich "oak_sapling"
## steht. Ein eigener, auf Setzlinge beschränkter Katalog pro NPC wäre ein
## größerer Umbau (ShopService müsste NPC-Identität kennen) und stand nicht im
## Wunsch — für den ersten Wurf reicht der eigene NPC mit eigenem Namen/
## Aussehen/Inspect-Text, der den Sinn ("hier gibt's Setzlinge") klar macht.
##
## Passt zur "Handelsstraße" der übrigen stationären NPCs (Shop/Bank/
## Auktionshaus/Villager, siehe WorldSpawner.spawn_all()) und steht dort in
## Sichtweite der Baumschul-Plots (FarmPlot mit crop_id="oak_sapling").

func _init() -> void:
	npc_display_name = "Förster Holgar"

func _get_body_color() -> Color:
	return Color(0.22, 0.42, 0.20)  # Waldgrün statt Tomas Blau.
