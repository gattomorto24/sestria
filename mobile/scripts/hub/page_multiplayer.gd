extends RefCounted
# Scheda Multigiocatore: «Su questo dispositivo» (Passa e gioca), LAN e Online. LAN e online usano la sessione di rete
# del gioco (game.lan); qui c'è solo l'aspetto.
const Kit = preload("res://scripts/hub/kit.gd")
const OnlineLink = preload("res://scripts/online_link.gd")
const Platform = preload("res://scripts/platform.gd")
const SUBS := ["device","lan","online"]
const SUB_NAMES := ["Su questo dispositivo","LAN","Online"]

static func build(hub: Control, parent: VBoxContainer) -> void:
	var sub: String = str(hub.page_state.get("sub","device"))
	if not SUBS.has(sub):
		sub = "device"
	var tabs := Kit.tabs(parent,SUB_NAMES,SUBS.find(sub),func(index):
		hub.leave_room_if_needed()
		hub.navigate("multiplayer",{"sub":SUBS[index]}))
	var frame := Kit.panel(parent,"wood",24,0)
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var content := Kit.scroll(frame,14)
	match sub:
		"device": build_device(hub,content)
		"lan": build_lan(hub,content)
		"online": build_online(hub,content)

static func note(hub: Control, parent: Node) -> void:
	if hub.network_note != "":
		var line := Kit.panel(parent,"leather",10,0)
		Kit.label(line,hub.network_note,16,Kit.EMBER_LIGHT,false,600)

# ---- Passa e gioca ----

static func build_device(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	Kit.title(parent,"Passa e gioca",30)
	Kit.paragraph(parent,"Due persone, un solo dispositivo. Si siedono una di fronte all'altra: ciascuno lancia i suoi dadi e sceglie quali tenere. Le tattiche si scelgono in segreto: dopo la prima scelta compare una schermata per passare il dispositivo. Non serve rete, non si guadagnano XP.",0.0,17,Kit.MUTED)
	Kit.label(parent,"GIOCATORE 1",13,Kit.DIM,false,700)
	var first := LineEdit.new()
	first.text = str(game.profile.data.name)
	first.max_length = 20
	first.custom_minimum_size.y = Kit.scale(48)
	hub.style_field(first)
	parent.add_child(first)
	Kit.label(parent,"GIOCATORE 2",13,Kit.DIM,false,700)
	var second := LineEdit.new()
	second.text = str(hub.page_state.get("second","Giocatore 2"))
	second.max_length = 20
	second.custom_minimum_size.y = Kit.scale(48)
	hub.style_field(second)
	parent.add_child(second)
	Kit.paragraph(parent,"Entrambi giocano con le tattiche che hai scelto tu, così la partita è alla pari.",0.0,15,Kit.DIM)
	var play := Kit.button(parent,"INIZIA LA PARTITA",func():game.start_hotseat(first.text,second.text),"primary",300)
	play.custom_minimum_size.y = Kit.scale(56)

# ---- LAN ----

static func build_lan(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var session: Node = game.lan
	Kit.title(parent,"Sfida nella rete locale",30)
	if session == null or not Platform.lan_available():
		Kit.paragraph(parent,"La sfida LAN usa la rete del tuo dispositivo e non è disponibile nel browser. Per giocare a distanza usa la scheda Online.",0.0,17,Kit.MUTED)
		return
	session.enable_discovery(true)
	note(hub,parent)
	if session.role == "host":
		Kit.label(parent,"STANZA CREATA",13,Kit.DIM,false,700)
		Kit.title(parent,"Codice  "+str(session.room_code),40)
		var ips: PackedStringArray = session.local_addresses()
		Kit.paragraph(parent,"IP · "+(" / ".join(ips) if not ips.is_empty() else "Nessuna rete locale trovata"),0.0,17,Kit.TEXT)
		Kit.paragraph(parent,str(session.status),0.0,16,Kit.MUTED)
		if session.active:
			Kit.button(parent,"INIZIA LA SFIDA",session.start_match,"primary",300)
		Kit.button(parent,"Chiudi la stanza",func():
			session.close()
			hub.navigate("multiplayer",{"sub":"lan"}),"secondary")
	elif session.role == "guest":
		Kit.paragraph(parent,str(session.status),0.0,17,Kit.TEXT)
		Kit.button(parent,"Esci dalla stanza",func():
			session.close()
			hub.navigate("multiplayer",{"sub":"lan"}),"secondary")
	else:
		Kit.paragraph(parent,"Due dispositivi sulla stessa rete. Il primo crea la stanza; il secondo la trova tra le stanze vicine e tocca Entra, senza codice. Per una connessione manuale usa IP e codice.",0.0,17,Kit.MUTED)
		Kit.button(parent,"CREA UNA STANZA",session.host_room,"primary",300)
		Kit.title(parent,"Stanze vicine",22)
		var near := 0
		for ip in session.rooms:
			var entry: Dictionary = session.rooms[ip]
			near += 1
			if str(entry.code) != "":
				Kit.card(parent,"%s" % entry.name,"%s · entra senza codice" % ip,false,func():session.join_room(ip,str(entry.code)),Kit.MOSS,"⚔")
			else:
				Kit.card(parent,"%s" % entry.name,"%s · serve il codice" % ip,false,func():hub.navigate("multiplayer",{"sub":"lan","ip":ip}),Kit.DIM)
		if near == 0:
			Kit.paragraph(parent,"Nessuna stanza vicina trovata per ora. L'elenco si aggiorna da solo.",0.0,16,Kit.DIM)
		Kit.title(parent,"Connessione manuale",22)
		var address := LineEdit.new()
		address.placeholder_text = "IP del creatore · es. 192.168.1.20"
		address.text = str(hub.page_state.get("ip",""))
		address.custom_minimum_size.y = Kit.scale(48)
		hub.style_field(address)
		parent.add_child(address)
		var code := LineEdit.new()
		code.placeholder_text = "Codice stanza · 6 cifre"
		code.max_length = 6
		code.custom_minimum_size.y = Kit.scale(48)
		hub.style_field(code)
		parent.add_child(code)
		Kit.button(parent,"UNISCITI ALLA STANZA",func():session.join_room(address.text.strip_edges(),code.text.strip_edges()),"secondary",300)
	Kit.paragraph(parent,"Se non vi vedete: controllate la rete, disattivate l'isolamento client del router oppure usate un hotspot. Non serve aprire porte su Internet.",0.0,14,Kit.DIM)

# ---- Online ----

static func build_online(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var session: Node = game.lan
	Kit.title(parent,"Partita online",30)
	if session == null or not Platform.online_available():
		Kit.paragraph(parent,"Le partite online non sono disponibili in questa versione del gioco.",0.0,17,Kit.MUTED)
		return
	if session.role == "" and not session.active and session.online.role != "browse":
		session.online_browse()
	note(hub,parent)
	if session.role == "host":
		Kit.label(parent,"STANZA ONLINE APERTA",13,Kit.DIM,false,700)
		Kit.title(parent,"Invito  "+OnlineLink.format_invite(session.invite_code),40)
		Kit.paragraph(parent,str(session.status),0.0,16,Kit.MUTED)
		Kit.button(parent,"COPIA IL CODICE INVITO",func():
			DisplayServer.clipboard_set(OnlineLink.format_invite(session.invite_code))
			hub.toast("Codice invito copiato"),"secondary",300)
		if session.active:
			Kit.button(parent,"INIZIA LA SFIDA",session.start_match,"primary",300)
		Kit.button(parent,"Chiudi la stanza",func():
			session.close()
			hub.navigate("multiplayer",{"sub":"online"}),"ghost")
	elif session.role == "guest":
		Kit.paragraph(parent,str(session.status),0.0,17,Kit.TEXT)
		Kit.button(parent,"Esci dalla stanza",func():
			session.close()
			hub.navigate("multiplayer",{"sub":"online"}),"secondary")
	else:
		Kit.paragraph(parent,"Crea una stanza e passa il codice invito a un amico, oppure rendila pubblica per farla comparire nell'elenco di tutti.",0.0,17,Kit.MUTED)
		var line := Kit.row(parent,10)
		Kit.button(line,"CREA STANZA PUBBLICA",func():session.host_online(true),"primary",260)
		Kit.button(line,"STANZA CON INVITO",func():session.host_online(false),"secondary",230)
		Kit.title(parent,"Entra con un codice",22)
		var join := Kit.row(parent,10)
		var invite := LineEdit.new()
		invite.placeholder_text = "Codice invito · es. K7QF-2M9X"
		invite.max_length = 9
		invite.text = str(hub.page_state.get("invite",""))
		invite.custom_minimum_size = Vector2(Kit.scale(300),Kit.scale(48))
		hub.style_field(invite)
		invite.text_changed.connect(func(value):hub.page_state["invite"] = value)
		join.add_child(invite)
		Kit.button(join,"ENTRA",func():session.join_online_invite(invite.text),"secondary")
		Kit.title(parent,"Stanze online",22)
		var shown := 0
		for id in session.online.rooms:
			var entry: Dictionary = session.online.rooms[id]
			shown += 1
			if entry.free:
				Kit.card(parent,str(entry.name),"Stanza pubblica · tocca per entrare",false,func():session.join_online_room(id),Kit.MOSS,"⚔")
			else:
				Kit.card(parent,str(entry.name),"Stanza piena",false,func():pass,Kit.DIM)
		if shown == 0:
			Kit.paragraph(parent,"Nessuna stanza pubblica trovata per ora. L'elenco si aggiorna da solo; puoi crearne una tu.",0.0,16,Kit.DIM)
		Kit.button(parent,"Cerca di nuovo",session.online.browse,"ghost")
	Kit.paragraph(parent,"Il collegamento è diretto: l'altro giocatore può vedere il tuo indirizzo IP. Per trovarsi si usano tracker pubblici gratuiti di terzi; se non rispondono, la sfida LAN resta disponibile.",0.0,14,Kit.DIM)
