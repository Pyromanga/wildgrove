class_name ServiceDependencyResolver extends RefCounted

## ServiceDependencyResolver — Phase 2 der Boot-Pipeline.
##
## Nimmt das validierte Array[ServiceDefinition] und gibt die korrekte
## Boot-Reihenfolge als Array[String] zurück (Kahn's Algorithmus).
## Bei einem Zyklus wird ein leerer Array zurückgegeben (Boot wird abgebrochen).

const LOG_CAT := "DependencyResolver"

# ─────────────────────────────────────────────
# Öffentliche API
# ─────────────────────────────────────────────


func resolve(defs: Array[ServiceDefinition]) -> Array[String]:
	if defs.is_empty():
		return []

	# Bekannte Service-Namen sammeln für Abhängigkeits-Prüfung
	var known: Dictionary = {}
	for d in defs:
		known[d.service_name.to_lower()] = true

	# Adjazenzliste und In-Degree aufbauen
	var in_degree: Dictionary = {}
	var adj: Dictionary = {}

	for d in defs:
		var key := d.service_name.to_lower()
		in_degree[key] = 0
		adj[key] = []

	for d in defs:
		var key := d.service_name.to_lower()
		for dep_raw in d.deps:
			var dep := (dep_raw as String).to_lower()
			if not known.has(dep):
				Logger.log_error(
					(
						"Unbekannte Abhängigkeit '%s' in '%s'! Prüfe bootstrap_config.tres."
						% [dep, d.service_name]
					),
					LOG_CAT
				)
				return []
			adj[dep].append(key)
			in_degree[key] += 1

	# Kahn's Algorithmus — Quellen zuerst in die Queue
	var queue: Array[String] = []
	for name in in_degree:
		if in_degree[name] == 0:
			queue.append(name)

	var result: Array[String] = []
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		result.append(cur)
		for neighbor in adj[cur]:
			in_degree[neighbor] -= 1
			if in_degree[neighbor] == 0:
				queue.append(neighbor)

	# Zyklus-Erkennung — result muss alle Services enthalten
	if result.size() != defs.size():
		var result_set: Dictionary = {}
		for r in result:
			result_set[r] = true

		var cycle_members: Array[String] = []
		for d in defs:
			if not result_set.has(d.service_name.to_lower()):
				cycle_members.append(d.service_name)

		Logger.log_error(
			"Zyklische Abhängigkeit erkannt! Beteiligte Services: %s" % str(cycle_members), LOG_CAT
		)
		return []

	Logger.log_info("Reihenfolge aufgelöst: [%s]" % ", ".join(result), LOG_CAT)
	return result
