extends SceneTree
var host: Node3D
var guest: Node3D
var failures := 0
var with_favors := false
var favors_seen := false
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func run() -> void:
	with_favors="--lan-favors" in OS.get_cmdline_user_args()
	host=load("res://scenes/table.tscn").instantiate()
	root.add_child(host)
	host.integration=true
	host.music.stop()
	guest=load("res://scenes/table.tscn").instantiate()
	root.add_child(guest)
	guest.integration=true
	guest.music.stop()
	if with_favors:
		host.equipped=["impact","attrition","renew"]
		guest.equipped=["reinforcements","reroll","impact"]
	check(host.lan.private_address("192.168.1.1") and host.lan.private_address("10.0.2.2") and not host.lan.private_address("8.8.8.8"),"LAN limitata a indirizzi locali")
	check(host.lan.host_room()==OK,"Creazione stanza TCP")
	var announced := {"game":"sestria","version":host.lan.PROTOCOL,"name":"Prova","code":host.lan.room_code}
	var room: Dictionary = host.lan.parse_room(announced,"192.168.1.20",0)
	check(room.get("code")==host.lan.room_code and room.get("ip")=="192.168.1.20","La stanza annunciata porta il codice")
	check(host.lan.parse_room({"game":"sestria","version":host.lan.PROTOCOL,"name":"Vecchia"},"192.168.1.21",0).get("code")=="","Una stanza di versione precedente non ha codice")
	check(host.lan.parse_room({"game":"sestria","version":host.lan.PROTOCOL,"code":"12ab56"},"192.168.1.22",0).get("code")=="","Un codice non valido viene ignorato")
	check(host.lan.parse_room({"game":"altro","version":host.lan.PROTOCOL},"192.168.1.23",0).is_empty(),"Annunci di altri giochi ignorati")
	# Un annuncio reale via UDP viene letto dal listener e mostra il codice della stanza.
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1",host.lan.DISCOVERY_PORT)
	sender.put_packet(host.lan.announcement())
	var heard := Time.get_ticks_msec()+2000
	while Time.get_ticks_msec()<heard and not host.lan.rooms.has("127.0.0.1"):
		await process_frame
		OS.delay_msec(5)
	sender.close()
	check(host.lan.rooms.has("127.0.0.1") and host.lan.rooms["127.0.0.1"].code==host.lan.room_code,"Annuncio UDP ricevuto con il codice")
	# Entrare da «stanze vicine» usa il codice annunciato, senza digitarlo.
	check(guest.lan.join_room("127.0.0.1",str(room.code))==OK,"Connessione guest con il codice annunciato")
	var deadline := Time.get_ticks_msec()+5000
	while not (host.lan.active and guest.lan.active) and Time.get_ticks_msec()<deadline:
		await process_frame
	if not host.lan.active or not guest.lan.active:
		check(false,"Handshake con codice stanza")
		quit(1)
		return
	check(host.lan.validate_plan({"id":"unknown","level":0},1)==null,"Favore non equipaggiato rifiutato")
	check(host.lan.validate_plan({"id":"impact","level":9},1)==null,"Livello favore non valido rifiutato")
	host.phase="target"
	host.lan.handle_command("favor",{})
	check(host.lan.plans[1] is Dictionary,"L’offerta rivale resta valida mentre l’host sceglie i bersagli di Seconda occasione")
	host.lan.plans=[null,null]
	host.phase="menu"
	host.lan.start_match()
	for i in 12:
		await process_frame
	var sample_state: Dictionary=host.lan.snapshot()
	sample_state.phase="favor"
	guest.phase="target"
	guest.targets=[[0,0]]
	guest.ui.action("Seconda occasione · scegli i bersagli","Attiva",guest.confirm_targets)
	guest.lan.apply_snapshot(sample_state)
	check(guest.phase=="target" and guest.targets==[[0,0]],"Gli aggiornamenti di rete non interrompono la selezione Seconda occasione del guest")
	check(guest.ui.action_callback==Callable(guest,"confirm_targets"),"Il pulsante Invoca resta attivo durante gli aggiornamenti LAN")
	guest.targets=[]
	guest.phase="ai"
	host.toss(0)
	var ticks := 0
	while ticks<18000 and (host.phase!="end" or guest.phase!="end"):
		await process_frame
		ticks+=1
		for game in [host,guest]:
			match game.phase:
				"roll": game.roll()
				"select":
					for die in game.cubes[0]:
						if not die.committed:
							die.select(true)
					game.confirm_selection()
				"favor":
					var plan := {}
					if with_favors:
						if game==guest and game.rules.gold[0]>=2:
							if game.rules.round_no%2==0 and not game.rules.board[1].is_empty():
								plan={"id":"reroll","level":0,"targets":[[1,game.rules.board[1][0].id]]}
							else:
								plan={"id":"reinforcements","level":0}
						elif game==host and game.rules.gold[0]>=4:
							plan={"id":"impact","level":0}
						if not plan.is_empty():
							favors_seen=true
					game.resolve(plan)
				"between": game.next_round()
		if host.rules.round_no>60:
			break
	check(host.phase=="end" and guest.phase=="end","Partita LAN completata da entrambi: %s / %s, manche %d" % [host.phase,guest.phase,host.rules.round_no])
	check(not host.saga_run.get("enabled",true) and not guest.saga_run.get("enabled",true),"Entrambi i peer LAN disabilitano i buff della saga")
	check(host.rules.hp==[guest.rules.hp[1],guest.rules.hp[0]],"Pietre sincronizzate e prospettive invertite")
	check(host.rules.gold==[guest.rules.gold[1],guest.rules.gold[0]],"Gettoni sincronizzati")
	check(host.rules.winner==1-guest.rules.winner,"Vincitore unico condiviso")
	check(host.physics_rolls>0 and host.raycast_hits==0,"Fisica autorevole sul creatore della stanza")
	if with_favors:
		check(favors_seen,"Favori attivate durante la partita LAN")
	print("LAN | due peer TCP reali | round %d | lanci %d | hp %s / %s | errori %d" % [host.rules.round_no,host.physics_rolls,host.rules.hp,guest.rules.hp,failures])
	host.lan.close()
	for i in 12:
		await process_frame
	check(not guest.lan.active and guest.phase=="menu","Disconnessione gestita senza risultato inventato")
	guest.lan.close(false)
	host.queue_free()
	guest.queue_free()
	await process_frame
	quit(1 if failures else 0)
