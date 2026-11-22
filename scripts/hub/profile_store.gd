extends RefCounted
# Profilo del giocatore: nome, icona, colore, sfondo, titolo e codice amico. Salvato in user://profile.json.
const ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const BANNERS := [
	{"name":"Alba","a":Color("#ff9b3d"),"b":Color("#7a2f6b")},{"name":"Notte","a":Color("#2a3a8c"),"b":Color("#0b1030")},
	{"name":"Foresta","a":Color("#1b9a7a"),"b":Color("#0c2b3a")},{"name":"Brace","a":Color("#d9422b"),"b":Color("#3a0f1c")},
	{"name":"Ametista","a":Color("#8a5cff"),"b":Color("#1b1146")},{"name":"Oro","a":Color("#e0b34a"),"b":Color("#3a2a10")}]
# Titoli che si sbloccano salendo di livello.
const TITLES := [
	{"id":"novice","name":"Novizio","level":1},{"id":"player","name":"Giocatore","level":2},{"id":"strategist","name":"Stratega","level":5},
	{"id":"veteran","name":"Veterano","level":8},{"id":"master","name":"Maestro dei dadi","level":12},{"id":"legend","name":"Leggenda","level":20}]
var path: String
var data := {"schema":1,"name":"Giocatore","emblem":0,"color":0,"banner":1,"title":"novice","friend_id":"","created":0}

func _init(storage_path := "user://profile.json") -> void:
	path = storage_path
	if FileAccess.file_exists(path):
		var stored = JSON.parse_string(FileAccess.get_file_as_string(path))
		if stored is Dictionary and int(stored.get("schema",0)) == 1:
			data.name = clean_name(stored.get("name","Giocatore"))
			data.emblem = clampi(int(stored.get("emblem",0)),0,11)
			data.color = clampi(int(stored.get("color",0)),0,7)
			data.banner = clampi(int(stored.get("banner",1)),0,BANNERS.size()-1)
			data.title = str(stored.get("title","novice"))
			data.created = int(stored.get("created",0))
			var id := str(stored.get("friend_id",""))
			if valid_id(id):
				data.friend_id = id
	if data.friend_id.is_empty():
		data.friend_id = new_id()
		data.created = int(Time.get_unix_time_from_system())
		save()

static func clean_name(value: Variant) -> String:
	var text := ""
	for ch in str(value).left(20).strip_edges():
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			text += ch
	return text if text.length() >= 2 else "Giocatore"

static func valid_id(id: String) -> bool:
	if id.length() != 12:
		return false
	for ch in id:
		if not ALPHABET.contains(ch):
			return false
	return true

static func new_id() -> String:
	var bytes := Crypto.new().generate_random_bytes(12)
	var out := ""
	for b in bytes:
		out += ALPHABET[b % ALPHABET.length()]
	return out

static func format_code(id: String) -> String:
	return "%s-%s-%s" % [id.substr(0,4),id.substr(4,4),id.substr(8,4)] if id.length() == 12 else id

# Codice digitato da un amico → id a 12 caratteri, o "" se non valido.
static func parse_code(text: String) -> String:
	var id := text.to_upper().replace("-","").replace(" ","")
	return id if valid_id(id) else ""

func code() -> String:
	return format_code(data.friend_id)

func title_name(level: int) -> String:
	for entry in TITLES:
		if entry.id == data.title and int(entry.level) <= level:
			return entry.name
	return TITLES[0].name

static func unlocked_titles(level: int) -> Array:
	return TITLES.filter(func(t):return int(t.level) <= level)

func update(changes: Dictionary) -> void:
	if changes.has("name"):
		data.name = clean_name(changes.name)
	if changes.has("emblem"):
		data.emblem = clampi(int(changes.emblem),0,11)
	if changes.has("color"):
		data.color = clampi(int(changes.color),0,7)
	if changes.has("banner"):
		data.banner = clampi(int(changes.banner),0,BANNERS.size()-1)
	if changes.has("title"):
		data.title = str(changes.title)
	save()

func save() -> Error:
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data))
	file.close()
	return OK
