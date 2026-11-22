extends RefCounted
# Scheda Amici: il tuo codice, aggiungere un amico, richieste ricevute e inviate, elenco con presenza online e inviti.
const Kit = preload("res://scripts/hub/kit.gd")
const Avatar = preload("res://scripts/hub/avatar.gd")
const Profile = preload("res://scripts/hub/profile_store.gd")

static func build(hub: Control, parent: VBoxContainer) -> void:
	var game: Node3D = hub.game
	var service = game.friends
	var layout: BoxContainer = Kit.row(parent,16) if not hub.portrait else Kit.column(parent,12)
	layout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var left := Kit.panel(layout,"wood",22,0)
	left.custom_minimum_size.x = 0.0 if hub.portrait else 420.0
	var side := Kit.scroll(left,12)
	Kit.title(side,"Il tuo codice",24)
	var code_box := Kit.panel(side,"parchment",14,0)
	var code_column := Kit.column(code_box,4)
	var code := Kit.label(code_column,game.profile.code(),26,Kit.INK,true)
	code.remove_theme_color_override("font_shadow_color")
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint := Kit.paragraph(code_column,"Dallo ai tuoi amici: con questo codice ti trovano e ti scrivono una richiesta.",0.0,14,Kit.INK_SOFT)
	hint.remove_theme_color_override("font_shadow_color")
	Kit.button(side,"Copia il codice",func():
		DisplayServer.clipboard_set(game.profile.code())
		hub.toast("Codice amico copiato"),"secondary")
	if service == null:
		Kit.paragraph(side,"Gli amici usano le partite online, che non sono disponibili in questa versione.",0.0,15,Kit.MUTED)
		return
	Kit.title(side,"Aggiungi un amico",24)
	var field := LineEdit.new()
	field.placeholder_text = "Codice amico · es. K7QF-2M9X-ABCD"
	field.max_length = 14
	field.text = str(hub.page_state.get("draft",""))
	field.custom_minimum_size.y = Kit.scale(48)
	hub.style_field(field)
	field.text_changed.connect(func(value):hub.page_state["draft"] = value)
	side.add_child(field)
	var send := func():
		var problem: String = service.add_friend(field.text)
		if problem.is_empty():
			hub.toast("Richiesta inviata: arriverà quando il tuo amico è online")
			hub.page_state["draft"] = ""
			hub.navigate("friends",hub.page_state)
		else:
			hub.toast(problem)
			Kit.sfx("error")
	field.text_submitted.connect(func(_t):send.call())
	Kit.button(side,"INVIA LA RICHIESTA",send,"primary")
	Kit.paragraph(side,"Non servono account né server: la richiesta passa direttamente dal tuo dispositivo a quello del tuo amico e si consegna quando è online. Se non lo è, riprova da sola.",0.0,14,Kit.DIM)
	var account = game.account
	if account != null and account.has_method("available"):
		Kit.title(side,"Account Google",24)
		Kit.paragraph(side,"Collega il tuo account Google per riconoscere i tuoi dispositivi. Il salvataggio di amici e progressi su Google Drive è in preparazione.",0.0,14,Kit.MUTED)
		Kit.button(side,"Accedi con Google" if account.profile.is_empty() else "Collegato: "+str(account.profile.get("name","")),func():account.sign_in(),"secondary")
	var right := Kit.panel(layout,"wood",22,0)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var list := Kit.scroll(right,12)
	var store: RefCounted = service.store
	if not store.incoming.is_empty():
		Kit.title(list,"Richieste ricevute",24)
		for entry in store.incoming:
			var card := person_card(list,entry,false,"ti ha chiesto l'amicizia")
			var actions := card.get_meta("actions") as HBoxContainer
			Kit.button(actions,"Accetta",func():
				service.store.accept(entry.id)
				Kit.sfx("confirm")
				hub.navigate("friends",hub.page_state),"primary")
			Kit.button(actions,"Rifiuta",func():
				service.store.decline(entry.id)
				hub.navigate("friends",hub.page_state),"ghost")
	Kit.title(list,"I tuoi amici (%d)" % store.friends.size(),24)
	if store.friends.is_empty():
		Kit.paragraph(list,"Non hai ancora amici. Aggiungi qualcuno con il suo codice.",0.0,16,Kit.DIM)
	for entry in store.friends:
		var online: bool = service.is_online(entry.id)
		var card := person_card(list,entry,online,"online" if online else "non visto di recente")
		var actions := card.get_meta("actions") as HBoxContainer
		var invite := Kit.button(actions,"Invita",func():invite_friend(hub,entry),"primary" if online else "secondary")
		Kit.button(actions,"Rimuovi",func():
			hub.confirm("Rimuovere l'amico?","«%s» sparirà dalla tua lista e verrà avvisato appena possibile." % entry.name,"Rimuovi",func():
				service.store.remove(entry.id)
				hub.navigate("friends",hub.page_state),true),"ghost")
	if not store.outgoing.is_empty():
		Kit.title(list,"Richieste inviate",24)
		for entry in store.outgoing:
			var card := person_card(list,{"id":entry.id,"name":Profile.format_code(entry.id),"emblem":0,"color":6},false,"in attesa che sia online")
			var actions := card.get_meta("actions") as HBoxContainer
			Kit.button(actions,"Annulla",func():
				service.store.cancel(entry.id)
				hub.navigate("friends",hub.page_state),"ghost")

# Riga di una persona: icona (con puntino di presenza), nome, stato e un contenitore per i pulsanti.
static func person_card(parent: Node, entry: Dictionary, online: bool, status: String) -> PanelContainer:
	var card := Kit.panel(parent,"leather",14,0)
	var line := Kit.row(card,14)
	var avatar := Avatar.new(Kit.scale(54))
	avatar.configure(int(entry.emblem),int(entry.color))
	if online:
		avatar.badge = ""
	line.add_child(avatar)
	var texts := Kit.column(line,2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.label(texts,str(entry.name),19,Kit.TEXT,true)
	var state := Kit.row(texts,6)
	var dot := ColorRect.new()
	dot.color = Kit.MOSS if online else Kit.DIM
	dot.custom_minimum_size = Vector2(Kit.scale(9),Kit.scale(9))
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	state.add_child(dot)
	Kit.label(state,status,14,Kit.MOSS if online else Kit.MUTED,false,600)
	var actions := Kit.row(line,8)
	card.set_meta("actions",actions)
	return card

# Invito: si apre (o si riusa) una stanza privata e si manda il codice all'amico.
static func invite_friend(hub: Control, entry: Dictionary) -> void:
	var game: Node3D = hub.game
	var session: Node = game.lan
	if session == null:
		return
	if session.role != "host" or str(session.invite_code).is_empty():
		session.host_online(false)
	var code := str(session.invite_code)
	if code.is_empty():
		hub.toast("Non riesco ad aprire la stanza online. Riprova tra poco.")
		return
	game.friends.invite(entry.id,code)
	hub.toast("Invito in arrivo a %s: aspetta nella stanza" % entry.name)
	hub.navigate("multiplayer",{"sub":"online"})
