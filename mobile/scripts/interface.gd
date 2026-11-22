extends Control
const Rules = preload("res://scripts/rules.gd")
const OnlineLink = preload("res://scripts/online_link.gd")
const SafeSpace = preload("res://scripts/safe_space.gd")
const Kit = preload("res://scripts/hub/kit.gd")
const IVORY := Color("#f6e8c6")
const GOLD := Color("#ffd98a")
const MINT := Color("#9cc878")
const MUTED := Color("#d2bd90")
const INK := Color("#20120a")
const FRAME = preload("res://assets/ui/panel.png")
const PRIMARY = preload("res://assets/ui/primary.png")
const SECONDARY = preload("res://assets/ui/secondary.png")
const HOVER = preload("res://assets/ui/hover.png")
const PRESSED = preload("res://assets/ui/selected.png")
const DISABLED = preload("res://assets/ui/disabled.png")
var game: Node3D
var title_font: Font
var body_font: Font
var hub: Control
var screen: Control
var dialog: Control
var context_popup: Control
var paused_for_menu := false
var inspect_mode := false
var margins := Vector4(24,24,24,24)
var simulated_safe := Vector4.ZERO
var header: VBoxContainer
var dock: VBoxContainer
var feedback: Label
var phase_label: Label
var hp_labels: Array[Label] = []
var token_labels: Array[Label] = []
var meters: Array[ProgressBar] = []
var phase_marks: Array[Label] = []
var favor_row: HBoxContainer
var primary_action: Button
var action_callback := Callable()
var hud_signature := ""
var active_stage := 0
var menu_mode := true
var screen_buttons: Array[Button] = []
var inspector_viewport: SubViewport
var icon_cache := {}
var lan_panel := false
var online_panel := false
var invite_text := ""
var profile_panel := false
var pass_panel := false
var updates_panel := false
var updates_signature := ""
var updates_message: Label
var updates_meter: ProgressBar
var updates_refresh_pending := false
var lan_note := ""
var pass_note := ""
var scroll_guard := 0

func setup(owner_game: Node3D) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	Kit.portrait = true
	title_font = Kit.display_font(1)
	body_font = Kit.body_font(500)
	var palette := Theme.new()
	palette.default_font = body_font
	palette.default_font_size = 30
	palette.set_color("font_color","Label",IVORY)
	palette.set_font_size("font_size","Button",25)
	palette.set_font("font","Button",title_font)
	palette.set_color("font_color","Button",IVORY)
	palette.set_color("font_hover_color","Button",GOLD)
	palette.set_color("font_pressed_color","Button",GOLD)
	palette.set_color("font_disabled_color","Button",Kit.DIM)
	for state in ["normal","hover","pressed","focus","disabled"]:
		palette.set_stylebox(state,"Button",chrome({"normal":SECONDARY,"hover":HOVER,"pressed":PRESSED,"focus":HOVER,"disabled":DISABLED}[state]))
	palette.set_stylebox("panel","PanelContainer",chrome(FRAME,24))
	palette.set_stylebox("panel","PopupMenu",style(INK,GOLD,16))
	theme = palette
	resized.connect(layout)
	layout.call_deferred()

func style(fill: Color, border: Color, padding := 20) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(16)
	s.content_margin_left = padding
	s.content_margin_right = padding
	s.content_margin_top = padding
	s.content_margin_bottom = padding
	return s

func label(parent: Node, text: String, font_size := 28, color := IVORY, display := false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font",title_font if display else body_font)
	node.add_theme_font_size_override("font_size",font_size)
	node.add_theme_color_override("font_color",color)
	node.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func text(parent: Node, content: String, font_size := 28, color := MUTED, width_reduction := 0) -> Label:
	var node := label(parent,content,font_size,color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.clip_text = true
	node.custom_minimum_size.x = size.x-margins.x-margins.z-48-width_reduction
	node.custom_minimum_size.y = ceilf(body_font.get_multiline_string_size(content,HORIZONTAL_ALIGNMENT_LEFT,node.custom_minimum_size.x,font_size).y)+8
	node.size_flags_horizontal = SIZE_EXPAND_FILL
	return node

func vbox(parent: Node, gap := 16) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func hbox(parent: Node, gap := 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation",gap)
	node.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func button(parent: Node, text_value: String, callback: Callable, primary := false) -> Button:
	var node := Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 96
	node.size_flags_horizontal = SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_NONE
	node.clip_text = true
	node.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if primary:
		node.add_theme_stylebox_override("normal",chrome(PRIMARY))
		node.add_theme_stylebox_override("hover",chrome(HOVER))
		node.add_theme_color_override("font_color",IVORY)
		node.add_theme_color_override("font_hover_color",IVORY)
	node.pressed.connect(func():
		# A tap that stops a fling, or the end of a drag, must never activate what lies underneath.
		if Time.get_ticks_msec() < scroll_guard:
			return
		game.haptic()
		callback.call())
	parent.add_child(node)
	return node

func icon(path: String) -> Texture2D:
	if not icon_cache.has(path):
		icon_cache[path] = load(path)
	return icon_cache[path]

func place(node: Control, rect: Rect2) -> void:
	node.position = rect.position
	node.size = rect.size

func update_margins() -> void:
	margins = Vector4(24,28,24,28)
	if simulated_safe != Vector4.ZERO:
		margins = simulated_safe
	elif OS.has_feature("android"):
		margins = SafeSpace.measure(size,Vector2(DisplayServer.window_get_size()),Rect2(DisplayServer.get_display_safe_area()),DisplayServer.get_display_cutouts())

func layout() -> void:
	update_margins()
	if not is_instance_valid(screen):
		return
	var width := size.x-margins.x-margins.z
	if not menu_mode:
		place(header,Rect2(margins.x,margins.y,width,0))
		var dock_height := maxf(190,dock.get_combined_minimum_size().y)
		place(dock,Rect2(margins.x,size.y-margins.w-dock_height,width,dock_height))
	if is_instance_valid(dialog):
		fit_sheet.call_deferred(dialog)
	if is_instance_valid(context_popup):
		fit_sheet.call_deferred(context_popup)

func board_region() -> Rect2:
	var top := margins.y+250
	var bottom := size.y-margins.w-290
	if is_instance_valid(header) and not menu_mode:
		top = margins.y+header.get_combined_minimum_size().y+16
		bottom = dock.position.y-16
	return Rect2(margins.x,top,size.x-margins.x-margins.z,maxf(100,bottom-top))

func clear_screen() -> void:
	close_dialog()
	close_context()
	if hub != null:
		hub.visible = false
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(screen)
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	screen_buttons.clear()
	hud_signature = ""

func wash(parent: Node, menu := false) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0,.28,.52,.72,1])
	gradient.colors = PackedColorArray([Color("#071316"),Color(.027,.067,.078,.95 if menu else .15),Color(.027,.067,.078,.05),Color(.027,.067,.078,.9 if menu else .1),Color("#071316")])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(.5,0)
	texture.fill_to = Vector2(.5,1)
	var art := TextureRect.new()
	art.texture = texture
	art.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(art)
	art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func ensure_hub() -> void:
	if hub == null:
		hub = preload("res://scripts/hub/hub.gd").new()
		add_child(hub)
		hub.setup(game,self,true)

# Margini sicuri (alto, basso) per il menu: tacca, barra dei gesti.
func safe_margins() -> Vector2:
	return Vector2(margins.y,margins.w)

func show_menu() -> void:
	clear_screen()
	menu_mode = true
	update_margins()
	ensure_hub()
	hub.open()

# Le impostazioni stanno nella scheda Opzioni del menu; durante una partita si aprono sopra al tavolo.
func show_settings(active = 0) -> void:
	ensure_hub()
	var tab: String = active if active is String else ["audio","graphics","system","game"][clampi(active,0,3)]
	hub.open("options",{"tab":tab,"overlay":game.phase != "menu"})

func refresh_profile() -> void:
	if hub != null and hub.visible:
		hub.rebuild_deferred()

const RULES_TEXT := preload("res://scripts/rules_text.gd").TEXT

# Scorciatoie verso le schede del menu (usate dall'app e dai collaudi).
func show_lan() -> void:
	ensure_hub()
	hub.open("multiplayer",{"sub":"lan"})

func show_online() -> void:
	ensure_hub()
	hub.open("multiplayer",{"sub":"online"})

func show_updates() -> void:
	ensure_hub()
	hub.open("options",{"tab":"system"})

func show_statistics() -> void:
	ensure_hub()
	hub.open("progress")

func show_pass() -> void:
	ensure_hub()
	hub.open("progress")

func show_profile() -> void:
	ensure_hub()
	hub.open("campaign")
	hub.show_profile()

func buy_upgrade(id: String) -> void:
	game.progression.purchase(id)
	hub.navigate("progress",{})

func show_rules() -> void:
	ensure_hub()
	hub.show_rules()

func refresh_updates() -> void:
	if hub != null:
		hub.refresh_updates()

func refresh_friends() -> void:
	if hub != null:
		hub.refresh_friends()

func friend_invited(from_name: String, code: String) -> void:
	if hub != null:
		hub.friend_invited(from_name,code)

func refresh_lan() -> void:
	if hub != null and not game.lan.started:
		hub.refresh_network()

func lan_problem(message: String) -> void:
	if hub != null:
		hub.network_problem(message)

func match_layout() -> void:
	clear_screen()
	menu_mode = false
	wash(screen)
	hp_labels = []
	token_labels = []
	meters = []
	phase_marks = []
	header = vbox(screen,12)
	var navigation := hbox(header)
	var back := button(navigation,"Ⅱ",ask_leave)
	back.custom_minimum_size = Vector2(96,88)
	back.size_flags_horizontal = SIZE_SHRINK_BEGIN
	phase_label = label(navigation,"MANCHE 01",27,GOLD,true)
	phase_label.size_flags_horizontal = SIZE_EXPAND_FILL
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var view := button(navigation,"⌖",toggle_view)
	view.custom_minimum_size = Vector2(96,88)
	view.size_flags_horizontal = SIZE_SHRINK_END
	var enemy := PanelContainer.new()
	header.add_child(enemy)
	stat_card(enemy,1)
	var phases := hbox(header,6)
	for name in ["LANCIO","SCELTA","TATTICHE","SCONTRO"]:
		var item := label(phases,name,20,MUTED)
		item.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		item.size_flags_horizontal = SIZE_EXPAND_FILL
		phase_marks.append(item)
	feedback = label(header,"",25,IVORY)
	feedback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dock = vbox(screen,10)
	var own := PanelContainer.new()
	dock.add_child(own)
	stat_card(own,0)
	favor_row = hbox(dock,10)
	for id in game.equipped:
		var entry := button(favor_row,Rules.FAVOR[id][0].split("’")[0],game.inspect_favor.bind(0,id))
		entry.custom_minimum_size.y = 88
		entry.add_theme_font_size_override("font_size",24)
	primary_action = button(dock,"LANCIA",invoke_action,true)
	primary_action.custom_minimum_size.y = 100
	layout()

func stat_card(parent: Node, side: int) -> void:
	parent.add_theme_stylebox_override("panel",chrome(FRAME,14))
	var column := vbox(parent,6)
	var row := hbox(column,10)
	var nameplate := label(row,"TU" if side == 0 else "RIVALE",22,MUTED)
	nameplate.size_flags_horizontal = SIZE_EXPAND_FILL
	var hp := label(row,"15",30,IVORY)
	label(row,"/15",22,MUTED)
	var token := label(row,"✦  0",28,GOLD)
	var bar := ProgressBar.new()
	bar.max_value = 15
	bar.value = 15
	bar.show_percentage = false
	bar.custom_minimum_size.y = 4
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	for key in ["background","fill"]:
		bar.add_theme_stylebox_override(key,style(MINT if key == "fill" else Color("#29413f"),Color.TRANSPARENT,0))
	column.add_child(bar)
	if side == 1:
		hp_labels.append(hp)
		token_labels.append(token)
		meters.append(bar)
	else:
		hp_labels.push_front(hp)
		token_labels.push_front(token)
		meters.push_front(bar)

func toggle_view() -> void:
	game.overview = not game.overview
	feedback.text = "Vista completa" if game.overview else "Inquadratura dinamica"

func blocks_table(point: Vector2) -> bool:
	if menu_mode or is_instance_valid(dialog) or is_instance_valid(context_popup):
		return true
	return header.get_global_rect().has_point(point) or dock.get_global_rect().has_point(point)

func stats(hp: Array, gold: Array, round_no: int, first: int) -> void:
	if hp_labels.size() != 2:
		return
	for side in 2:
		hp_labels[side].text = str(hp[side])
		hp_labels[side].add_theme_color_override("font_color",Color("#ffab91") if hp[side] <= 4 else IVORY)
		token_labels[side].text = "✦  %d" % gold[side]
		meters[side].value = hp[side]
	phase_label.text = "%02d  /  %s" % [round_no,"INIZI TU" if first == 0 else "INIZIA IL RIVALE"]

func sync() -> void:
	if menu_mode or not is_instance_valid(primary_action):
		return
	var signature: String = game.phase+str(game.targets)+str(game.attempts)
	for cube in game.cubes[game.acting]:
		signature += str(cube.selected)
	if hud_signature == signature:
		return
	hud_signature = signature
	favor_row.visible = game.phase in ["favor","target","between"]
	layout.call_deferred()
	primary_action.disabled = not action_callback.is_valid() or game.phase in ["ai","busy","sorting"]
	if game.phase == "select":
		var count: int = game.cubes[game.acting].filter(func(c):return c.selected and not c.committed).size()
		primary_action.text = "TIENI %d DADI  →" % count if count > 0 else "RILANCIA TUTTI  →"
		set_stage(1)

func set_stage(index: int) -> void:
	active_stage = index
	for i in phase_marks.size():
		phase_marks[i].add_theme_color_override("font_color",GOLD if i == index else MUTED)

func action(message: String, action_name: String, callback: Callable) -> void:
	close_context()
	feedback.text = message
	action_callback = callback
	primary_action.text = action_name.to_upper()+"  →"
	primary_action.disabled = false
	hud_signature = ""

func invoke_action() -> void:
	if action_callback.is_valid() and not primary_action.disabled:
		primary_action.disabled = true
		action_callback.call()

func status(message: String) -> void:
	close_dialog()
	close_context()
	feedback.text = message
	action_callback = Callable()
	primary_action.text = "IN CORSO…"
	primary_action.disabled = true

func favor_stage() -> void:
	set_stage(2)
	rebuild_favor_row()
	action(("%s: attiva una tattica o conserva i gettoni" % game.player_names[game.acting]) if game.hotseat else "Attiva una tattica o conserva i gettoni","Conserva e combatti",game.resolve.bind({}))

# I pulsanti delle tattiche seguono il lato che gioca adesso (Passa e gioca).
func rebuild_favor_row() -> void:
	if not is_instance_valid(favor_row):
		return
	for child in favor_row.get_children():
		favor_row.remove_child(child)
		child.queue_free()
	for id in game.loadout(game.acting):
		var entry := button(favor_row,Rules.FAVOR[id][0].split("’")[0],game.inspect_favor.bind(game.acting,id))
		entry.custom_minimum_size.y = 88
		entry.add_theme_font_size_override("font_size",24)

# Passa e gioca: schermata di passaggio, così il secondo giocatore sceglie la tattica senza vedere l'altra.
func handoff(next_name: String, ready: Callable) -> void:
	var body := sheet("Passa il dispositivo")
	text(body,"Ora tocca a %s. La tattica appena scelta resta segreta fino alla risoluzione: consegna il telefono e premi il pulsante." % next_name,28,IVORY)
	button(body,"SONO %s, PRONTO" % next_name.to_upper(),func():
		close_dialog()
		ready.call(),true)
	Kit.sfx("open")

func finish_hotseat() -> void:
	var winner: int = game.rules.winner
	var body := sheet("Vince %s" % game.player_names[winner])
	text(body,"Pietre rimaste · %s %d / %s %d" % [game.player_names[0],game.rules.hp[0],game.player_names[1],game.rules.hp[1]],28,IVORY)
	button(body,"RIVINCITA",func():
		close_dialog()
		game.start_hotseat(game.player_names[0],game.player_names[1]),true)
	button(body,"Torna al menu",game.menu)

func finish(victory: bool) -> void:
	if game.hotseat:
		finish_hotseat()
		return
	var campaign: bool = game.active_campaign != ""
	var body := sheet("Vittoria!" if victory else "La partita è persa")
	Kit.sfx("confirm" if victory else "back")
	text(body,"Pietre rimaste · Tu %d / Rivale %d" % game.rules.hp,28,IVORY)
	if game.lan and game.lan.active:
		if game.lan.role=="host":
			button(body,"UNA NUOVA SFIDA",game.rematch_lan,true)
		else:
			text(body,"Il creatore della stanza può iniziare una nuova sfida.")
	else:
		var reward: Dictionary = game.progression.last_reward
		if reward.has("error"):
			text(body,str(reward.error),25,GOLD)
		elif victory and reward.has("xp"):
			text(body,"+%d XP" % reward.xp,34,MINT)
			if int(reward.levels) > 0:
				text(body,"LIVELLO %d → %d  ·  +%d PUNTI" % [reward.from_level,reward.to_level,reward.points],27,GOLD)
			text(body,"Livello %d · %d / %d XP" % [game.progression.level(),game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],25)
			Kit.meter(body,game.progression.xp_in_level(),game.progression.xp_required(game.progression.level()),20)
		elif not victory:
			text(body,"Gli XP si guadagnano con le vittorie. I tuoi progressi e punti restano al sicuro.",25)
		if campaign:
			var index: int = game.campaigns.find(game.active_campaign)
			if index >= 0:
				var item: Dictionary = game.campaigns.campaigns[index]
				text(body,"Campagna «%s» · %s · serie %d" % [item.name,game.campaigns.chapter_title(int(item.chapter)),int(item.streak)],25)
			button(body,"PROSSIMA PARTITA" if victory else "RIPROVA",func():
				close_dialog()
				game.start_campaign(game.active_campaign),true)
		else:
			button(body,"UN'ALTRA PARTITA",func():
				close_dialog()
				game.start_quick(),true)
		button(body,"I miei progressi",func():
			game.menu()
			hub.open("progress"))
	button(body,"Torna al menu",game.menu)

func selection_count(value: int, limit: int) -> void:
	feedback.text = "Seconda occasione · %d / %d bersagli" % [value,limit]

func describe_event(event: Dictionary) -> void:
	feedback.text = event.text+ (" · %d" % event.amount if event.amount > 0 else "")

func combat_detail(title: String, amount: int, damage: bool) -> void:
	feedback.text = "%s  ·  %d %s" % [title,amount,"pietre" if damage else "parate"]

func sheet(title: String, context := false) -> VBoxContainer:
	# Rebuilding the same sheet (a toggle, a selection, a refresh) keeps the reader where they were.
	var restore := -1
	var current: Control = context_popup if context else dialog
	if is_instance_valid(current) and current.get_meta("sheet_title","") == title and current.has_node("Card/Scroll"):
		restore = int(current.get_node("Card/Scroll").scroll_vertical)
	close_dialog(true)
	close_context()
	var root := Control.new()
	root.set_meta("sheet_title",title)
	add_child(root)
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(.01,.04,.05,.88)
	root.add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var card := PanelContainer.new()
	card.name = "Card"
	card.add_theme_stylebox_override("panel",chrome(FRAME,24))
	root.add_child(card)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_guard = 0
	scroll.scroll_started.connect(func():scroll_guard = 1 << 60)
	scroll.scroll_ended.connect(func():scroll_guard = Time.get_ticks_msec()+260)
	card.add_child(scroll)
	var body := vbox(scroll,20)
	body.name = "Body"
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	var handle := HSeparator.new()
	handle.mouse_filter = MOUSE_FILTER_IGNORE
	body.add_child(handle)
	var heading := label(body,title,37,IVORY,true)
	heading.clip_text = true
	if context:
		context_popup = root
	else:
		dialog = root
	fit_sheet.call_deferred(root)
	if restore > 0:
		restore_pass_scroll.call_deferred(root,restore)
	return body

func restore_pass_scroll(root: Control, position_y: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(root) and root.has_node("Card/Scroll"):
		root.get_node("Card/Scroll").scroll_vertical = position_y

func scrollable(node: Node) -> void:
	# Godot sends a touch to the control under the finger and stops at the first MOUSE_FILTER_STOP.
	# Cards and buttons must let the press reach the ScrollContainer; the scroll deadzone then separates
	# a tap (button fires) from a drag (NOTIFICATION_SCROLL_BEGIN cancels the press).
	# Sliders, text fields and the 3D inspector keep their own drag handling.
	for child in node.get_children():
		if child is Control:
			var item: Control = child
			var interactive: bool = item is SubViewportContainer or item is LineEdit or item is Slider or item is SpinBox
			if not interactive and item.mouse_filter == MOUSE_FILTER_STOP:
				item.mouse_filter = MOUSE_FILTER_PASS
		scrollable(child)

func fit_sheet(root: Control) -> void:
	if not is_instance_valid(root):
		return
	var card: PanelContainer = root.get_node("Card")
	var scroll: ScrollContainer = card.get_node("Scroll")
	var body: VBoxContainer = scroll.get_node("Body")
	scrollable(body)
	var width := size.x-margins.x-margins.z
	body.custom_minimum_size.x = width-48
	card.size.x = width
	body.size.x = width-48
	await get_tree().process_frame
	if not is_instance_valid(root):
		return
	# The wrapped line count is only exact once the label has its final width: never let a paragraph be clipped.
	for item in body.find_children("*","Label",true,false):
		var paragraph: Label = item
		if paragraph.autowrap_mode != TextServer.AUTOWRAP_OFF and paragraph.get_line_count() > 0:
			var needed := paragraph.get_line_count()*(paragraph.get_line_height()+paragraph.get_theme_constant("line_spacing"))+8
			if needed > paragraph.custom_minimum_size.y:
				paragraph.custom_minimum_size.y = needed
	await get_tree().process_frame
	if not is_instance_valid(root):
		return
	var height := minf(body.get_combined_minimum_size().y,size.y-margins.y-margins.w-100)
	scroll.custom_minimum_size = Vector2(width-48,height)
	card.position = Vector2(margins.x,size.y-margins.w-height-48)
	card.size = Vector2(width,height+48)

func close_dialog(keep_pause := false) -> void:
	scroll_guard = 0
	if (lan_panel or online_panel) and not keep_pause and game.lan and not game.lan.started:
		game.lan.close()
	lan_panel=false
	online_panel=false
	profile_panel=false
	pass_panel=false
	updates_panel=false
	if is_instance_valid(dialog):
		remove_child(dialog)
		dialog.queue_free()
		dialog = null
	if paused_for_menu and not keep_pause:
		paused_for_menu = false
		get_tree().paused = false

func close_context() -> void:
	scroll_guard = 0
	inspector_viewport = null
	if is_instance_valid(context_popup):
		remove_child(context_popup)
		context_popup.queue_free()
		context_popup = null

func coin_prompt() -> void:
	var body := sheet("Chi sfida il destino?")
	text(body,"La moneta decide l’iniziativa. Scegli il tuo segno.")
	var row := hbox(body)
	button(row,"TESTA",game.toss.bind(0),true)
	button(row,"CROCE",game.toss.bind(1))

func ask_leave() -> void:
	game.touch_active = false
	paused_for_menu = true
	get_tree().paused = true
	var body := sheet("Un momento di tregua")
	text(body,"La saga ti aspetta.")
	button(body,"RIPRENDI",close_dialog,true)
	button(body,"Impostazioni",show_settings)
	button(body,"Lascia il tavolo",game.menu)

func favor_popup(id: String, actionable: bool) -> void:
	var data: Array = Rules.FAVOR[id]
	var body := sheet(data[0],true)
	text(body,"TATTICA  /  PRIORITÀ %d" % data[1],22,GOLD)
	var sacrifice := [1 if game.rules.hp[game.acting] > 1 else 0]
	if actionable and id in ["reserve","exchange"]:
		text(body,"Pietre da offrire",26)
		var row := hbox(body)
		var amount := label(row,str(sacrifice[0]),40,GOLD)
		amount.size_flags_horizontal = SIZE_EXPAND_FILL
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var minus := button(row,"−",func():sacrifice[0]=maxi(0,sacrifice[0]-1);amount.text=str(sacrifice[0]))
		minus.custom_minimum_size.x = 100
		var plus := button(row,"+",func():sacrifice[0]=mini(game.rules.hp[game.acting]-1,sacrifice[0]+1);amount.text=str(sacrifice[0]))
		plus.custom_minimum_size.x = 100
	for level in 3:
		text(body,data[4] % data[3][level],27,IVORY)
		var price := "%d GETTONI  ·  LIVELLO %d" % [data[2][level],level+1]
		if actionable:
			var entry := button(body,price,func():close_context();game.pick_favor(id,level,sacrifice[0]),true)
			var available: int = game.rules.gold[game.acting]
			if data[1] > 5:
				available += game.rules.marks(game.acting)
			entry.disabled = available < data[2][level]
		else:
			text(body,price,23,GOLD)
	button(body,"Chiudi",close_context)

func inspect_die(id: int, face: int) -> void:
	var data := Rules.die(id,face)
	var body := sheet(Rules.NAMES[data.kind],true)
	text(body,"DADO %02d  /  TRASCINA PER RUOTARE" % [id+1],22,GOLD)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(560,280)
	container.stretch = true
	body.add_child(container)
	inspector_viewport = SubViewport.new()
	inspector_viewport.size = Vector2i(560,280)
	inspector_viewport.own_world_3d = true
	inspector_viewport.transparent_bg = true
	inspector_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(inspector_viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_energy = .8
	inspector_viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40,-25,0)
	inspector_viewport.add_child(light)
	var camera := Camera3D.new()
	camera.position = Vector3(0,1.4,2)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.35
	inspector_viewport.add_child(camera)
	camera.current = true
	camera.look_at(Vector3.ZERO)
	var cube: Node3D = load("res://scenes/die.tscn").instantiate()
	inspector_viewport.add_child(cube)
	cube.collision_layer = 0
	cube.collision_mask = 0
	cube.setup(game.table,id,0)
	cube.arrange(Vector3.ZERO,face,0)
	container.gui_input.connect(func(event):
		var motion := Vector2.ZERO
		if event is InputEventScreenDrag:
			motion=event.relative
		elif event is InputEventMouseMotion and event.button_mask == MOUSE_BUTTON_MASK_LEFT:
			motion=event.relative
		cube.rotate_y(motion.x*.012)
		cube.rotate_x(motion.y*.012)
		if motion != Vector2.ZERO and is_instance_valid(inspector_viewport):
			inspector_viewport.render_target_update_mode=SubViewport.UPDATE_ONCE)
	var row := hbox(body,10)
	for index in 6:
		var tile := TextureRect.new()
		var info := Rules.die(id,index)
		tile.texture = icon("res://assets/icons/face_%d%s.svg" % [info.kind,"_gold" if info.gold else ""])
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tile.custom_minimum_size = Vector2(84,84)
		tile.modulate = Color("#eed8af")
		var backing := PanelContainer.new()
		backing.add_theme_stylebox_override("panel",style(Color("#e9d5b4"),GOLD,4))
		backing.size_flags_horizontal = SIZE_EXPAND_FILL
		row.add_child(backing)
		backing.add_child(tile)
	text(body,["Danno corpo a corpo","Danno a distanza","Blocca un’ascia","Blocca una freccia","Ruba gettoni dopo lo scontro"][data.kind],28,IVORY)
	if data.gold:
		text(body,"✦ Bordo dorato: genera un gettone.",26,GOLD)
	button(body,"Torna al tavolo",close_context,true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		game.go_back()
		get_viewport().set_input_as_handled()

# Le vecchie texture (verde e oro) sono sostituite dalla pelle rustica del nuovo kit.
func chrome(texture: Texture2D, padding := 22) -> StyleBoxTexture:
	var name := "leather_normal"
	var edge := 22.0
	if texture == PRIMARY or texture == PRESSED:
		name = "brass_normal"
	elif texture == HOVER:
		name = "leather_hover"
	elif texture == DISABLED:
		name = "leather_disabled"
	elif texture == FRAME:
		name = "wood_panel"
		edge = 40.0
	var skin: StyleBoxTexture = Kit.tex_style(name,edge,0).duplicate()
	skin.content_margin_left = maxf(padding,edge*.5)
	skin.content_margin_right = maxf(padding,edge*.5)
	skin.content_margin_top = maxf(12,edge*.4) if texture != FRAME else padding+8
	skin.content_margin_bottom = maxf(12,edge*.4) if texture != FRAME else padding+8
	return skin

func show_diagnostics() -> void:
	var body := sheet("Diagnostica locale")
	var report: String = "SESTRIA · versione "+game.updater.current_version+"\n"
	if game.lan.android_bridge:
		report+=game.lan.android_bridge.getDiagnosticReport()
	else:
		report+="Sistema: "+OS.get_name()+"\nLAN: "+game.lan.role+" · fase "+game.phase
	text(body,"Questo rapporto resta sul dispositivo. Non contiene account, email o codice della stanza. Puoi copiarlo per segnalare una chiusura imprevista.",25)
	text(body,report.left(10000),22,IVORY)
	button(body,"Copia rapporto",func():DisplayServer.clipboard_set(report))
	button(body,"Torna alle impostazioni",show_settings,true)
