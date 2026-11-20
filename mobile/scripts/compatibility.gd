extends RefCounted
# Identificativi dei vecchi salvataggi; mai mostrati nell’interfaccia.
const LEGACY := {"thrymr": "disruption", "var": "bond", "frigg": "reroll", "freyja": "reinforcements", "loki": "sabotage", "skuld": "attrition", "tyr": "exchange", "baldr": "fortify", "bragi": "harvest", "brunhild": "assault", "freyr": "resonance", "heimdall": "recovery", "hel": "siphon", "mimir": "resolve", "skadi": "volley", "ullr": "pierce", "vidar": "breach", "thor": "impact", "idun": "renew", "odin": "reserve"}
static func tactic(id: String) -> String:
	return str(LEGACY.get(id,id))

static func load_settings(config: ConfigFile) -> Error:
	var error := config.load("user://sestria.cfg")
	if error != OK:
		error = config.load("user://orlog.cfg")
	return error
