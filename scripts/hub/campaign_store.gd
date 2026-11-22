extends RefCounted
# Campagne di SESTRIA: salvataggi con nome, sfida e dieci impostazioni. Ogni partita vinta contro il bot dà XP.
# Salvate in user://campaigns.json. La «partita al volo» usa le impostazioni predefinite e non crea una campagna.
const MAX_CAMPAIGNS := 12
const DIFFICULTIES := ["Esploratore","Guerriero","Maestro"]
const TIER_NAMES := ["Alba della campagna","Tavolo degli esperti","Tavolo dei maestri","Sfida finale"]
const MATCHES_PER_TIER := 3
# Le dieci impostazioni: id → {name, hint, options:[[value,label]...], default}
const SETTINGS := [
	{"id":"player_tokens","name":"I tuoi gettoni iniziali","hint":"Gettoni di partenza per te.","options":[[0,"0"],[1,"1"],[2,"2"],[3,"3"]],"default":0},
	{"id":"bot_tokens","name":"Gettoni iniziali del bot","hint":"Automatico segue il livello della campagna.","options":[[-1,"Auto"],[0,"0"],[1,"1"],[2,"2"],[3,"3"],[5,"5"]],"default":-1},
	{"id":"first","name":"Chi inizia","hint":"Alla moneta, sempre tu oppure sempre il bot.","options":[["coin","Moneta"],["player","Tu"],["bot","Bot"]],"default":"coin"},
	{"id":"throws","name":"Lanci per manche","hint":"Con due lanci le manche sono più rapide.","options":[[3,"3 lanci"],[2,"2 lanci"]],"default":3},
	{"id":"bot_style","name":"Stile del bot","hint":"Cambia quanto rischia e quanto difende.","options":[["balanced","Equilibrato"],["aggressive","Aggressivo"],["cautious","Prudente"]],"default":"balanced"},
	{"id":"bot_tactics","name":"Tattiche del bot","hint":"Per livello, casuali o uguali alle tue.","options":[["tier","Per livello"],["random","Casuali"],["mirror","Come le tue"]],"default":"tier"},
	{"id":"speed","name":"Velocità delle animazioni","hint":"Veloce accorcia pause e combattimenti.","options":[["normal","Normale"],["fast","Veloce"]],"default":"normal"},
	{"id":"cloth","name":"Colore del panno","hint":"Solo estetico.","options":[["blue","Blu"],["green","Verde"],["red","Rosso"],["violet","Viola"]],"default":"blue"},
	{"id":"hints","name":"Suggerimenti","hint":"Evidenzia i dadi consigliati. Riduce il premio XP.","options":[[false,"No"],[true,"Sì"]],"default":false},
	{"id":"fixed_seed","name":"Lanci ripetibili","hint":"Stessi dadi ad ogni tentativo dello stesso capitolo.","options":[[false,"No"],[true,"Sì"]],"default":false}]
var path: String
var campaigns: Array = []

func _init(storage_path := "user://campaigns.json") -> void:
	path = storage_path
	if FileAccess.file_exists(path):
		var stored = JSON.parse_string(FileAccess.get_file_as_string(path))
		if stored is Dictionary and int(stored.get("schema",0)) == 1 and stored.get("campaigns") is Array:
			for item in stored.campaigns:
				var clean := sanitize(item)
				if not clean.is_empty() and campaigns.size() < MAX_CAMPAIGNS:
					campaigns.append(clean)

static func default_settings() -> Dictionary:
	var result := {}
	for entry in SETTINGS:
		result[entry.id] = entry.default
	return result

static func clean_settings(raw: Variant) -> Dictionary:
	var result := default_settings()
	if not raw is Dictionary:
		return result
	for entry in SETTINGS:
		if raw.has(entry.id):
			for option in entry.options:
				if typeof(option[0]) == typeof(raw[entry.id]) and option[0] == raw[entry.id]:
					result[entry.id] = raw[entry.id]
	return result

static func clean_name(value: Variant) -> String:
	var text := ""
	for ch in str(value).left(24).strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			text += ch
	return text if not text.is_empty() else "Campagna"

static func sanitize(item: Variant) -> Dictionary:
	if not item is Dictionary:
		return {}
	var identifier := str(item.get("id",""))
	if identifier.length() < 4 or identifier.length() > 32:
		return {}
	var now := int(Time.get_unix_time_from_system())
	return {"id":str(item.id).left(32),"name":clean_name(item.get("name","Campagna")),"difficulty":clampi(int(item.get("difficulty",1)),0,2),
		"settings":clean_settings(item.get("settings")),"created":int(item.get("created",now)),"played":int(item.get("played",0)),
		"chapter":clampi(int(item.get("chapter",1)),1,999),"wins":maxi(0,int(item.get("wins",0))),"losses":maxi(0,int(item.get("losses",0))),
		"streak":maxi(0,int(item.get("streak",0))),"best_streak":maxi(0,int(item.get("best_streak",0))),"xp":maxi(0,int(item.get("xp",0))),
		"seed":int(item.get("seed",1))}

func save() -> Error:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema":1,"campaigns":campaigns}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

func create(name: String, difficulty: int, settings: Dictionary) -> Dictionary:
	if campaigns.size() >= MAX_CAMPAIGNS:
		return {}
	var bytes := Crypto.new().generate_random_bytes(8)
	var id := ""
	for b in bytes:
		id += "%02x" % b
	var item := sanitize({"id":id,"name":name,"difficulty":difficulty,"settings":settings,"created":int(Time.get_unix_time_from_system()),
		"seed":Crypto.new().generate_random_bytes(3).decode_u16(0)+1})
	campaigns.append(item)
	save()
	return item

func find(id: String) -> int:
	for index in campaigns.size():
		if campaigns[index].id == id:
			return index
	return -1

func remove(id: String) -> void:
	var index := find(id)
	if index >= 0:
		campaigns.remove_at(index)
		save()

func rename(id: String, name: String) -> void:
	var index := find(id)
	if index >= 0:
		campaigns[index].name = clean_name(name)
		save()

# Livello del bot per il capitolo corrente (3 partite per livello). Il livello 3 è la sfida finale.
static func tier_for(chapter: int) -> int:
	return clampi((chapter-1)/MATCHES_PER_TIER,0,3)

static func chapter_title(chapter: int) -> String:
	return "%s · partita %d" % [TIER_NAMES[tier_for(chapter)],((chapter-1)%MATCHES_PER_TIER)+1] if chapter <= MATCHES_PER_TIER*3 else "%s · partita %d" % [TIER_NAMES[3],chapter-MATCHES_PER_TIER*3]

# Parametri della partita: gettoni, livello e profondità del bot, tattiche, velocità, regole di gioco.
static func match_setup(campaign: Dictionary) -> Dictionary:
	var settings: Dictionary = campaign.settings
	var tier := tier_for(int(campaign.chapter))
	var base := clampi(int(campaign.difficulty),0,2)
	var bot_tokens := int(settings.bot_tokens)
	return {"campaign":str(campaign.id),"difficulty":base,"tier":tier,"ai_level":maxi(base,mini(tier,2)),"trials_extra":8 if tier == 3 else 0,
		"enemy_gold":tier if bot_tokens < 0 else bot_tokens,"player_gold":int(settings.player_tokens),"first":str(settings.first),"throws":int(settings.throws),
		"style":str(settings.bot_style),"tactics":str(settings.bot_tactics),"speed":str(settings.speed),"cloth":str(settings.cloth),
		"hints":bool(settings.hints),"seed":(int(campaign.seed)*1009+int(campaign.chapter)*31) if settings.fixed_seed else 0,"chapter":int(campaign.chapter)}

# Moltiplicatore del premio XP: più la partita è difficile, più rende. Con i suggerimenti rende meno.
static func xp_multiplier(settings: Dictionary) -> float:
	var value := 1.0
	value -= .05*int(settings.get("player_tokens",0))
	var bot := int(settings.get("bot_tokens",-1))
	if bot >= 2:
		value += .05*(bot-1)
	if int(settings.get("throws",3)) == 2:
		value += .10
	match str(settings.get("bot_style","balanced")):
		"aggressive": value += .05
		"cautious": value += .03
	match str(settings.get("first","coin")):
		"bot": value += .05
		"player": value -= .05
	if bool(settings.get("hints",false)):
		value -= .10
	return clampf(value,.6,1.6)

# Esito di una partita della campagna. Restituisce {"chapter":..,"promoted":bool}.
func record(id: String, victory: bool, xp: int) -> Dictionary:
	var index := find(id)
	if index < 0:
		return {}
	var item: Dictionary = campaigns[index]
	item.played = int(Time.get_unix_time_from_system())
	var promoted := false
	if victory:
		item.wins += 1
		item.streak += 1
		item.best_streak = maxi(item.best_streak,item.streak)
		item.xp += xp
		item.chapter += 1
		promoted = true
	else:
		item.losses += 1
		item.streak = 0
	save()
	return {"chapter":item.chapter,"promoted":promoted}

func sorted() -> Array:
	var copy := campaigns.duplicate()
	copy.sort_custom(func(a,b):return int(a.played if a.played > 0 else a.created) > int(b.played if b.played > 0 else b.created))
	return copy
