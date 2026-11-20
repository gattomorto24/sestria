extends RefCounted
const SCHEMA := 1
var path := "user://statistics.json"
var data := {}
var active := {}
var elapsed := 0.0
var recorded_rounds := {}

func _init(storage_path := "user://statistics.json") -> void:
	path = storage_path
	data = {"schema":SCHEMA,"played":0,"wins":0,"losses":0,"abandoned":0,"streak":0,"best_streak":0,"seconds":0,"rounds":0,"rolls":0,"dice_kept":0,"damage_dealt":0,"damage_taken":0,"blocked":0,"tokens_stolen":0,"favors":{},"modes":{},"history":[]}
	if FileAccess.file_exists(path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary and int(saved.get("schema",0)) == SCHEMA:
			for key in data:
				if saved.has(key) and typeof(saved[key]) == typeof(data[key]) or (saved.has(key) and data[key] is int and saved[key] is float):
					data[key] = saved[key]
			var migrated := {}
			for id in data.favors:
				var key: String = preload("res://scripts/compatibility.gd").tactic(str(id))
				migrated[key] = int(migrated.get(key,0))+int(data.favors[id])
			data.favors = migrated
			if saved.get("unfinished",false):
				data.abandoned += 1
				save()

func save() -> Error:
	var stored: Dictionary = data.duplicate(true)
	stored.unfinished = not active.is_empty()
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(stored))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

func start(mode: String, difficulty: int) -> void:
	if not active.is_empty():
		interrupt()
	active = {"id":Crypto.new().generate_random_bytes(12).hex_encode(),"mode":mode,"difficulty":difficulty,"rounds":0,"rolls":0,"dice_kept":0,"damage_dealt":0,"damage_taken":0,"blocked":0,"tokens_stolen":0,"favors":{}}
	elapsed = 0
	recorded_rounds.clear()
	save()

func tick(delta: float) -> void:
	if not active.is_empty():
		elapsed += maxf(0,delta)

func rolled() -> void:
	if not active.is_empty():
		active.rolls += 1

func kept(amount: int) -> void:
	if not active.is_empty():
		active.dice_kept += maxi(0,amount)

func events(round_no: int, entries: Array) -> void:
	if active.is_empty() or recorded_rounds.has(round_no):
		return
	recorded_rounds[round_no] = true
	active.rounds += 1
	for event: Dictionary in entries:
		var amount := int(event.get("amount",0))
		var side := int(event.get("side",0))
		match str(event.get("kind","")):
			"hit":
				active["damage_taken" if side == 0 else "damage_dealt"] += amount
			"block":
				if side == 0:
					active.blocked += amount
			"token":
				if side == 0 and event.get("extra",{}).get("hand",false):
					active.tokens_stolen += amount
			"favor":
				if side == 0:
					var id := str(event.get("extra",{}).get("id",""))
					active.favors[id] = int(active.favors.get(id,0))+1

func finish(victory: bool, hp: Array) -> void:
	if active.is_empty():
		return
	var mode: String = active.mode
	data.played += 1
	data.wins += int(victory)
	data.losses += int(not victory)
	data.streak = int(data.streak)+1 if victory else 0
	data.best_streak = maxi(int(data.best_streak),int(data.streak))
	for key in ["rounds","rolls","dice_kept","damage_dealt","damage_taken","blocked","tokens_stolen"]:
		data[key] += int(active[key])
	data.seconds += roundi(elapsed)
	for id in active.favors:
		data.favors[id] = int(data.favors.get(id,0))+int(active.favors[id])
	var bucket: Dictionary = data.modes.get(mode,{"played":0,"wins":0})
	bucket.played += 1
	bucket.wins += int(victory)
	data.modes[mode]=bucket
	var summary: Dictionary = active.duplicate(true)
	summary.victory = victory
	summary.seconds = roundi(elapsed)
	summary.hp = hp.duplicate()
	summary.date = Time.get_datetime_string_from_system()
	data.history.push_front(summary)
	data.history = data.history.slice(0,50)
	active.clear()
	save()

func interrupt() -> void:
	if active.is_empty():
		return
	data.abandoned += 1
	active.clear()
	save()

func win_rate() -> int:
	return roundi(100.0*float(data.wins)/maxi(1,int(data.played)))
