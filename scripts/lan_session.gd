extends Node
const Rules = preload("res://scripts/rules.gd")
const PORT := 32640
const DISCOVERY_PORT := 32641
const PROTOCOL := 43
const MAX_PACKET := 32768
signal changed
signal problem(message: String)
var game: Node3D
var role := ""
var active := false
var started := false
var replaying := false
var room_code := ""
var peer_name := "Giocatore"
var peer_loadout := ["impact","renew","breach"]
var match_id := ""
var address := ""
var status := ""
var server := TCPServer.new()
var stream: StreamPeerTCP
var packets: PacketPeerStream
var discovery := PacketPeerUDP.new()
var rooms := {}
var plans: Array = [null,null]
var next_ready := [false,false]
var seq := 0
var last_seq := -1
var last_rx := 0
var deadline := 0
var broadcast_clock := 0.0
var snapshot_clock := 0.0
var ping_clock := 0.0
var client_submitted := false
var snapshot_phase := ""
var last_round := 0
var client_transforms := {}
var testing := false
var awaiting_action := ""
var remote_paused := false
var android_bridge: Object
var discovery_enabled := false
var refresh_pending := false

func setup(owner_game: Node3D) -> void:
	game=owner_game
	name="LAN"
	if Engine.has_singleton("SestriaLAN"):
		android_bridge=Engine.get_singleton("SestriaLAN")
	process_mode=Node.PROCESS_MODE_ALWAYS


static func private_address(ip: String) -> bool:
	if not ip.is_valid_ip_address() or ":" in ip:
		return false
	var p := ip.split(".")
	return p[0] in ["10","127"] or (p[0]=="192" and p[1]=="168") or (p[0]=="172" and int(p[1]) >= 16 and int(p[1]) <= 31) or (p[0]=="169" and p[1]=="254")

func local_addresses() -> PackedStringArray:
	var result := PackedStringArray()
	for ip in IP.get_local_addresses():
		if private_address(ip) and not ip.begins_with("127."):
			result.append(ip)
	return result

func host_room() -> Error:
	close(false)
	var error := server.listen(PORT,"0.0.0.0")
	if error != OK:
		status="Impossibile aprire la stanza. Un’altra stanza potrebbe essere già attiva."
		problem.emit.call_deferred(status)
		return error
	role="host"
	trace_stage("host_listening")
	enable_discovery(true)
	room_code=str(100000+int(Crypto.new().generate_random_bytes(4).decode_u32(0)%900000))
	status="Stanza aperta. Condividi IP e codice con il tuo amico."
	notify_changed()
	return OK

func join_room(ip: String, code: String) -> Error:
	if not private_address(ip) or code.length()!=6 or not code.is_valid_int():
		problem.emit.call_deferred("Inserisci l’IP locale dell’host e il codice di sei cifre.")
		return ERR_INVALID_PARAMETER
	close(false)
	role="guest"
	trace_stage("guest_connecting")
	address=ip
	room_code=code
	stream=StreamPeerTCP.new()
	var error := stream.connect_to_host(ip,PORT)
	if error != OK:
		fail_connection("Impossibile raggiungere la stanza.")
		return error
	deadline=Time.get_ticks_msec()+10000
	status="Connessione alla stanza…"
	notify_changed()
	return OK

func is_guest() -> bool:
	return role=="guest" and active

func close(notify := true) -> void:
	enable_discovery(false)
	if notify and packets and active:
		send({"type":"bye"})
	if stream:
		stream.disconnect_from_host()
	stream=null
	packets=null
	server.stop()
	active=false
	started=false
	replaying=false
	role=""
	plans=[null,null]
	next_ready=[false,false]
	client_submitted=false
	client_transforms.clear()
	seq=0
	last_seq=-1
	last_round=0
	awaiting_action=""
	remote_paused=false
	deadline=0
	ping_clock=0
	snapshot_clock=0
	broadcast_clock=0
	snapshot_phase=""
	trace_stage("session_closed")

func fail_connection(message: String) -> void:
	var was_started := started
	close(false)
	status=message
	if was_started and is_instance_valid(game):
		game.menu()
	problem.emit.call_deferred(message)
	notify_changed()

func attach_packets() -> void:
	stream.set_no_delay(true)
	packets=PacketPeerStream.new()
	packets.stream_peer=stream
	packets.input_buffer_max_size=65536
	packets.output_buffer_max_size=131072
	last_rx=Time.get_ticks_msec()

func send(message: Dictionary) -> void:
	if packets:
		var bytes := JSON.stringify(message).to_utf8_buffer()
		if bytes.size() > MAX_PACKET or packets.put_packet(bytes) != OK:
			fail_connection.call_deferred("La connessione è troppo lenta o si è interrotta. Rientra nella stanza.")

func command(action: String, payload := {}) -> void:
	if not active:
		return
	if role=="host":
		return
	if action in ["roll","keep"]:
		if awaiting_action!="":
			return
		awaiting_action=action
	seq += 1
	send({"type":"command","seq":seq,"round":game.rules.round_no,"action":action,"payload":payload})

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	poll_discovery(now)
	if role=="host" and server.is_connection_available():
		var incoming := server.take_connection()
		if incoming == null:
			return
		if stream or not private_address(incoming.get_connected_host()):
			incoming.disconnect_from_host()
		else:
			stream=incoming
			attach_packets()
			deadline=now+10000
	if stream:
		stream.poll()
		var state := stream.get_status()
		if state==StreamPeerTCP.STATUS_CONNECTED and packets==null:
			attach_packets()
			send({"type":"hello","version":PROTOCOL,"code":room_code,"name":game.player_name(),"loadout":game.equipped})
		elif state in [StreamPeerTCP.STATUS_NONE,StreamPeerTCP.STATUS_ERROR]:
			fail_connection("Connessione interrotta. Rientra nella stanza per giocare di nuovo.")
			return
		if packets:
			for i in mini(24,packets.get_available_packet_count()):
				var raw := packets.get_packet()
				if raw.size()>MAX_PACKET:
					fail_connection("Messaggio LAN non valido.")
					return
				var message=JSON.parse_string(raw.get_string_from_utf8())
				if not message is Dictionary or not message.get("type",null) is String:
					fail_connection("Protocollo LAN non valido.")
					return
				last_rx=now
				receive(message)
				if not stream:
					return
		if not active and now>deadline:
			fail_connection("Stanza non raggiungibile. Controlla Wi-Fi, codice e isolamento client del router.")
			return
		if active and now-last_rx>30000:
			fail_connection("Il rivale non risponde più. La partita non viene contata come vittoria o sconfitta.")
			return
	if active:
		ping_clock+=delta
		if ping_clock>2:
			ping_clock=0
			send({"type":"ping"})
		if role=="host" and started:
			snapshot_clock+=delta
			if snapshot_clock>=.10:
				snapshot_clock=0
				send(snapshot())
		elif role=="guest" and not replaying and started and not get_tree().paused:
			interpolate_client(delta)

func poll_discovery(now: int) -> void:
	if not discovery_enabled or not discovery.is_bound():
		return
	for packet in mini(24,discovery.get_available_packet_count()):
		var bytes := discovery.get_packet()
		var ip := discovery.get_packet_ip()
		if bytes.size()>1024 or not private_address(ip):
			continue
		var item=JSON.parse_string(bytes.get_string_from_utf8())
		if item is Dictionary and item.get("game","")=="sestria" and int(item.get("version",0))==PROTOCOL:
			rooms[ip]={"ip":ip,"name":str(item.get("name","Stanza Sestria")).left(32),"seen":now}
	for ip in rooms.keys():
		if now-int(rooms[ip].seen)>6000:
			rooms.erase(ip)
	if role=="host" and not active:
		broadcast_clock+=get_process_delta_time()
		if broadcast_clock>1:
			broadcast_clock=0
			discovery.set_dest_address("255.255.255.255",DISCOVERY_PORT)
			discovery.put_packet(JSON.stringify({"game":"sestria","version":PROTOCOL,"name":game.player_name()}).to_utf8_buffer())

func valid_loadout(value: Variant) -> bool:
	return value is Array and value.size()==3 and value.all(func(id):return id is String and Rules.FAVOR.has(id)) and value[0]!=value[1] and value[1]!=value[2] and value[0]!=value[2]

func receive(message: Dictionary) -> void:
	var type: String=message.type
	if type=="hello" and role=="host" and not active:
		if int(message.get("version",0))!=PROTOCOL or str(message.get("code",""))!=room_code or not valid_loadout(message.get("loadout",null)):
			send({"type":"error","message":"Codice errato o versione dell’app diversa."})
			stream.disconnect_from_host()
			stream=null
			packets=null
			return
		peer_name=str(message.get("name","Giocatore")).left(32)
		peer_loadout=message.loadout.duplicate()
		active=true
		trace_stage("peer_connected")
		status=peer_name+" è nella stanza. Puoi iniziare."
		send({"type":"welcome","version":PROTOCOL,"name":game.player_name(),"loadout":game.equipped})
		notify_changed()
	elif type=="welcome" and role=="guest" and not active:
		if int(message.get("version",0))!=PROTOCOL or not valid_loadout(message.get("loadout",null)):
			fail_connection("Versione LAN non compatibile.")
			return
		active=true
		trace_stage("peer_connected")
		peer_name=str(message.get("name","Giocatore")).left(32)
		peer_loadout=message.loadout.duplicate()
		status="Connesso a "+peer_name+". Attendi l’avvio."
		notify_changed()
	elif type=="error":
		fail_connection(str(message.get("message","Connessione rifiutata.")).left(160))
	elif not active:
		return
	elif type=="bye":
		fail_connection("Il rivale ha lasciato la stanza.")
	elif type=="ping":
		send({"type":"pong"})
	elif type=="retry" and role=="guest":
		awaiting_action=""
		client_submitted=false
		snapshot_phase=""
	elif type=="start" and role=="guest":
		match_id=str(message.get("match",""))
		started=true
		client_submitted=false
		game.prepare_lan_guest()
	elif type=="state" and role=="guest" and started:
		if not replaying:
			apply_snapshot(message)
	elif type=="resolve" and role=="guest" and started:
		if not replaying and int(message.get("round",0))==game.rules.round_no:
			replay_guest(message)
	elif type=="command" and role=="host" and started:
		var incoming_seq := int(message.get("seq",0))
		if incoming_seq<=last_seq or int(message.get("round",0))!=game.rules.round_no:
			return
		last_seq=incoming_seq
		var payload=message.get("payload",{})
		if not payload is Dictionary:
			return
		handle_command(str(message.get("action","")),payload)

func start_match() -> void:
	if role!="host" or not active or started:
		return
	enable_discovery(false)
	match_id=Crypto.new().generate_random_bytes(12).hex_encode()
	started=true
	trace_stage("match_start")
	send({"type":"start","match":match_id})
	game.prepare()

func handle_command(action: String, payload: Dictionary) -> void:
	if get_tree().paused:
		send({"type":"retry"})
		return
	match action:
		"roll":
			if game.current==1 and game.phase=="remote_roll":
				game.phase="ai"
				game.roll()
		"keep":
			if game.current!=1 or game.phase!="remote_select":
				return
			var ids=payload.get("ids",null)
			if not ids is Array or ids.size()>6:
				return
			var valid: Array=[]
			for value in ids:
				var id := int(value)
				if not (value is float or value is int) or float(id)!=float(value) or id in valid or not game.pending.any(func(d):return d.id==id):
					return
				valid.append(id)
			game.commit(valid)
		"favor":
			if game.phase in ["favor","favor_wait","target"] and plans[1]==null:
				var plan=validate_plan(payload,1,true)
				if plan!=null:
					plans[1]=plan
					try_resolve()
		"next":
			if game.phase=="between":
				next_ready[1]=true
				try_next()

func validate_plan(raw: Dictionary, side: int, reverse_targets := false) -> Variant:
	if raw.is_empty():
		return {}
	var id=str(raw.get("id",""))
	var loadout: Array=game.equipped if side==0 else peer_loadout
	if id not in loadout:
		return null
	var level := int(raw.get("level",-1))
	if level<0 or level>2:
		return null
	var sacrifice := int(raw.get("sacrifice",0))
	if sacrifice<0 or sacrifice>=int(game.rules.hp[side]):
		return null
	var data: Array=Rules.FAVOR[id]
	var available: int=game.rules.gold[side]
	if data[1]>5:
		available+=game.rules.marks(side)+game.rules.count(side,Rules.HAND)
	if available<int(data[2][level]):
		return null
	var result := {"id":id,"level":level,"sacrifice":sacrifice}
	if id=="reroll":
		var targets=raw.get("targets",[])
		if not targets is Array or targets.size()>int(data[3][level]):
			return null
		result.targets=[]
		for pair in targets:
			if not pair is Array or pair.size()!=2:
				return null
			var who := int(pair[0])
			var die_id := int(pair[1])
			if who not in [0,1] or die_id<0 or die_id>=game.cubes[side].size():
				return null
			if reverse_targets:
				who=1-who
			if not game.rules.board[who].any(func(d):return d.id==die_id) or [who,die_id] in result.targets:
				return null
			result.targets.append([who,die_id])
	return result

func submit_favor(plan: Dictionary) -> void:
	if is_guest():
		if client_submitted:
			return
		client_submitted=true
		command("favor",plan)
		game.phase="favor_wait"
		game.ui.status("Offerta pronta. Attendi il rivale.")
	elif role=="host" and active and plans[0]==null:
		var validated=validate_plan(plan,0)
		if validated==null:
			game.ui.feedback.text="Offerta non valida o gettoni insufficienti."
			return
		plans[0]=validated
		game.phase="favor_wait"
		game.ui.status("Offerta pronta. Attendi il rivale.")
		try_resolve()

func try_resolve() -> void:
	if plans[0]==null or plans[1]==null:
		return
	var chosen: Array=plans.duplicate(true)
	send({"type":"resolve","round":game.rules.round_no,"rng":str(game.rules.rng.state),"plans":chosen,"hp":game.rules.hp,"gold":game.rules.gold,"board":game.rules.board,"first":game.rules.first})
	plans=[null,null]
	next_ready=[false,false]
	game.network_enemy_plan=chosen[1]
	game.network_resolving=true
	game.phase="favor"
	game.resolve(chosen[0])

func next_round() -> void:
	if is_guest():
		command("next")
		game.ui.status("Pronto. Attendi il rivale.")
	else:
		next_ready[0]=true
		game.ui.status("Pronto. Attendi il rivale.")
		try_next()

func try_next() -> void:
	if next_ready[0] and next_ready[1]:
		next_ready=[false,false]
		game.network_advancing=true
		game.next_round()

func snapshot() -> Dictionary:
	var dice: Array=[]
	for side in 2:
		var row: Array=[]
		for cube in game.cubes[side]:
			var q: Quaternion=cube.quaternion
			row.append({"id":cube.die_id,"face":cube.face,"committed":cube.committed,"visible":cube.visible,"p":[cube.position.x,cube.position.y,cube.position.z],"q":[q.x,q.y,q.z,q.w]})
		dice.append(row)
	return {"type":"state","phase":game.phase,"current":game.current,"round":game.rules.round_no,"hp":game.rules.hp,"gold":game.rules.gold,"board":game.rules.board,"first":game.rules.first,"winner":game.rules.winner,"attempts":game.attempts,"pending":game.pending if game.current==1 else [],"dice":dice,"lanes":game.table.lanes.visible,"paused":get_tree().paused}

func swap_board(board: Array) -> Array:
	return [board[1].duplicate(true),board[0].duplicate(true)]

func swap_plan(plan: Dictionary) -> Dictionary:
	var result=plan.duplicate(true)
	if result.has("targets"):
		for pair in result.targets:
			pair[0]=1-int(pair[0])
	return result

static func integer_between(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==float(int(value)) and int(value)>=low and int(value)<=high

func valid_board(value: Variant) -> bool:
	if not value is Array or value.size()!=2:
		return false
	for row in value:
		if not valid_dice(row):
			return false
	return true

func valid_dice(row: Variant) -> bool:
	if not row is Array or row.size()>12:
		return false
	var seen := []
	for die in row:
		if not die is Dictionary:
			return false
		if not integer_between(die.get("id"),0,11) or die.id in seen or not integer_between(die.get("face"),0,5) or not integer_between(die.get("kind"),0,4) or not die.get("gold") is bool:
			return false
		seen.append(die.id)
	return true

func valid_state(state: Dictionary) -> bool:
	for key in ["hp","gold","attempts"]:
		if not state.get(key) is Array or state[key].size()!=2:
			return false
	for side in 2:
		if not integer_between(state.hp[side],0,15) or not integer_between(state.gold[side],0,100000) or not integer_between(state.attempts[side],0,3):
			return false
	if not integer_between(state.get("first"),0,1) or not integer_between(state.get("current"),0,1) or not integer_between(state.get("winner"),-1,1) or not integer_between(state.get("round"),1,200):
		return false
	if not valid_board(state.get("board")) or not valid_dice(state.get("pending",[])):
		return false
	if not state.get("dice") is Array or state.dice.size()!=2:
		return false
	for row in state.dice:
		if not row is Array or row.size()>12:
			return false
		var seen := []
		for die in row:
			if not die is Dictionary or not integer_between(die.get("id"),0,11) or die.id in seen:
				return false
			seen.append(die.id)
			for spec in [["p",3],["q",4]]:
				if not die.get(spec[0]) is Array or die[spec[0]].size()!=spec[1]:
					return false
				for value in die[spec[0]]:
					if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value))>30:
						return false
			var q := Quaternion(float(die.q[0]),float(die.q[1]),float(die.q[2]),float(die.q[3]))
			if q.length_squared()<.5 or q.length_squared()>1.5:
				return false
	return state.get("phase") in ["menu","coin","roll","ai","busy","select","remote_roll","remote_select","sorting","favor","favor_wait","target","between","end"]

func apply_snapshot(state: Dictionary) -> void:
	if not valid_state(state):
		fail_connection("Stato LAN non valido o incompatibile. Aggiornate entrambi i dispositivi.")
		return
	# The peer is authenticated with the room code; shape bounds also protect the renderer.
	for key in ["hp","gold","board","attempts","dice"]:
		if not state.get(key,null) is Array or state[key].size()!=2:
			return
	var round_no := int(state.get("round",0))
	if round_no<1 or round_no>200:
		return
	game.rules.hp=[int(state.hp[1]),int(state.hp[0])]
	game.rules.gold=[int(state.gold[1]),int(state.gold[0])]
	game.rules.board=swap_board(state.board)
	game.rules.first=1-int(state.first)
	game.rules.round_no=round_no
	game.rules.winner=-1 if int(state.winner)<0 else 1-int(state.winner)
	game.current=1-int(state.current)
	game.attempts=[int(state.attempts[1]),int(state.attempts[0])]
	if round_no!=last_round:
		last_round=round_no
		client_submitted=false
	var phase: String=str(state.phase)
	var local_phase := "ai"
	if awaiting_action=="roll" and phase!="remote_roll" or awaiting_action=="keep" and phase!="remote_select":
		awaiting_action=""
	if awaiting_action!="":
		local_phase="busy"
	elif phase=="remote_roll":
		local_phase="roll"
	elif phase=="remote_select":
		local_phase="select"
	elif phase in ["favor","favor_wait","target"]:
		local_phase="favor_wait" if client_submitted else ("target" if game.phase=="target" else "favor")
	elif phase in ["busy","sorting","between","end"]:
		local_phase=phase
	elif phase=="coin":
		local_phase="ai"
	game.phase=local_phase
	if state.pending is Array:
		game.pending=state.pending.duplicate(true)
	for side in 2:
		var source: Array=state.dice[1-side]
		if source.size()>12:
			return
		for entry in source:
			if not entry is Dictionary or not entry.get("p",null) is Array or entry.p.size()!=3 or not entry.get("q",null) is Array or entry.q.size()!=4:
				continue
			var id := int(entry.get("id",-1))
			if id<0 or id>11:
				continue
			var cube: Node3D=game.cubes[side][id] if id<game.cubes[side].size() else game.make_die(side,id)
			cube.freeze=true
			cube.scale=Vector3.ONE
			cube.visible=bool(entry.get("visible",false))
			cube.face=clampi(int(entry.get("face",0)),0,5)
			cube.committed=bool(entry.get("committed",false))
			if local_phase not in ["select","target"] or (side==1 and local_phase=="select"):
				cube.selected=false
				cube.frame.hide()
			var p := Vector3(float(entry.p[0]),float(entry.p[1]),-float(entry.p[2]))
			if not p.is_finite() or p.length()>30:
				continue
			var q := Quaternion(float(entry.q[0]),float(entry.q[1]),float(entry.q[2]),float(entry.q[3]))
			if not q.is_finite() or q.length_squared()<.5:
				continue
			q=(Quaternion(Vector3.UP,PI)*q).normalized()
			client_transforms[cube]={"p":p,"q":q}
			cube.rest=p
	game.table.lanes.visible=bool(state.lanes)
	game.table.update_counters(game.rules.hp,game.rules.gold,game.rules.first)
	game.ui.stats(game.rules.hp,game.rules.gold,round_no,game.rules.first)
	var paused_now := bool(state.get("paused",false))
	if remote_paused and not paused_now:
		snapshot_phase=""
	remote_paused=paused_now
	if local_phase!=snapshot_phase:
		snapshot_phase=local_phase
		match local_phase:
			"roll":game.ui.action("Il tuo turno · lancia i dadi","Lancia",game.roll)
			"select":game.ui.action("Tocca i dadi da tenere","Conferma",game.confirm_selection)
			"favor":game.ui.favor_stage()
			"target":game.ui.selection_count(game.targets.size(),game.target_limit)
			"between":game.ui.action("Fine della manche","Prossima manche",game.next_round)
			"end":game.ui.finish(game.rules.winner==0)
			"favor_wait":game.ui.status("Offerta pronta. Attendi il rivale.")
			"sorting":game.ui.set_stage(1);game.ui.status("Preparazione delle corsie")
			_:game.ui.status("I tuoi dadi sono in movimento" if game.current==0 and local_phase=="busy" else "Il rivale sta giocando")
	if bool(state.get("paused",false)):
		if is_instance_valid(game.ui.primary_action):game.ui.primary_action.disabled=true
		game.ui.feedback.text="Il rivale ha messo in pausa la partita"

func interpolate_client(delta: float) -> void:
	for cube in client_transforms.keys():
		if not is_instance_valid(cube):
			client_transforms.erase(cube)
			continue
		var goal: Dictionary=client_transforms[cube]
		cube.position=cube.position.lerp(goal.p+Vector3.UP*(.13 if cube.selected else 0),1-exp(-22*delta))
		cube.quaternion=cube.quaternion.slerp(goal.q,1-exp(-22*delta))

func replay_guest(message: Dictionary) -> void:
	if not message.get("plans",null) is Array or message.plans.size()!=2 or not valid_board(message.get("board")):
		fail_connection("Risoluzione LAN incompleta.")
		return
	for key in ["hp","gold"]:
		if not message.get(key) is Array or message[key].size()!=2:
			fail_connection("Risorse LAN non valide.")
			return
	for side in 2:
		if not integer_between(message.hp[side],0,15) or not integer_between(message.gold[side],0,100000) or not message.plans[side] is Dictionary:
			return
		var plan: Dictionary=message.plans[side]
		if not plan.is_empty() and (not Rules.FAVOR.has(str(plan.get("id",""))) or not integer_between(plan.get("level"),0,2)):
			return
	if not integer_between(message.get("first"),0,1):
		return
	replaying=true
	game.rules.hp=[int(message.hp[1]),int(message.hp[0])]
	game.rules.gold=[int(message.gold[1]),int(message.gold[0])]
	game.rules.board=swap_board(message.board)
	game.rules.first=1-int(message.first)
	game.rules.rng.state=int(str(message.rng))
	game.visual_board=game.rules.board.duplicate(true)
	game.network_enemy_plan=swap_plan(message.plans[0])
	game.network_resolving=true
	game.phase="favor"
	game.resolve(swap_plan(message.plans[1]))

func enable_discovery(enabled: bool) -> void:
	if enabled == discovery_enabled:
		return
	discovery_enabled=enabled
	if enabled:
		discovery.set_broadcast_enabled(true)
		var error := discovery.bind(DISCOVERY_PORT,"0.0.0.0")
		if error != OK:
			# Discovery is optional. Direct TCP by IP must remain available.
			discovery_enabled=false
	else:
		discovery.close()
	if android_bridge:
		android_bridge.setDiscoveryEnabled(discovery_enabled)

func notify_changed() -> void:
	if not refresh_pending:
		refresh_pending=true
		emit_changed.call_deferred()

func emit_changed() -> void:
	refresh_pending=false
	changed.emit()

func trace_stage(stage: String) -> void:
	if android_bridge:
		android_bridge.recordStage(stage)

func _exit_tree() -> void:
	close(false)
	discovery.close()
