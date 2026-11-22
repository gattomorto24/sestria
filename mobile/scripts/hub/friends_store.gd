extends RefCounted
# Elenco amici, richieste e consegne in attesa. Salvato in user://friends.json. Nessun server: tutto passa da canali diretti
# fra i dispositivi (vedi friends_service.gd), quindi una richiesta o una risposta si consegna quando l'altra persona è online.
const Profile = preload("res://scripts/hub/profile_store.gd")
const MAX_FRIENDS := 60
const MAX_REQUESTS := 30
var path: String
var friends: Array = []      # {id,name,emblem,color,seen}
var incoming: Array = []     # richieste ricevute {id,name,emblem,color,time}
var outgoing: Array = []     # richieste inviate non ancora accettate {id,time}
var outbox: Array = []       # messaggi da consegnare {to,t,extra}

func _init(storage_path := "user://friends.json") -> void:
	path = storage_path
	if not FileAccess.file_exists(path):
		return
	var stored = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not stored is Dictionary or int(stored.get("schema",0)) != 1:
		return
	for item in stored.get("friends",[]):
		var entry := person(item)
		if not entry.is_empty() and friends.size() < MAX_FRIENDS and find(friends,entry.id) < 0:
			friends.append(entry)
	for item in stored.get("incoming",[]):
		var entry := person(item)
		if not entry.is_empty() and incoming.size() < MAX_REQUESTS and find(incoming,entry.id) < 0 and find(friends,entry.id) < 0:
			incoming.append(entry)
	for item in stored.get("outgoing",[]):
		if item is Dictionary and Profile.valid_id(str(item.get("id",""))) and find(outgoing,str(item.id)) < 0 and find(friends,str(item.id)) < 0:
			outgoing.append({"id":str(item.id),"time":int(item.get("time",0))})
	for item in stored.get("outbox",[]):
		if item is Dictionary and Profile.valid_id(str(item.get("to",""))) and str(item.get("t","")) in ["accept","remove"] and outbox.size() < 60:
			outbox.append({"to":str(item.to),"t":str(item.t)})

static func person(item: Variant) -> Dictionary:
	if not item is Dictionary or not Profile.valid_id(str(item.get("id",""))):
		return {}
	return {"id":str(item.id),"name":Profile.clean_name(item.get("name","Giocatore")),"emblem":clampi(int(item.get("emblem",0)),0,11),
		"color":clampi(int(item.get("color",0)),0,7),"seen":int(item.get("seen",0)),"time":int(item.get("time",0))}

static func find(list: Array, id: String) -> int:
	for index in list.size():
		if list[index].id == id:
			return index
	return -1

func is_friend(id: String) -> bool:
	return find(friends,id) >= 0

func pending_incoming() -> int:
	return incoming.size()

func save() -> Error:
	var file := FileAccess.open(path+".tmp",FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify({"schema":1,"friends":friends,"incoming":incoming,"outgoing":outgoing,"outbox":outbox}))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(path+".tmp"),ProjectSettings.globalize_path(path))

# Invia una richiesta d'amicizia al codice indicato. Restituisce "" o un messaggio d'errore.
func request(id: String, own_id: String) -> String:
	if not Profile.valid_id(id):
		return "Il codice amico non è valido. Ha dodici caratteri, ad esempio K7QF-2M9X-ABCD."
	if id == own_id:
		return "Questo è il tuo codice amico."
	if is_friend(id):
		return "È già tuo amico."
	if find(outgoing,id) >= 0:
		return "Hai già inviato una richiesta a questo codice."
	if friends.size() >= MAX_FRIENDS:
		return "Hai raggiunto il massimo di amici."
	var pending := find(incoming,id)
	if pending >= 0:
		accept(id)
		return ""
	outgoing.append({"id":id,"time":int(Time.get_unix_time_from_system())})
	save()
	return ""

func receive_request(info: Dictionary) -> bool:
	var entry := person(info)
	if entry.is_empty() or is_friend(entry.id):
		return false
	var mine := find(outgoing,entry.id)
	if mine >= 0:
		# richieste incrociate: diventate amici
		outgoing.remove_at(mine)
		entry.time = int(Time.get_unix_time_from_system())
		friends.append(entry)
		outbox.append({"to":entry.id,"t":"accept"})
		save()
		return true
	var existing := find(incoming,entry.id)
	if existing >= 0:
		incoming[existing].name = entry.name
		incoming[existing].emblem = entry.emblem
		incoming[existing].color = entry.color
		save()
		return false
	if incoming.size() >= MAX_REQUESTS:
		return false
	entry.time = int(Time.get_unix_time_from_system())
	incoming.append(entry)
	save()
	return true

func accept(id: String) -> void:
	var index := find(incoming,id)
	if index < 0:
		return
	var entry: Dictionary = incoming[index]
	incoming.remove_at(index)
	if not is_friend(id) and friends.size() < MAX_FRIENDS:
		friends.append(entry)
	outbox.append({"to":id,"t":"accept"})
	save()

func decline(id: String) -> void:
	var index := find(incoming,id)
	if index >= 0:
		incoming.remove_at(index)
		save()

func cancel(id: String) -> void:
	var index := find(outgoing,id)
	if index >= 0:
		outgoing.remove_at(index)
		save()

func remove(id: String) -> void:
	var index := find(friends,id)
	if index >= 0:
		friends.remove_at(index)
		outbox.append({"to":id,"t":"remove"})
		save()

# L'altra persona ha accettato la nostra richiesta.
func accepted(info: Dictionary) -> bool:
	var entry := person(info)
	var mine := find(outgoing,entry.get("id",""))
	if entry.is_empty() or mine < 0:
		return false
	outgoing.remove_at(mine)
	if not is_friend(entry.id):
		entry.time = int(Time.get_unix_time_from_system())
		friends.append(entry)
	save()
	return true

func removed_by(id: String) -> void:
	var index := find(friends,id)
	if index >= 0:
		friends.remove_at(index)
		save()

func update_profile(info: Dictionary, now: int) -> void:
	var entry := person(info)
	var index := find(friends,entry.get("id",""))
	if entry.is_empty() or index < 0:
		return
	friends[index].name = entry.name
	friends[index].emblem = entry.emblem
	friends[index].color = entry.color
	friends[index].seen = now
