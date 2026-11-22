extends RefCounted

# Every upgrade is bounded and belongs to the offline saga. Rules and LAN stay standard.
const UPGRADES := {
	"provisions":{"name":"Scorta del viandante","rune":"I","costs":[2,3,4],"levels":[2,4,7],"description":"Inizi ogni saga con 1 / 2 / 3 gettoni extra."},
	"breath":{"name":"Secondo respiro","rune":"II","costs":[3,4],"levels":[3,6],"description":"All’inizio della manche 4 recuperi 1 / 2 pietre, fino a 15. Una volta per saga."},
	"offering":{"name":"Riserva tattica","rune":"III","costs":[3,4],"levels":[3,6],"description":"All’inizio della manche 3 ricevi 1 / 2 gettoni. Una volta per saga."},
	"last_rune":{"name":"Ultima risorsa","rune":"IV","costs":[4,5],"levels":[5,9],"description":"Da manche 2, se inizi con 5 pietre o meno, ricevi 1 / 2 gettoni. Una volta per saga."},
	"wisdom":{"name":"Esperienza sul campo","rune":"V","costs":[2,3,4],"levels":[2,5,8],"description":"Le vittorie della saga assegnano il 5 / 10 / 15% di XP in più."}
}
const ORDER := ["provisions","breath","offering","last_rune","wisdom"]
const TITLES := ["Alba della saga","Tavolo degli esperti","Tavolo dei maestri","Sfida dei maestri"]
var path: String
var data := {"schema":1,"xp":0,"ranks":{},"claimed":{}}
var last_reward := {}

func _init(storage_path := "user://progression.json") -> void:
	path = storage_path
	if FileAccess.file_exists(path):
		var stored = JSON.parse_string(FileAccess.get_file_as_string(path))
		if stored is Dictionary and int(stored.get("schema",0)) == 1:
			data.xp = clampi(int(stored.get("xp",0)),0,2_000_000_000)
			if stored.get("claimed") is Dictionary:
				data.claimed = stored.claimed
			if stored.get("ranks") is Dictionary:
				for id in ORDER:
					data.ranks[id] = clampi(int(stored.ranks.get(id,0)),0,UPGRADES[id].costs.size())
			# A partial or edited save cannot create a negative point balance.
			if spent_points() > earned_points():
				data.ranks.clear()

static func xp_required(current_level: int) -> int:
	var step := maxi(0,current_level-1)
	return 100 + 35*step + 5*step*step

func level() -> int:
	var result := 1
	var remaining := int(data.xp)
	while remaining >= xp_required(result):
		remaining -= xp_required(result)
		result += 1
	return result

func xp_in_level() -> int:
	var remaining := int(data.xp)
	for current in range(1,level()):
		remaining -= xp_required(current)
	return remaining

func earned_points() -> int:
	return (level()-1)*2

func rank_of(id: String) -> int:
	return int(data.ranks.get(id,0))

func spent_points() -> int:
	var amount := 0
	for id in ORDER:
		for rank_index in rank_of(id):
			amount += int(UPGRADES[id].costs[rank_index])
	return amount

func points() -> int:
	return earned_points()-spent_points()

func purchase_status(id: String) -> String:
	if not UPGRADES.has(id):
		return "Potenziamento sconosciuto"
	var rank_index := rank_of(id)
	if rank_index >= UPGRADES[id].costs.size():
		return "Grado massimo"
	if level() < int(UPGRADES[id].levels[rank_index]):
		return "Richiede livello %d" % UPGRADES[id].levels[rank_index]
	if points() < int(UPGRADES[id].costs[rank_index]):
		return "Punti insufficienti"
	return ""

func purchase(id: String) -> Error:
	if not purchase_status(id).is_empty():
		return ERR_UNAVAILABLE
	var previous: Dictionary = data.duplicate(true)
	data.ranks[id] = rank_of(id)+1
	var error := save()
	if error != OK:
		data = previous
	return error

func refund() -> Error:
	var previous: Dictionary = data.duplicate(true)
	data.ranks.clear()
	var error := save()
	if error != OK:
		data = previous
	return error

func save() -> Error:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

func create_run(difficulty: int, offline := true) -> Dictionary:
	var current := level()
	var tier := 3 if current >= 12 else (2 if current >= 8 else (1 if current >= 4 else 0))
	var base := clampi(difficulty,0,2)
	return {"enabled":offline,"level":current,"tier":tier if offline else 0,
		"difficulty":base,"ai_level":maxi(base,mini(tier,2)) if offline else base,
		"enemy_gold":tier if offline else 0,"trials_extra":8 if offline and tier==3 else 0,
		"ranks":data.ranks.duplicate(true) if offline else {},"last_round":0,"rescue_used":false}

static func victory_xp(run: Dictionary) -> int:
	if not run.get("enabled",false):
		return 0
	var base := 100 + 30*clampi(int(run.get("difficulty",0)),0,2) + 10*clampi(int(run.get("tier",0)),0,3)
	var bonus := 5*clampi(int(run.get("ranks",{}).get("wisdom",0)),0,3)
	return roundi(float(base*(100+bonus))/100.0*float(run.get("xp_multiplier",1.0)))

func complete_match(match_id: String, mode: String, victory: bool, run: Dictionary) -> Dictionary:
	last_reward = {}
	if mode != "solo" or not victory or match_id.is_empty() or data.claimed.has(match_id) or not run.get("enabled",false):
		return last_reward
	var previous: Dictionary = data.duplicate(true)
	var before := level()
	var amount := victory_xp(run)
	data.xp = mini(2_000_000_000,int(data.xp)+amount)
	data.claimed[match_id] = true
	var error := save()
	if error != OK:
		data = previous
		last_reward = {"error":"Impossibile salvare gli XP. Controlla lo spazio sul dispositivo."}
		return last_reward
	last_reward = {"xp":amount,"from_level":before,"to_level":level(),"levels":level()-before,"points":2*(level()-before)}
	return last_reward

static func round_bonuses(match_rules: RefCounted, run: Dictionary) -> Array[String]:
	var notes: Array[String] = []
	if not run.get("enabled",false) or match_rules.winner >= 0 or int(run.get("last_round",0)) >= match_rules.round_no:
		return notes
	run.last_round = match_rules.round_no
	var ranks: Dictionary = run.get("ranks",{})
	var starting_hp := int(match_rules.hp[0])
	if match_rules.round_no == 1:
		var supplies := int(ranks.get("provisions",0))
		match_rules.gold[0] += supplies
		match_rules.gold[1] += int(run.get("enemy_gold",0))
		match_rules.gold[0] += int(run.get("player_gold",0))
		if supplies > 0:
			notes.append("Scorta · +%d gettoni" % supplies)
		if int(run.get("player_gold",0)) > 0:
			notes.append("Campagna · +%d gettoni" % int(run.player_gold))
	if match_rules.round_no == 3:
		var offering := int(ranks.get("offering",0))
		match_rules.gold[0] += offering
		if offering > 0:
			notes.append("Riserva tattica · +%d gettoni" % offering)
	if match_rules.round_no == 4 and int(ranks.get("breath",0)) > 0:
		var healed := mini(int(ranks.breath),15-int(match_rules.hp[0]))
		match_rules.hp[0] += healed
		if healed > 0:
			notes.append("Secondo respiro · +%d pietre" % healed)
	if match_rules.round_no >= 2 and starting_hp <= 5 and starting_hp > 0 and not run.get("rescue_used",false) and int(ranks.get("last_rune",0)) > 0:
		run.rescue_used = true
		match_rules.gold[0] += int(ranks.last_rune)
		notes.append("Ultima risorsa · +%d gettoni" % ranks.last_rune)
	return notes
