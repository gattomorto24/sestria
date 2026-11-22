extends Control
# Menu principale di SESTRIA 4.8: barra del giocatore (livello, XP, icona → profilo) e cinque schede
# (Campagna, Multigiocatore, Amici, Progressi, Opzioni). Le pagine stanno in page_*.gd; qui c'è la struttura.
const Kit = preload("res://scripts/hub/kit.gd")
const Avatar = preload("res://scripts/hub/avatar.gd")
const Profile = preload("res://scripts/hub/profile_store.gd")
const VIGNETTE = preload("res://assets/ui/hub_vignette.gdshader")
const TORCH = preload("res://assets/ui/hub_torch.gdshader")
const Audio = preload("res://scripts/hub/hub_audio.gd")
const Rules = preload("res://scripts/rules.gd")
const PAGES := ["campaign","multiplayer","friends","progress","options"]
const PAGE_NAMES := {"campaign":"Campagna","multiplayer":"Multigiocatore","friends":"Amici","progress":"Progressi","options":"Opzioni"}
const SCRIPTS := {"campaign":"res://scripts/hub/page_campaign.gd","multiplayer":"res://scripts/hub/page_multiplayer.gd","friends":"res://scripts/hub/page_friends.gd","progress":"res://scripts/hub/page_progress.gd","options":"res://scripts/hub/page_options.gd"}

var game: Node3D
var ui: Control
var portrait := false
var page := "campaign"
var page_state := {}
var content: VBoxContainer
var top_slot: Control
var nav_slot: Control
var modal_layer: Control
var player_card: Control
var toast_label: Label
var toast_tween: Tween
var audio: Node
var network_note := ""
var stage: Control

func setup(owner_game: Node3D, interface: Control, is_portrait: bool) -> void:
	game = owner_game
	ui = interface
	portrait = is_portrait
	Kit.portrait = portrait
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Il tavolo 3D resta visibile e non viene toccato: solo bordi scuri, il bagliore delle fiaccole e qualche favilla.
	var shade := ColorRect.new()
	shade.material = ShaderMaterial.new()
	shade.material.shader = VIGNETTE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var torch := ColorRect.new()
	torch.material = ShaderMaterial.new()
	torch.material.shader = TORCH
	torch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(torch)
	torch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(make_embers())
	stage = Control.new()
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	audio = Audio.new()
	add_child(audio)
	audio.setup(game)
	Kit.audio = audio
	visibility_changed.connect(func():
		var menu_open: bool = visible and not page_state.get("overlay",false)
		if menu_open:
			audio.start_music()
		else:
			audio.stop_music()
		if game.friends != null:
			game.friends.activate(menu_open))

func make_embers() -> CPUParticles2D:
	var embers := CPUParticles2D.new()
	embers.material = CanvasItemMaterial.new()
	embers.material.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	embers.amount = 26
	embers.lifetime = 7.0
	embers.preprocess = 7.0
	embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	embers.emission_rect_extents = Vector2(900,6)
	embers.position = Vector2(640,820)
	embers.direction = Vector2(0,-1)
	embers.spread = 18.0
	embers.gravity = Vector2(6,-10)
	embers.initial_velocity_min = 22.0
	embers.initial_velocity_max = 60.0
	embers.scale_amount_min = 1.6
	embers.scale_amount_max = 3.6
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1,.75,.3,0),Color(1,.65,.2,.85),Color(.9,.3,.1,0)])
	ramp.offsets = PackedFloat32Array([0.0,.25,1.0])
	embers.color_ramp = ramp
	embers.z_index = 5
	return embers

# Gli aggiornamenti cambiano stato in background: se la pagina Sistema è aperta, si ricostruisce.
func refresh_updates() -> void:
	if visible and page == "options" and str(page_state.get("tab","")) == "system" and not is_instance_valid(modal_layer):
		var message := find_child("UpdateMessage",true,false)
		if message and game.updater and game.updater.state in ["downloading","verifying"]:
			message.text = str(game.updater.message)
			var meter := find_child("UpdateMeter",true,false)
			if meter:
				meter.set_value(game.updater.progress,1.0)
			return
		rebuild_deferred()

func rebuild_deferred() -> void:
	if has_meta("rebuild_pending"):
		return
	set_meta("rebuild_pending",true)
	await get_tree().process_frame
	remove_meta("rebuild_pending")
	if visible:
		rebuild()

# Apre il menu su una pagina. `state` passa dati alla pagina (ad esempio la sotto-scheda).
func open(wanted := "", state := {}) -> void:
	if wanted == "" and not has_meta("opened_once"):
		wanted = game.start_page
		set_meta("opened_once",true)
	if wanted != "":
		page = wanted if PAGES.has(wanted) else "campaign"
	page_state = state
	visible = true
	rebuild()

func rebuild() -> void:
	for child in stage.get_children():
		child.queue_free()
	modal_layer = null
	var inset := Kit.margin(stage,22,18,22,18) if not portrait else Kit.margin(stage,14,10,14,10)
	inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var frame := Kit.column(inset,16)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if portrait and ui.has_method("safe_margins"):
		inset.add_theme_constant_override("margin_top",roundi(ui.safe_margins().x)+8)
		inset.add_theme_constant_override("margin_bottom",roundi(ui.safe_margins().y)+8)
	if page_state.get("overlay",false):
		build_overlay_bar(frame)
	else:
		build_top_bar(frame)
	content = Kit.column(frame,0)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if portrait:
		build_bottom_bar(frame)
	load_page()

func load_page() -> void:
	for child in content.get_children():
		child.queue_free()
	var script: GDScript = load(SCRIPTS[page])
	script.build(self,content)
	make_scrollable.call_deferred(content)

# Su Android i tocchi devono arrivare alla zona scorrevole: pulsanti e schede non bloccano il trascinamento.
func make_scrollable(node: Node) -> void:
	if ui and ui.has_method("scrollable") and is_instance_valid(node):
		ui.scrollable(node)

# Se si lascia la scheda con una stanza LAN o online aperta e non iniziata, la stanza si chiude.
func leave_room_if_needed() -> void:
	if game.lan and not game.lan.started and game.lan.role != "":
		game.lan.close()

# Aggiornamento della rete (stanze trovate, ospite arrivato): si ricostruisce la scheda Multigiocatore.
func refresh_network() -> void:
	if visible and page == "multiplayer" and not is_instance_valid(modal_layer):
		rebuild_deferred()

func refresh_friends() -> void:
	if visible and page == "friends" and not is_instance_valid(modal_layer):
		rebuild_deferred()
	elif visible and page != "friends":
		toast("Novità tra i tuoi amici")
		Kit.sfx("tab")

# Un amico ti invita a una partita: entra con il suo codice o rifiuta.
func friend_invited(from_name: String, code: String) -> void:
	if not visible:
		return
	Kit.sfx("confirm")
	var body := modal("%s ti invita a giocare" % from_name,520)
	Kit.paragraph(body,"Ha aperto una stanza online e ti ha mandato il codice invito. Vuoi entrare?",0.0,16,Kit.MUTED)
	var line := Kit.row(body,10)
	Kit.button(line,"ENTRA",func():
		close_modal()
		navigate("multiplayer",{"sub":"online"})
		game.lan.join_online_invite(code),"primary")
	Kit.button(line,"Rifiuta",close_modal,"ghost")

func network_problem(message: String) -> void:
	network_note = message
	Kit.sfx("error")
	if visible and page == "multiplayer":
		rebuild_deferred()
		toast(message)

func navigate(wanted: String, state := {}) -> void:
	if page == "multiplayer" and wanted != "multiplayer":
		leave_room_if_needed()
	page = wanted
	page_state = state
	close_modal()
	rebuild()

# Impostazioni aperte durante la partita: solo un titolo e il ritorno al tavolo.
func build_overlay_bar(parent: Control) -> void:
	var bar := Kit.panel(parent,"bar",14)
	var line := Kit.row(bar,18)
	Kit.button(line,"‹  Torna alla partita",close_overlay,"primary")
	Kit.spacer(line)
	Kit.title(line,"Impostazioni",30)
	Kit.spacer(line)
	build_brand(line,44)

func close_overlay() -> void:
	Kit.sfx("back")
	page_state = {}
	visible = false
	if audio:
		audio.stop_music()
	if game.phase == "menu":
		ui.show_menu()
	elif ui.paused_for_menu:
		ui.close_dialog()

# ---- Barra superiore ----

func build_top_bar(parent: Control) -> void:
	var bar := Kit.panel(parent,"bar",14 if not portrait else 8)
	var line := Kit.row(bar,18)
	player_card = build_player_card(line)
	if not portrait:
		Kit.spacer(line)
		var names := PAGES.map(func(p):return PAGE_NAMES[p] + (" •" if p == "friends" and friend_alert() else ""))
		Kit.tabs(line,names,PAGES.find(page),func(index):
			Kit.sfx("tab")
			navigate(PAGES[index]))
		Kit.spacer(line)
		build_brand(line,46)
	else:
		Kit.spacer(line)
		build_brand(line,40)
	Kit.appear(bar)

func build_brand(parent: Control, side: float) -> void:
	var brand := Kit.row(parent,10)
	var mark := TextureRect.new()
	mark.texture = Kit.MARK
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(Kit.scale(side),Kit.scale(side))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand.add_child(mark)
	if not portrait:
		var word := Kit.title(brand,"Sestria",28)
		word.size_flags_vertical = Control.SIZE_SHRINK_CENTER

func friend_alert() -> bool:
	return game.friends != null and game.friends.pending_incoming() > 0

# Scheda del giocatore: icona con anello di ferro, sigillo con il livello, nome e barra XP. Un tocco apre il profilo.
func build_player_card(parent: Control) -> Control:
	var progression: RefCounted = game.progression
	var level: int = progression.level()
	var holder := Button.new()
	holder.flat = true
	holder.focus_mode = Control.FOCUS_NONE
	holder.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for key in ["normal","hover","pressed","focus"]:
		holder.add_theme_stylebox_override(key,empty)
	holder.pressed.connect(show_profile)
	parent.add_child(holder)
	Kit.juice(holder,"hover","open")
	var line := Kit.row(holder,12)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.custom_minimum_size = Vector2(Kit.scale(290 if not portrait else 250),Kit.scale(74))
	var badge := Control.new()
	badge.custom_minimum_size = Vector2(Kit.scale(76),Kit.scale(76))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(badge)
	var avatar := Avatar.new(Kit.scale(68))
	avatar.configure(game.profile.data.emblem,game.profile.data.color)
	badge.add_child(avatar)
	var seal := Kit.seal(badge,str(level),34)
	seal.position = Vector2(Kit.scale(42),Kit.scale(42))
	var texts := Kit.column(line,2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	Kit.label(texts,str(game.profile.data.name),20,Kit.TEXT,true)
	var xp: int = progression.xp_in_level()
	var needed: int = progression.xp_required(level)
	Kit.meter(texts,xp,needed,16)
	Kit.label(texts,"Livello %d · %s / %s XP" % [level,Kit.format_number(xp),Kit.format_number(needed)],13,Kit.MUTED,false,600)
	return holder

# ---- Barra inferiore (verticale) ----

func build_bottom_bar(parent: Control) -> void:
	var bar := Kit.panel(parent,"bar",4)
	var line := Kit.row(bar,3)
	for index in PAGES.size():
		var entry: String = PAGES[index]
		var selected := entry == page
		var item := Button.new()
		item.text = {"campaign":"Campagna","multiplayer":"Insieme","friends":"Amici","progress":"Progressi","options":"Opzioni"}[entry]
		item.custom_minimum_size.x = 0
		item.focus_mode = Control.FOCUS_NONE
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.custom_minimum_size.y = Kit.scale(48)
		item.add_theme_font_override("font",Kit.display_font(0))
		item.add_theme_font_size_override("font_size",roundi(Kit.scale(11)))
		item.add_theme_stylebox_override("normal",Kit.tex_style("tab_active" if selected else "tab_normal",18,Kit.scale(4),Kit.scale(2),Kit.scale(2)))
		item.add_theme_stylebox_override("hover",Kit.tex_style("tab_active" if selected else "tab_hover",18,Kit.scale(4),Kit.scale(2),Kit.scale(2)))
		item.add_theme_stylebox_override("pressed",Kit.tex_style("tab_pressed",18,Kit.scale(4),Kit.scale(2),Kit.scale(2)))
		for key in ["font_color","font_pressed_color"]:
			item.add_theme_color_override(key,Kit.EMBER_LIGHT if selected else Kit.MUTED)
		item.add_theme_color_override("font_hover_color",Kit.EMBER_LIGHT)
		item.clip_text = true
		item.pressed.connect(func():
			Kit.sfx("tab")
			navigate(entry))
		line.add_child(item)

# ---- Finestre ----

func modal(title: String, width := 560.0) -> VBoxContainer:
	close_modal()
	modal_layer = Control.new()
	modal_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(modal_layer)
	var dim := ColorRect.new()
	dim.color = Color(.02,.03,.09,.66)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	modal_layer.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			pass)
	var center := CenterContainer.new()
	modal_layer.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var card := Kit.panel(center,"high",24,26)
	card.custom_minimum_size.x = minf(Kit.scale(width),size.x-40)
	var column := Kit.column(card,14)
	var head := Kit.row(column,8)
	var heading := Kit.title(head,title,30)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.button(head,"X",close_modal,"ghost")
	Kit.divider(column)
	var scroll_area := ScrollContainer.new()
	scroll_area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_area.custom_minimum_size.y = 0
	column.add_child(scroll_area)
	make_scrollable.call_deferred(column)
	var body := Kit.column(scroll_area,14)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.resized.connect(func():
		if is_instance_valid(scroll_area):
			scroll_area.custom_minimum_size.y = minf(body.get_combined_minimum_size().y,size.y-Kit.scale(210)))
	return body

func close_modal() -> void:
	if is_instance_valid(modal_layer):
		modal_layer.queue_free()
	modal_layer = null

func confirm(title: String, message: String, action_label: String, action: Callable, danger := false) -> void:
	var body := modal(title,520)
	Kit.paragraph(body,message,0.0,16,Kit.MUTED)
	var line := Kit.row(body,10)
	Kit.button(line,action_label,func():
		close_modal()
		action.call(),"danger" if danger else "primary")
	Kit.button(line,"Annulla",close_modal,"ghost")

func toast(message: String) -> void:
	if not is_instance_valid(toast_label):
		toast_label = Kit.label(null,"",15,Kit.TEXT,false,500)
		toast_label.add_theme_stylebox_override("normal",Kit.pad(Kit.box_style(Kit.HIGH,Kit.EMBER,14,1,14),18,10))
		toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		toast_label.z_index = 20
		add_child(toast_label)
	toast_label.text = message
	toast_label.size = Vector2.ZERO
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	toast_label.position = Vector2((size.x-toast_label.get_combined_minimum_size().x)*.5,size.y-Kit.scale(110))
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_tween.tween_interval(2.6)
	toast_tween.tween_property(toast_label,"modulate:a",0.0,.5)

# ---- Regole e tattiche ----

func show_rules() -> void:
	var body := modal("Come si gioca",640)
	var text: String = ui.RULES_TEXT
	if portrait:
		text = text.replace("Clic su un dado per tenerlo. Clic destro per ispezionarlo. Clic sui totem per consultare o attivare una tattica.","Tocca un dado sul tavolo o nella barra per tenerlo. Attiva Ispeziona e tocca un dado per vedere le facce. Tocca i totem per consultare o attivare una tattica.")
	Kit.paragraph(body,text,0.0,17,Kit.MUTED)
	Kit.button(body,"Chiudi",close_modal,"primary")

# Sceglie le tre tattiche (totem) con cui si gioca: si sceglie un posto e poi la tattica da mettervi.
func show_tactics(slot := 0) -> void:
	var body := modal("Le tue tattiche",1000)
	Kit.paragraph(body,"Scegli un posto e poi la tattica da metterci. Le tattiche agiscono per priorità: le prime precedono i dadi, le ultime possono spendere i gettoni appena guadagnati.",0.0,16,Kit.MUTED)
	var slots: BoxContainer = Kit.row(body,10) if not portrait else Kit.column(body,8)
	for i in 3:
		var id: String = game.equipped[i]
		var card := Kit.card(slots,"Posto %d · %s" % [i+1,Rules.FAVOR[id][0]],str(Rules.FAVOR[id][4]) % Rules.FAVOR[id][3][0],i == slot,func():show_tactics(i),Kit.EMBER)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2 if portrait else 4
	grid.add_theme_constant_override("h_separation",roundi(Kit.scale(10)))
	grid.add_theme_constant_override("v_separation",roundi(Kit.scale(10)))
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(grid)
	var ids := Rules.FAVOR.keys()
	for index in ids.size():
		var id: String = ids[index]
		var data: Array = Rules.FAVOR[id]
		var equipped_here: bool = game.equipped.has(id)
		var card := Kit.card(grid,str(data[0]),"Priorità %d · %d / %d / %d gettoni" % [data[1],data[2][0],data[2][1],data[2][2]],equipped_here,func():
			var old: int = game.equipped.find(id)
			if old >= 0:
				game.equipped[old] = game.equipped[slot]
			game.equipped[slot] = id
			game.save_settings()
			Kit.sfx("click")
			show_tactics(slot),Kit.MOSS)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Kit.button(body,"Fatto",close_modal,"primary")

# ---- Profilo ----

func show_profile() -> void:
	var profile: RefCounted = game.profile
	var level: int = game.progression.level()
	var body := modal("Il tuo profilo",640)
	var banner: Dictionary = Profile.BANNERS[profile.data.banner]
	var hero := PanelContainer.new()
	var hero_style: StyleBoxFlat = Kit.box_style(banner.b,banner.a.darkened(.2),14,2)
	hero_style.border_width_bottom = 0
	hero.add_theme_stylebox_override("panel",Kit.pad(hero_style,20,18))
	body.add_child(hero)
	var hero_row := Kit.row(hero,16)
	var avatar := Avatar.new(Kit.scale(86))
	avatar.configure(profile.data.emblem,profile.data.color)
	hero_row.add_child(avatar)
	var info := Kit.column(hero_row,4)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Kit.label(info,str(profile.data.name),26,Kit.TEXT,true)
	Kit.label(info,profile.title_name(level)+" · livello "+str(level),15,Kit.EMBER_LIGHT,false,500)
	var stats: Dictionary = game.stats_store.data if game.stats_store else {}
	var played := int(stats.get("played",0))
	var wins := int(stats.get("wins",0))
	Kit.label(info,"%d partite · %d vittorie" % [played,wins],14,Kit.MUTED)
	var code_row := Kit.row(info,8)
	Kit.label(code_row,"Codice amico",12,Kit.DIM)
	Kit.label(code_row,profile.code(),14,Kit.AZURE,false,600)
	Kit.button(code_row,"Copia",func():
		DisplayServer.clipboard_set(profile.code())
		toast("Codice amico copiato"),"ghost")
	Kit.label(body,"NOME",12,Kit.DIM,false,600)
	var field := LineEdit.new()
	field.text = str(profile.data.name)
	field.max_length = 20
	field.custom_minimum_size.y = Kit.scale(46)
	style_field(field)
	field.text_submitted.connect(func(value):
		profile.update({"name":value})
		show_profile())
	body.add_child(field)
	Kit.label(body,"ICONA",12,Kit.DIM,false,600)
	var emblems := GridContainer.new()
	emblems.columns = 6 if not portrait else 4
	emblems.add_theme_constant_override("h_separation",roundi(Kit.scale(10)))
	emblems.add_theme_constant_override("v_separation",roundi(Kit.scale(10)))
	body.add_child(emblems)
	for index in Avatar.EMBLEM_NAMES.size():
		emblems.add_child(avatar_choice(profile,index,-1))
	Kit.label(body,"COLORE",12,Kit.DIM,false,600)
	var colors := Kit.row(body,10)
	for index in Avatar.COLORS.size():
		colors.add_child(avatar_choice(profile,-1,index))
	Kit.label(body,"SFONDO DEL PROFILO",12,Kit.DIM,false,600)
	var banners := Kit.row(body,8)
	for index in Profile.BANNERS.size():
		var entry: Dictionary = Profile.BANNERS[index]
		var chip := Kit.button(banners,str(entry.name),func():
			profile.update({"banner":index})
			show_profile(),"primary" if profile.data.banner == index else "secondary")
		chip.custom_minimum_size.y = Kit.scale(40)
		chip.add_theme_font_size_override("font_size",roundi(Kit.scale(13)))
	Kit.label(body,"TITOLO",12,Kit.DIM,false,600)
	var titles := Kit.row(body,8)
	for entry in Profile.TITLES:
		var unlocked: bool = int(entry.level) <= level
		var item := Kit.button(titles,str(entry.name) if unlocked else "🔒 liv. %d" % int(entry.level),func():
			profile.update({"title":entry.id})
			show_profile(),"primary" if profile.data.title == entry.id else "secondary")
		item.disabled = not unlocked
		item.add_theme_font_size_override("font_size",roundi(Kit.scale(13)))
	var footer := Kit.row(body,10)
	Kit.button(footer,"Salva e chiudi",func():
		profile.update({"name":field.text})
		close_modal()
		rebuild(),"primary")
	var google = game.account
	if google != null and google.has_method("available"):
		Kit.button(footer,"Account Google" if google.profile.is_empty() else "Google: "+str(google.profile.get("name","")),func():
			google.sign_in(),"ghost")

func style_field(field: LineEdit) -> void:
	field.add_theme_font_override("font",Kit.body_font(500))
	field.add_theme_font_size_override("font_size",roundi(Kit.scale(17)))
	field.add_theme_color_override("font_color",Kit.TEXT)
	field.add_theme_color_override("font_placeholder_color",Kit.DIM)
	field.add_theme_color_override("caret_color",Kit.EMBER)
	var normal: StyleBoxFlat = Kit.pad(Kit.box_style(Color("#1c1008"),Kit.LINE,8,2),14,8)
	var focus: StyleBoxFlat = Kit.pad(Kit.box_style(Color("#1c1008"),Kit.EMBER,8,2),14,8)
	field.add_theme_stylebox_override("normal",normal)
	field.add_theme_stylebox_override("focus",focus)

# Pulsante tondo con l'icona o il colore da scegliere nel profilo.
func avatar_choice(profile: RefCounted, emblem: int, color: int) -> Control:
	var button := Button.new()
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var selected: bool = (emblem >= 0 and profile.data.emblem == emblem) or (color >= 0 and profile.data.color == color)
	var frame := Kit.box_style(Color.TRANSPARENT,Kit.EMBER if selected else Color.TRANSPARENT,99,3)
	for key in ["normal","hover","pressed","focus"]:
		button.add_theme_stylebox_override(key,frame)
	var side := Kit.scale(54 if emblem >= 0 else 34)
	button.custom_minimum_size = Vector2(side+6,side+6)
	var avatar := Avatar.new(side)
	avatar.configure(emblem if emblem >= 0 else profile.data.emblem,color if color >= 0 else profile.data.color,false)
	avatar.position = Vector2(3,3)
	button.add_child(avatar)
	button.pressed.connect(func():
		if emblem >= 0:
			profile.update({"emblem":emblem})
		else:
			profile.update({"color":color})
		show_profile())
	return button
