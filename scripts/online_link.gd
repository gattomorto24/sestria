extends Node
# Partite online senza server proprio.
# I giocatori si incontrano tramite tracker WebTorrent pubblici, usati soltanto per la segnalazione WebRTC,
# poi la partita passa su un canale dati diretto fra i due dispositivi. Nessun dato di gioco attraversa i tracker.
#
# Due sciami: la "piazza" (elenco delle stanze pubbliche) e uno sciame segreto per ogni stanza (codice invito).
# Prima della partita il canale parla un piccolo protocollo con chiave "o": probe, card, join, ok, busy, ping.
# Dopo "ok" il canale appartiene alla sessione di gioco, che usa gli stessi messaggi della LAN.
signal rooms_changed
signal guest_arrived
signal joined
signal problem(message: String)
signal state_changed
signal friend_message(peer, message)     # messaggi degli amici (richieste, presenza, inviti) su un canale aperto

const PROTOCOL := 43
const LOBBY := "SestriaLobbyP43A0001"
const ROOM_PREFIX := "SestriaRoom"
const ALPHABET := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
const DEFAULT_TRACKERS := ["wss://tracker.openwebtorrent.com","wss://tracker.webtorrent.dev","wss://tracker.files.fm:7073/announce"]
const DEFAULT_STUN := ["stun:stun.l.google.com:19302","stun:stun.cloudflare.com:3478"]
const MAX_OFFER := 8192
const MAX_LOBBY_PACKET := 2048
const MAX_TRACKER_PACKET := 32768
const BROWSE_PROBES := 6
const MAX_INCOMING := 10
const MAX_ANSWERS_PER_WINDOW := 8
const ANSWER_WINDOW_MS := 10000
const HANDSHAKE_MS := 15000
const IDLE_MS := 60000

var trackers: Array = []
var stun: Array = DEFAULT_STUN
var role := ""                  # "", "host", "browse", "invite"
var status := ""
var my_id := ""
var card_name := "Giocatore"
var listed := false
var invite := ""
var busy := false
var rooms := {}                 # peer_id -> {name, free, peer}
var current: Peer               # collegamento passato alla partita
var subscriptions := {}         # info_hash -> true (sciami in cui l'host ascolta)
var incoming := {}              # peer_id remoto -> Peer (host)
var outgoing: Array = []        # Peer (ospite)
var by_offer := {}              # offer_id -> Peer
var batches: Array = []
var answer_times: Array = []
var last_announce := 0
var started_at := 0
var resend_at := 0
var joining: Peer
var invite_timeout := 30000

class Peer extends RefCounted:
	var pc: WebRTCPeerConnection
	var channel: WebRTCDataChannel
	var candidates: Array = []
	var description := ""
	var packed := ""
	var phase := "new"          # gathering, signal, waiting, open, dead
	var started := 0
	var last_candidate := 0
	var opened_at := 0
	var last_rx := 0
	var offer_id := ""
	var remote_id := ""
	var swarm := ""
	var tracker := -1
	var kind := ""              # "in" (host) o "out" (ospite)
	var introduced := false
	var probes := 0
	var info := {}
	var hello := {}              # messaggio da inviare appena il canale si apre (al posto della sonda)

	func begin(ice: Array) -> bool:
		pc = WebRTCPeerConnection.new()
		if pc.initialize({"iceServers":[{"urls":ice}]}) != OK:
			return false
		pc.session_description_created.connect(on_description)
		pc.ice_candidate_created.connect(on_candidate)
		channel = pc.create_data_channel("sestria",{"negotiated":true,"id":1})
		if channel == null:
			return false
		started = Time.get_ticks_msec()
		last_candidate = started
		last_rx = started
		phase = "gathering"
		return true

	func make_offer(ice: Array) -> bool:
		return begin(ice) and pc.create_offer() == OK

	func accept_offer(ice: Array, sdp: String) -> bool:
		return begin(ice) and pc.set_remote_description("offer",sdp) == OK

	func accept_answer(sdp: String) -> bool:
		return pc != null and pc.set_remote_description("answer",sdp) == OK

	func on_description(type: String, sdp: String) -> void:
		if pc:
			pc.set_local_description(type,sdp)
			description = sdp

	func on_candidate(_media: String, _index: int, name: String) -> void:
		candidates.append(name)
		last_candidate = Time.get_ticks_msec()

	# La segnalazione via tracker non ha un canale per i candidati ICE: li incorporiamo nell'SDP.
	func poll(now: int) -> void:
		if pc == null or phase == "dead":
			return
		pc.poll()
		if phase == "gathering" and description != "":
			if (now - started >= 700 and now - last_candidate >= 350) or now - started >= 3000:
				var out := description.strip_edges()
				for c in candidates:
					out += "\r\na=" + str(c)
				packed = out + "\r\na=end-of-candidates\r\n"
				phase = "signal"
		elif phase == "waiting" and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			phase = "open"
			opened_at = now
			last_rx = now
		elif phase == "open" and channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			phase = "dead"

	func is_open() -> bool:
		return phase == "open" and channel != null and channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN

	func send(message: Dictionary) -> void:
		if is_open():
			channel.put_packet(JSON.stringify(message).to_utf8_buffer())

	func read_one() -> Variant:
		if channel == null or channel.get_available_packet_count() == 0:
			return null
		var raw := channel.get_packet()
		if raw.size() > MAX_LOBBY_PACKET:
			return false
		var message = JSON.parse_string(raw.get_string_from_utf8())
		if not message is Dictionary or not message.get("o",null) is String:
			return false
		last_rx = Time.get_ticks_msec()
		return message

	func close() -> void:
		phase = "dead"
		if channel:
			channel.close()
		if pc:
			pc.close()
		channel = null
		pc = null

# ---- Utilità statiche ----

const EXTENSION := "res://addons/webrtc_native/webrtc_native.gdextension"
static var support_checked := false
static var support_ok := false

# Vero se esiste davvero un'implementazione WebRTC: nel browser è integrata, sulle app native arriva dall'estensione
# webrtc-native, che deve essere stata caricata per questa piattaforma e architettura.
static func supported() -> bool:
	if not support_checked:
		support_checked = true
		if OS.has_feature("web"):
			support_ok = ClassDB.class_exists("WebRTCPeerConnection")
		elif GDExtensionManager.is_extension_loaded(EXTENSION):
			var probe := WebRTCPeerConnection.new()
			support_ok = probe.initialize({"iceServers":[]}) == OK
			probe.close()
	return support_ok

static func new_invite() -> String:
	var bytes := Crypto.new().generate_random_bytes(8)
	var code := ""
	for b in bytes:
		code += ALPHABET[b % ALPHABET.length()]
	return code

static func normalize_invite(text: String) -> String:
	var code := text.to_upper().replace("-","").replace(" ","")
	if code.length() != 8:
		return ""
	for ch in code:
		if not ALPHABET.contains(ch):
			return ""
	return code

static func format_invite(code: String) -> String:
	return code.left(4) + "-" + code.right(4) if code.length() == 8 else code

static func room_hash(code: String) -> String:
	return ROOM_PREFIX + code + "1"

static func clean_name(value: Variant) -> String:
	var text := str(value).left(32).strip_edges()
	var out := ""
	for ch in text:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out if out != "" else "Giocatore"

static func valid_peer_id(value: Variant) -> bool:
	return value is String and value.length() >= 8 and value.length() <= 40

# ---- Ciclo di vita ----

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if trackers.is_empty():
		configure(DEFAULT_TRACKERS)

func configure(urls: Array) -> void:
	for t in trackers:
		if t.ws:
			t.ws.close()
	trackers.clear()
	for url in urls:
		trackers.append({"url":str(url),"ws":null,"open":false,"retry":0})

func random_text(count: int) -> String:
	var bytes := Crypto.new().generate_random_bytes(count)
	var text := ""
	for b in bytes:
		text += ALPHABET[b % ALPHABET.length()]
	return text

func start_role(new_role: String) -> void:
	stop()
	role = new_role
	my_id = "-SE46-" + random_text(14)
	started_at = Time.get_ticks_msec()
	for t in trackers:
		t.retry = 0
	notify_state()

func stop() -> void:
	release()
	for peer in incoming.values():
		peer.close()
	for peer in outgoing:
		peer.close()
	incoming.clear()
	outgoing.clear()
	by_offer.clear()
	batches.clear()
	rooms.clear()
	subscriptions.clear()
	answer_times.clear()
	for t in trackers:
		if t.ws:
			t.ws.close()
		t.ws = null
		t.open = false
	role = ""
	listed = false
	invite = ""
	busy = false
	joining = null
	status = ""
	notify_state()

# Libera il collegamento passato alla partita (fine partita o rinuncia).
func release() -> void:
	if current:
		current.close()
		current = null
	if busy:
		busy = false
		push_cards()

func notify_state() -> void:
	state_changed.emit.call_deferred()

func fail(message: String) -> void:
	status = message
	problem.emit.call_deferred(message)

# ---- Host ----

func host_room(name_text: String, is_listed: bool) -> String:
	if not supported():
		fail("Questa versione non supporta le partite online.")
		return ""
	start_role("host")
	card_name = clean_name(name_text)
	listed = is_listed
	invite = new_invite()
	subscriptions[room_hash(invite)] = true
	if listed:
		subscriptions[LOBBY] = true
	status = "Stanza online aperta. Il tuo amico entra con il codice invito." if not listed else "Stanza pubblica aperta: compare nell’elenco e si entra anche con il codice."
	notify_state()
	return invite

func card() -> Dictionary:
	return {"o":"card","v":PROTOCOL,"name":card_name,"free":not busy}

func push_cards() -> void:
	for peer in incoming.values():
		if peer.is_open() and peer != current:
			peer.send(card())

func announce_swarms() -> void:
	for hash in subscriptions:
		tracker_announce(hash,[],0)
	last_announce = Time.get_ticks_msec()

func host_offer(index: int, m: Dictionary) -> void:
	var swarm := str(m.get("info_hash",""))
	var remote: Variant = m.get("peer_id","")
	var oid: Variant = m.get("offer_id","")
	var offer: Variant = m.get("offer",null)
	if role != "host" or busy or not subscriptions.has(swarm) or not valid_peer_id(remote) or remote == my_id:
		return
	if not oid is String or oid.length() < 4 or oid.length() > 64 or not offer is Dictionary:
		return
	if offer.get("type","") != "offer" or not offer.get("sdp",null) is String or offer.sdp.length() > MAX_OFFER:
		return
	if incoming.has(remote) or incoming.size() >= MAX_INCOMING:
		return
	var now := Time.get_ticks_msec()
	answer_times = answer_times.filter(func(t): return now - t < ANSWER_WINDOW_MS)
	if answer_times.size() >= MAX_ANSWERS_PER_WINDOW:
		return
	answer_times.append(now)
	var peer := Peer.new()
	peer.kind = "in"
	peer.remote_id = remote
	peer.offer_id = oid
	peer.swarm = swarm
	peer.tracker = index
	if not peer.accept_offer(stun,offer.sdp):
		peer.close()
		return
	incoming[remote] = peer

func host_peer_message(peer: Peer, message: Dictionary) -> void:
	var op: String = message.o
	if op == "probe":
		peer.probes += 1
		if peer.probes <= 3 and int(message.get("v",0)) == PROTOCOL:
			peer.send(card())
	elif op == "join":
		if int(message.get("v",0)) != PROTOCOL:
			peer.send({"o":"error","message":"Versione dell’app diversa."})
		elif busy or current != null:
			peer.send({"o":"busy"})
		else:
			busy = true
			current = peer
			peer.send({"o":"ok"})
			incoming.erase(peer.remote_id)
			for other in incoming.values():
				other.send({"o":"busy"})
				other.close()
			incoming.clear()
			status = "Un giocatore è entrato."
			guest_arrived.emit.call_deferred()
			notify_state()
	elif op == "friend":
		friend_message.emit(peer,message)
	elif op != "ping":
		peer.close()

# ---- Ospite ----

func browse() -> void:
	if not supported():
		fail("Questa versione non supporta le partite online.")
		return
	if role != "browse":
		start_role("browse")
	prune_dead()
	var missing := BROWSE_PROBES - outgoing.size()
	if missing > 0:
		make_batch(LOBBY,missing)
	status = "Ricerca di stanze online…"
	notify_state()

# Amici: si resta in ascolto nello sciame personale (richieste e presenza in arrivo)...
func listen(swarm: String) -> void:
	if not supported():
		return
	start_role("host")
	subscriptions[swarm] = true
	status = "In ascolto."
	notify_state()

# ...e si bussa allo sciame di un amico con un messaggio da consegnare.
func probe(swarm: String, hello: Dictionary) -> void:
	if not supported():
		return
	if role != "browse":
		start_role("browse")
	make_batch(swarm,1,hello)

func idle() -> bool:
	return outgoing.is_empty() and batches.is_empty()

func join_invite(text: String) -> Error:
	var code := normalize_invite(text)
	if code == "":
		fail("Il codice invito ha otto caratteri, ad esempio K7QF-2M9X.")
		return ERR_INVALID_PARAMETER
	if not supported():
		fail("Questa versione non supporta le partite online.")
		return ERR_UNAVAILABLE
	start_role("invite")
	make_batch(room_hash(code),1)
	status = "Ricerca della stanza…"
	resend_at = Time.get_ticks_msec() + 8000
	notify_state()
	return OK

func join_room(remote: String) -> Error:
	if not rooms.has(remote) or role != "browse":
		return ERR_DOES_NOT_EXIST
	var peer: Peer = rooms[remote].peer
	if not peer.is_open():
		return ERR_UNAVAILABLE
	joining = peer
	peer.send({"o":"join","v":PROTOCOL})
	status = "Ingresso nella stanza…"
	notify_state()
	return OK

func make_batch(swarm: String, count: int, hello := {}) -> void:
	var batch := {"swarm":swarm,"peers":[],"born":Time.get_ticks_msec(),"sent":false}
	for i in count:
		var peer := Peer.new()
		peer.kind = "out"
		peer.swarm = swarm
		peer.hello = hello
		peer.offer_id = random_text(20)
		if peer.make_offer(stun):
			batch.peers.append(peer)
			outgoing.append(peer)
			by_offer[peer.offer_id] = peer
		else:
			peer.close()
	if batch.peers.is_empty():
		fail("Impossibile preparare la connessione online.")
		return
	batches.append(batch)

func guest_answer(m: Dictionary) -> void:
	var oid: Variant = m.get("offer_id","")
	var answer: Variant = m.get("answer",null)
	if not oid is String or not by_offer.has(oid) or not answer is Dictionary or not valid_peer_id(m.get("peer_id","")):
		return
	var peer: Peer = by_offer[oid]
	if peer.phase != "waiting" or peer.remote_id != "" or answer.get("type","") != "answer" or not answer.get("sdp",null) is String or answer.sdp.length() > MAX_OFFER:
		return
	peer.remote_id = m.peer_id
	for other in outgoing:
		if other != peer and other.remote_id == peer.remote_id and other.phase != "dead":
			peer.remote_id = ""
			return
	if not peer.accept_answer(answer.sdp):
		peer.close()
		peer.remote_id = ""

func guest_peer_message(peer: Peer, message: Dictionary) -> void:
	var op: String = message.o
	if op == "card" and role == "browse":
		if int(message.get("v",0)) == PROTOCOL and peer.remote_id != "":
			rooms[peer.remote_id] = {"name":clean_name(message.get("name","")),"free":bool(message.get("free",false)),"peer":peer}
			rooms_changed.emit.call_deferred()
	elif op == "ok" and peer == joining:
		for other in outgoing:
			if other != peer:
				other.close()
		outgoing.clear()
		by_offer.clear()
		batches.clear()
		rooms.clear()
		current = peer
		joining = null
		role = ""
		for t in trackers:
			if t.ws:
				t.ws.close()
			t.ws = null
			t.open = false
		status = "Connesso."
		joined.emit.call_deferred()
		notify_state()
	elif op == "busy" and peer == joining:
		joining = null
		fail("La stanza è già piena.")
	elif op == "error":
		joining = null
		fail(clean_name(message.get("message","Errore")))
	elif op == "friend":
		friend_message.emit(peer,message)
	elif op != "ping" and op != "card" and op != "ok" and op != "busy":
		peer.close()

func prune_dead() -> void:
	var changed := false
	outgoing = outgoing.filter(func(p):
		if p.phase == "dead":
			by_offer.erase(p.offer_id)
			return false
		return true)
	for key in rooms.keys():
		if rooms[key].peer.phase == "dead":
			rooms.erase(key)
			changed = true
	if changed:
		rooms_changed.emit.call_deferred()

# ---- Tracker ----

func tracker_send(index: int, message: Dictionary) -> void:
	var t: Dictionary = trackers[index]
	if t.open and t.ws:
		t.ws.send_text(JSON.stringify(message))

func tracker_announce(swarm: String, offers: Array, left: int) -> void:
	for i in trackers.size():
		tracker_send(i,{"action":"announce","info_hash":swarm,"peer_id":my_id,"numwant":maxi(offers.size(),5),"uploaded":0,"downloaded":0,"left":left,"event":"started","offers":offers})

func any_tracker_open() -> bool:
	return trackers.any(func(t): return t.open)

func poll_trackers(now: int) -> void:
	for i in trackers.size():
		var t: Dictionary = trackers[i]
		if t.ws == null:
			if role != "" and now >= int(t.retry):
				t.ws = WebSocketPeer.new()
				t.ws.inbound_buffer_size = 65536
				t.ws.max_queued_packets = 64
				if t.ws.connect_to_url(t.url) != OK:
					t.ws = null
					t.retry = now + 8000
			continue
		t.ws.poll()
		var state: int = t.ws.get_ready_state()
		if state == WebSocketPeer.STATE_OPEN:
			if not t.open:
				t.open = true
				if role == "host":
					for hash in subscriptions:
						tracker_send(i,{"action":"announce","info_hash":hash,"peer_id":my_id,"numwant":5,"uploaded":0,"downloaded":0,"left":0,"event":"started","offers":[]})
			for n in mini(32,t.ws.get_available_packet_count()):
				var raw: PackedByteArray = t.ws.get_packet()
				if raw.size() > MAX_TRACKER_PACKET:
					continue
				var m = JSON.parse_string(raw.get_string_from_utf8())
				if m is Dictionary and m.get("action","") == "announce":
					on_tracker_message(i,m)
		elif state == WebSocketPeer.STATE_CLOSED:
			t.ws = null
			t.open = false
			t.retry = now + 5000

func on_tracker_message(index: int, m: Dictionary) -> void:
	if m.has("offer"):
		host_offer(index,m)
	elif m.has("answer") and role in ["browse","invite"]:
		guest_answer(m)

# ---- Ciclo ----

func _process(_delta: float) -> void:
	if role == "" and current == null:
		return
	var now := Time.get_ticks_msec()
	poll_trackers(now)
	if role == "host" and now - last_announce > 45000 and any_tracker_open():
		announce_swarms()
	for peer in incoming.values().duplicate():
		step_incoming(peer,now)
	for peer in outgoing.duplicate():
		step_outgoing(peer,now)
	if current:
		current.poll(now)
	flush_batches(now)
	if role == "invite" and now > resend_at and resend_at > 0 and not current:
		resend_at = 0
		for batch in batches:
			batch.sent = false
			batch.born = now
	if role == "invite" and now - started_at > invite_timeout and not current:
		stop()
		fail("Stanza non trovata. Controlla il codice o chiedi all’host di riaprirla.")

func step_incoming(peer: Peer, now: int) -> void:
	peer.poll(now)
	if peer.phase == "signal":
		var index: int = peer.tracker
		if index >= trackers.size() or not trackers[index].open:
			index = trackers.find_custom(func(t): return t.open)
		if index >= 0:
			tracker_send(index,{"action":"announce","info_hash":peer.swarm,"peer_id":my_id,"to_peer_id":peer.remote_id,"offer_id":peer.offer_id,"answer":{"type":"answer","sdp":peer.packed}})
		peer.phase = "waiting"
		peer.started = now
	elif peer.phase == "waiting" and now - peer.started > HANDSHAKE_MS:
		peer.close()
	elif peer.phase == "open":
		if peer == current:
			return
		for i in 4:
			var message = peer.read_one()
			if message == null:
				break
			if message is bool:
				peer.close()
				break
			host_peer_message(peer,message)
			if peer.phase == "dead" or peer == current:
				break
		if peer.phase == "open" and peer != current and now - peer.last_rx > IDLE_MS:
			peer.close()
	if peer.phase == "dead":
		incoming.erase(peer.remote_id)
		peer.close()

func step_outgoing(peer: Peer, now: int) -> void:
	peer.poll(now)
	if peer.phase == "waiting" and peer.remote_id == "" and now - peer.started > invite_timeout:
		peer.close()
	elif peer.phase == "waiting" and peer.remote_id != "" and now - peer.started > invite_timeout + HANDSHAKE_MS:
		peer.close()
	elif peer.phase == "open":
		if not peer.introduced:
			peer.introduced = true
			if not peer.hello.is_empty():
				peer.send(peer.hello)
			elif role == "invite":
				joining = peer
				peer.send({"o":"join","v":PROTOCOL})
			else:
				peer.send({"o":"probe","v":PROTOCOL})
		for i in 4:
			var message = peer.read_one()
			if message == null:
				break
			if message is bool:
				peer.close()
				break
			guest_peer_message(peer,message)
			if peer.phase == "dead" or peer == current:
				break
		if peer.phase == "open" and peer != current and now - peer.last_rx > IDLE_MS:
			peer.close()
	if peer.phase == "dead":
		prune_dead()

func flush_batches(now: int) -> void:
	for batch in batches.duplicate():
		if batch.sent:
			continue
		var ready: bool = batch.peers.all(func(p): return p.phase != "gathering")
		if not ready and now - int(batch.born) < 3400:
			continue
		if not any_tracker_open():
			if now - int(batch.born) > 12000:
				batches.erase(batch)
				fail("Impossibile raggiungere i servizi di incontro. Controlla Internet.")
			continue
		var offers: Array = []
		for p in batch.peers:
			if p.phase == "signal":
				offers.append({"offer_id":p.offer_id,"offer":{"type":"offer","sdp":p.packed}})
				p.phase = "waiting"
				p.started = now
			elif p.phase == "waiting":
				offers.append({"offer_id":p.offer_id,"offer":{"type":"offer","sdp":p.packed}})
		batch.sent = true
		if not offers.is_empty():
			tracker_announce(batch.swarm,offers,1)

func _exit_tree() -> void:
	stop()
