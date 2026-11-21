extends SceneTree
# Collaudo delle partite online: elenco stanze, ingresso con codice invito, scambio di dati e dati ostili.
# Richiede un tracker locale: tools/run_online_test.sh lo avvia e lo ferma.
const Link = preload("res://scripts/online_link.gd")
var errors := 0
var checks := 0
var tracker_url := "ws://127.0.0.1:32650"

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		errors += 1
		push_error(note)

func _initialize() -> void:
	call_deferred("run")

func make(label: String) -> Node:
	var node: Node = Link.new()
	node.name = label
	root.add_child(node)
	node.configure([tracker_url])
	node.stun = []
	return node

func wait_until(test: Callable, limit_ms: int) -> bool:
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < limit_ms:
		if test.call():
			return true
		await process_frame
	return test.call()

func receives(channel: WebRTCDataChannel, text: String) -> bool:
	return await wait_until(func(): return channel.get_available_packet_count() > 0 and channel.get_packet().get_string_from_utf8() == text,3000)

func run() -> void:
	check(Link.supported(),"WebRTC disponibile")
	check(Link.normalize_invite("k7qf-2m9x") == "K7QF2M9X","Codice invito normalizzato")
	check(Link.normalize_invite("K7QF-2M9") == "" and Link.normalize_invite("K7QF-2M9I") == "" and Link.normalize_invite("") == "","Codici invito non validi respinti")
	check(Link.clean_name("A\u0001B\n"+"x".repeat(60)).length() <= 32 and not Link.clean_name("\u0001\u0002").is_empty(),"Nomi ripuliti")
	check(Link.format_invite("K7QF2M9X") == "K7QF-2M9X","Codice invito formattato")

	# 1. Elenco: l'ospite vede la stanza pubblica e ci entra con un tocco.
	var host := make("Host")
	var guest := make("Guest")
	var code: String = host.host_room("Anfitrione",true)
	check(code.length() == 8,"L'host riceve un codice invito")
	guest.browse()
	var found: bool = await wait_until(func(): return guest.rooms.size() > 0,25000)
	check(found,"La stanza pubblica compare nell'elenco")
	if not found:
		print("ONLINE | elenco non trovato, interrotto")
		quit(1)
		return
	var room_id: String = guest.rooms.keys()[0]
	check(guest.rooms[room_id].name == "Anfitrione" and guest.rooms[room_id].free,"Scheda della stanza: nome e posto libero")
	check(guest.join_room(room_id) == OK,"Richiesta di ingresso inviata")
	var both: bool = await wait_until(func(): return host.current != null and guest.current != null,10000)
	check(both,"Host e ospite hanno il canale di gioco")
	if both:
		check(host.busy,"L'host risulta occupato")
		host.current.channel.put_packet("host->guest".to_utf8_buffer())
		guest.current.channel.put_packet("guest->host".to_utf8_buffer())
		check(await receives(guest.current.channel,"host->guest"),"Dati dall'host all'ospite")
		check(await receives(host.current.channel,"guest->host"),"Dati dall'ospite all'host")
	host.release()
	check(not host.busy and host.current == null,"Rilascio dell'host")
	guest.release()
	host.stop()
	guest.stop()

	# 2. Codice invito su stanza non pubblica: nessuna comparsa nell'elenco.
	var host2 := make("Host2")
	var spy := make("Spy")
	var guest2 := make("Guest2")
	var code2: String = host2.host_room("Privata",false)
	spy.browse()
	guest2.join_invite(Link.format_invite(code2).to_lower())
	var inside: bool = await wait_until(func(): return host2.current != null and guest2.current != null,25000)
	check(inside,"Ingresso con il codice invito")
	if inside:
		guest2.current.channel.put_packet("ciao".to_utf8_buffer())
		check(await receives(host2.current.channel,"ciao"),"Dati dopo l'ingresso con invito")
	check(spy.rooms.is_empty(),"Una stanza non pubblica non compare nell'elenco")
	host2.stop()
	guest2.stop()
	spy.stop()

	# 3. Codice sbagliato: errore chiaro invece di attesa infinita.
	var lost := make("Lost")
	lost.invite_timeout = 4000
	var failures := {"n":0}
	lost.problem.connect(func(_m): failures.n += 1)
	lost.join_invite("AAAA-AAAA")
	check(await wait_until(func(): return failures.n > 0,9000),"Codice sbagliato: segnalazione dell'errore")
	lost.stop()

	# 4. Dati ostili: un ospite che invia spazzatura viene scollegato e l'host resta in piedi.
	var host3 := make("Host3")
	var rogue := make("Rogue")
	host3.host_room("Solida",true)
	rogue.browse()
	check(await wait_until(func(): return rogue.rooms.size() > 0,25000),"Ospite ostile trova la stanza")
	if rogue.rooms.size() > 0:
		var peer = rogue.rooms.values()[0].peer
		peer.channel.put_packet("non è json".to_utf8_buffer())
		check(await wait_until(func(): return rogue.rooms.is_empty() or peer.phase == "dead",8000),"Messaggio non valido: canale chiuso dall'host")
	check(host3.role == "host","L'host resta attivo dopo dati ostili")
	rogue.stop()

	# 5. Offerte ostili o troppe: nessuna cresce senza limite.
	var before: int = host3.incoming.size()
	var answered: int = host3.answer_times.size()
	host3.host_offer(0,{"info_hash":Link.LOBBY,"peer_id":"-SE46-"+"A".repeat(14),"offer_id":"x".repeat(20),"offer":{"type":"offer","sdp":"v=0\r\n".repeat(3000)}})
	check(host3.incoming.size() == before and host3.answer_times.size() == answered,"Offerta troppo grande ignorata senza lavoro")
	host3.host_offer(0,{"info_hash":"altro","peer_id":"-SE46-"+"B".repeat(14),"offer_id":"y".repeat(20),"offer":{"type":"offer","sdp":"v=0"}})
	check(host3.answer_times.size() == answered,"Offerta per uno sciame non ascoltato ignorata")
	for i in 30:
		host3.host_offer(0,{"info_hash":Link.LOBBY,"peer_id":"-SE46-"+str(1000000+i).pad_zeros(8)+"ZZZZ","offer_id":"id"+str(i)+"abcdefgh","offer":{"type":"offer","sdp":"non valido"}})
	check(host3.answer_times.size() <= Link.MAX_ANSWERS_PER_WINDOW,"Limite di risposte per finestra: %d" % host3.answer_times.size())
	check(host3.incoming.size() <= Link.MAX_INCOMING,"Limite di connessioni in ingresso")
	host3.stop()

	print("ONLINE | %d controlli: elenco, invito, dati, errori e dati ostili | errori %d" % [checks,errors])
	quit(1 if errors else 0)
