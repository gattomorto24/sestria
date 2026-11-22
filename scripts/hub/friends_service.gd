extends Node
# Servizio amici: nessun server. Ognuno resta in ascolto nel proprio sciame personale (richieste, presenza e inviti in arrivo)
# e bussa agli sciami degli amici per consegnare richieste, risposte e inviti e per sapere chi è online. Una consegna riesce
# quando l'altra persona è online: le richieste in attesa si ritentano da sole.
const OnlineLink = preload("res://scripts/online_link.gd")
const Profile = preload("res://scripts/hub/profile_store.gd")
const Store = preload("res://scripts/hub/friends_store.gd")
signal changed
signal invited(from_name: String, code: String)
const PREFIX := "SestriaF"                # + 12 caratteri = 20, la lunghezza di un info-hash
const ONLINE_MS := 120000
const CYCLE_MS := 22000
const JOB_TIMEOUT_MS := 24000
var game: Node
var store: RefCounted
var listener: Node
var prober: Node
var active := false
var online := {}                          # id → ultimo segnale (ms)
var rate := {}                            # id → ultimo messaggio ricevuto (ms)
var job := {}
var job_started := 0
var next_cycle := 0
var presence_cursor := 0
var test_trackers: Array = []

func setup(owner_game: Node, storage_path := "user://friends.json") -> void:
	game = owner_game
	name = "Friends"
	process_mode = Node.PROCESS_MODE_ALWAYS
	store = Store.new(storage_path)
	listener = OnlineLink.new()
	prober = OnlineLink.new()
	add_child(listener)
	add_child(prober)
	listener.friend_message.connect(on_listener_message)
	prober.friend_message.connect(on_prober_message)

static func swarm(id: String) -> String:
	return PREFIX+id

func own_id() -> String:
	return str(game.profile.data.friend_id)

func own_card(kind: String, extra := {}) -> Dictionary:
	var message := {"o":"friend","t":kind,"id":own_id(),"name":str(game.profile.data.name),"emblem":int(game.profile.data.emblem),"color":int(game.profile.data.color)}
	message.merge(extra,true)
	return message

func pending_incoming() -> int:
	return store.pending_incoming()

func is_online(id: String) -> bool:
	return online.has(id) and Time.get_ticks_msec()-int(online[id]) < ONLINE_MS

static func supported() -> bool:
	return OnlineLink.supported()

# Acceso mentre il menu è aperto; spento durante le partite per non occupare la rete.
func activate(on: bool) -> void:
	if on == active or not supported():
		return
	active = on
	if on:
		for node in [listener,prober]:
			if not test_trackers.is_empty():
				node.configure(test_trackers)
		listener.listen(swarm(own_id()))
		next_cycle = Time.get_ticks_msec()+1500
	else:
		listener.stop()
		prober.stop()
		job = {}

# ---- Invio ----

func add_friend(code: String) -> String:
	var id := Profile.parse_code(code)
	var problem: String = store.request(id,own_id())
	if problem.is_empty():
		next_cycle = Time.get_ticks_msec()
		changed.emit()
	return problem

func invite(id: String, invite_code: String) -> void:
	if store.is_friend(id) and not invite_code.is_empty():
		store.outbox.append({"to":id,"t":"invite","extra":{"code":invite_code}})
		next_cycle = Time.get_ticks_msec()

func jobs() -> Array:
	var list: Array = []
	for entry in store.outgoing:
		list.append({"to":entry.id,"t":"request"})
	for entry in store.outbox:
		list.append({"to":entry.to,"t":entry.t,"extra":entry.get("extra",{})})
	return list

func _process(_delta: float) -> void:
	if not active:
		return
	var now := Time.get_ticks_msec()
	if not job.is_empty():
		if now-job_started > JOB_TIMEOUT_MS or (prober.idle() and now-job_started > 4000 and prober.role == "browse" and job_done_idle()):
			finish_job(false)
		return
	if now < next_cycle:
		return
	var queue := jobs()
	if queue.is_empty() and not store.friends.is_empty():
		presence_cursor = (presence_cursor+1)%store.friends.size()
		queue.append({"to":store.friends[presence_cursor].id,"t":"hello"})
	if queue.is_empty():
		next_cycle = now+CYCLE_MS
		return
	start_job(queue[0])

func job_done_idle() -> bool:
	return prober.outgoing.is_empty() and prober.batches.is_empty()

func start_job(entry: Dictionary) -> void:
	job = entry
	job_started = Time.get_ticks_msec()
	prober.probe(swarm(str(entry.to)),own_card(str(entry.t),entry.get("extra",{})))

func finish_job(delivered: bool) -> void:
	if job.is_empty():
		return
	var entry := job
	job = {}
	if delivered:
		match str(entry.t):
			"accept","remove","invite":
				for index in store.outbox.size():
					if store.outbox[index].to == entry.to and store.outbox[index].t == entry.t:
						store.outbox.remove_at(index)
						break
				store.save()
		changed.emit()
	next_cycle = Time.get_ticks_msec()+(1500 if delivered else 5000+randi_range(0,4000))
	if not delivered and store.outgoing.is_empty() and store.outbox.is_empty():
		next_cycle = Time.get_ticks_msec()+CYCLE_MS
	prober.stop()

# ---- Risposte degli amici ----

func on_prober_message(peer, message: Dictionary) -> void:
	var from := str(message.get("id",""))
	if job.is_empty() or from != str(job.to) or not Profile.valid_id(from):
		return
	var kind := str(message.get("t",""))
	if kind == "ack":
		online[from] = Time.get_ticks_msec()
		store.update_profile(message,int(Time.get_unix_time_from_system()))
		if str(job.t) == "request" and bool(message.get("accepted",false)):
			store.accepted(message)
		peer.close()
		finish_job(true)
	elif kind == "accept" and str(job.t) == "request":
		store.accepted(message)
		peer.close()
		finish_job(true)

# ---- Messaggi ricevuti ----

func on_listener_message(peer, message: Dictionary) -> void:
	var from := str(message.get("id",""))
	var kind := str(message.get("t",""))
	if not Profile.valid_id(from) or from == own_id() or not kind in ["hello","request","accept","invite","remove"]:
		return
	var now := Time.get_ticks_msec()
	if rate.has(from) and now-int(rate[from]) < 2500:
		return
	rate[from] = now
	var known: bool = store.is_friend(from) or Store.find(store.outgoing,from) >= 0 or Store.find(store.incoming,from) >= 0
	var accepted := false
	match kind:
		"hello":
			if not known:
				return
			if store.is_friend(from):
				online[from] = now
				store.update_profile(message,int(Time.get_unix_time_from_system()))
		"request":
			var fresh: bool = store.receive_request(message)
			accepted = store.is_friend(from)
			if accepted:
				online[from] = now
			if fresh or accepted:
				changed.emit()
		"accept":
			if store.accepted(message):
				online[from] = now
				changed.emit()
				accepted = true
		"invite":
			if store.is_friend(from) and str(message.get("code","")).length() >= 8 and str(message.code).length() <= 12:
				online[from] = now
				invited.emit(Profile.clean_name(message.get("name","Un amico")),str(message.code))
		"remove":
			if store.is_friend(from):
				store.removed_by(from)
				changed.emit()
	var reply := own_card("ack",{"accepted":accepted})
	peer.send(reply)
