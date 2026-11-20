extends Control
const Rules = preload("res://scripts/rules.gd")
const SafeSpace = preload("res://scripts/safe_space.gd")
const TITLE = preload("res://assets/fonts/Cinzel.ttf")
const BODY = preload("res://assets/fonts/Manrope.ttf")
const IVORY := Color("#f3e7d2")
const GOLD := Color("#dcb982")
const MINT := Color("#85e7cb")
const MUTED := Color("#9cb4b3")
const INK := Color("#091b20")
const FRAME = preload("res://assets/ui/panel.png")
const PRIMARY = preload("res://assets/ui/primary.png")
const SECONDARY = preload("res://assets/ui/secondary.png")
const HOVER = preload("res://assets/ui/hover.png")
const PRESSED = preload("res://assets/ui/selected.png")
const DISABLED = preload("res://assets/ui/disabled.png")
var game: Node3D
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
	var palette := Theme.new()
	palette.default_font = BODY
	palette.default_font_size = 28
	palette.set_color("font_color","Label",IVORY)
	palette.set_font_size("font_size","Button",27)
	palette.set_font("font","Button",TITLE)
	palette.set_color("font_color","Button",IVORY)
	palette.set_color("font_hover_color","Button",IVORY)
	palette.set_color("font_pressed_color","Button",IVORY)
	palette.set_color("font_disabled_color","Button",MUTED)
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
	node.add_theme_font_override("font",TITLE if display else BODY)
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
	node.custom_minimum_size.y = ceilf(BODY.get_multiline_string_size(content,HORIZONTAL_ALIGNMENT_LEFT,node.custom_minimum_size.x,font_size).y)+8
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

func show_menu() -> void:
	clear_screen()
	menu_mode = true
	update_margins()
	wash(screen,true)
	var banner := TextureRect.new()
	var crop := AtlasTexture.new()
	crop.atlas = preload("res://assets/ui/brand_banner.svg")
	crop.region = Rect2(0,0,368,220)
	banner.texture = crop
	banner.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	banner.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	banner.mouse_filter = MOUSE_FILTER_IGNORE
	screen.add_child(banner)
	place(banner,Rect2(size.x/2-250,margins.y-40,500,298))
	var sigil := preload("res://scripts/sigil.gd").new()
	screen.add_child(sigil)
	place(sigil,Rect2(size.x/2-240,size.y*.36-180,480,480))
	sigil.modulate.a = .25
	var top := vbox(screen,10)
	var title_offset := 250-maxf(0,margins.y-40)*.6
	place(top,Rect2(margins.x,margins.y+title_offset,size.x-margins.x-margins.z,0))
	var edition := label(top,"S E I   D A D I .   M I L L E   S T R A T E G I E .",20,GOLD)
	edition.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title := label(top,"SESTRIA",88,IVORY,true)
	top.move_child(title,0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := label(top,"Il destino è nelle tue mani.",28,MUTED)
	subtitle.visible = margins.y < 80
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bottom := vbox(screen,16)
	place(bottom,Rect2(margins.x,size.y-margins.w-524,size.x-margins.x-margins.z,0))
	var start := button(bottom,"INIZIA LA SAGA  →",show_play_modes,true)
	start.custom_minimum_size.y = 112
	var difficulty := button(bottom,"SFIDA  ·  "+["ESPLORATORE","GUERRIERO","MAESTRO"][game.difficulty],show_difficulty)
	difficulty.custom_minimum_size.y = 88
	var nav := hbox(bottom,12)
	button(nav,"Tattiche",show_equipped)
	button(nav,"Regole",show_rules)
	button(nav,"Opzioni",show_settings)
	var extras := hbox(bottom,12)
	for entry in [["Statistiche",show_statistics],["Pass · %d" % game.progression.points(),show_pass],["Profilo",show_profile]]:
		button(extras,entry[0],entry[1]).add_theme_font_size_override("font_size",24)
	var progress_card := PanelContainer.new()
	progress_card.add_theme_stylebox_override("panel",style(Color("#10252b"),GOLD,12))
	bottom.add_child(progress_card)
	var progress_content := vbox(progress_card,8)
	var progress_row := hbox(progress_content)
	var current_level := label(progress_row,"LIVELLO %d" % game.progression.level(),23,GOLD,true)
	current_level.size_flags_horizontal = SIZE_EXPAND_FILL
	label(progress_row,"%d / %d XP" % [game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],23,IVORY)
	xp_bar(progress_content)

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
	for cube in game.cubes[0]:
		signature += str(cube.selected)
	if hud_signature == signature:
		return
	hud_signature = signature
	favor_row.visible = game.phase in ["favor","target","between"]
	layout.call_deferred()
	primary_action.disabled = not action_callback.is_valid() or game.phase in ["ai","busy","sorting"]
	if game.phase == "select":
		var count: int = game.cubes[0].filter(func(c):return c.selected and not c.committed).size()
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
	action("Attiva una tattica o conserva i gettoni", "Conserva e combatti",game.resolve.bind({}))

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
	var height := minf(body.get_combined_minimum_size().y,size.y-margins.y-margins.w-100)
	scroll.custom_minimum_size = Vector2(width-48,height)
	card.position = Vector2(margins.x,size.y-margins.w-height-48)
	card.size = Vector2(width,height+48)

func close_dialog(keep_pause := false) -> void:
	scroll_guard = 0
	if lan_panel and not keep_pause and game.lan and not game.lan.started:
		game.lan.close()
	lan_panel=false
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
	button(body,"Audio e prestazioni",show_settings)
	button(body,"Come si gioca",show_rules)
	button(body,"Lascia il tavolo",game.menu)

func show_difficulty() -> void:
	var body := sheet("Scegli la sfida")
	text(body,"La sfida scelta è la base della saga. Ai livelli 4, 8 e 12 il rivale diventa più forte; il Pass ti aiuta a prepararti.",25)
	for i in 3:
		button(body,["ESPLORATORE · Impara il rituale","GUERRIERO · Una sfida equilibrata","MAESTRO · Nessuna concessione"][i],func():
			game.difficulty = i
			game.save_settings()
			show_menu(),i == game.difficulty)
	button(body,"Indietro",close_dialog)

func show_rules() -> void:
	var body := sheet("Come si gioca a Sestria")
	text(body,"01  /  IL DESTINO",23,GOLD)
	text(body,"Sei dadi, quindici pietre. Sopravvivi al rivale. Ogni manche offre fino a tre lanci: tocca i dadi 3D che vuoi tenere, poi conferma. Tieni premuto un dado per esaminarlo e ruotarlo.")
	text(body,"02  /  IL COMBATTIMENTO",23,GOLD)
	text(body,"L’ascia incontra l’elmo. La freccia incontra lo scudo. Ogni attacco senza difesa costa una pietra. Le mani contrapposte si annullano; quelle rimaste rubano gettoni dopo il combattimento.")
	text(body,"03  /  LE TATTICHE",23,GOLD)
	text(body,"I bordi dorati generano gettoni. Equipaggia tre tattiche e attivale al momento giusto: costo e priorità sono sempre indicati. Le tattiche tardivi possono usare i gettoni appena guadagnati.")
	text(body,"04  /  IL TOCCO",23,GOLD)
	text(body,"Tocco: seleziona. Pressione prolungata: ispeziona. Il mirino in alto alterna la vista completa e l’inquadratura ravvicinata. Indietro chiude la finestra; la pausa sospende l’intera partita.")
	button(body,"Ho capito",close_dialog,true)

func show_settings() -> void:
	var body := sheet("Il tuo ritmo")
	text(body,"SESTRIA · VERSIONE "+game.updater.current_version,23,GOLD)
	button(body,"AGGIORNAMENTI",show_updates)
	button(body,"Diagnostica locale",show_diagnostics)
	text(body,"AUDIO",22,GOLD)
	volume_slider(body,"Musica",game.music_volume,game.change_music)
	volume_slider(body,"Effetti",game.effects_volume,func(value):game.effects_volume=value;game.save_settings())
	text(body,"PRESTAZIONI",22,GOLD)
	for i in 3:
		button(body,["Bilanciata · 60 fps","Risparmio · 30 fps","Qualità · 60 fps"][i],func():
			game.graphics_mode=i
			game.adaptive_level=0
			game.apply_mobile_quality()
			game.save_settings()
			show_settings(),i == game.graphics_mode)
	text(body,"I valori indicano il limite dei fotogrammi. La fluidità effettiva dipende dal telefono.",23,MUTED)
	button(body,"Adatta al dispositivo  ·  "+("SÌ" if game.adaptive else "NO"),func():game.adaptive=not game.adaptive;game.save_settings();show_settings())
	button(body,"Vibrazione  ·  "+("SÌ" if game.haptics else "NO"),func():game.haptics=not game.haptics;game.save_settings();show_settings())
	button(body,"Fatto",close_dialog,true)

func volume_slider(parent: Node, title: String, value: float, callback: Callable) -> void:
	var row := hbox(parent)
	var caption := label(row,title,26)
	caption.custom_minimum_size.x = 130
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 1
	slider.step = .01
	slider.value = value
	slider.custom_minimum_size = Vector2(300,96)
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(slider)
	var rail := style(Color("#334e50"),Color.TRANSPARENT,4)
	var fill := style(GOLD,Color.TRANSPARENT,4)
	slider.add_theme_stylebox_override("slider",rail)
	slider.add_theme_stylebox_override("grabber_area",fill)
	slider.value_changed.connect(callback)

func show_equipped(slot := 0, selected := "") -> void:
	var body := sheet("Le tue tattiche")
	text(body,"Tre tattiche. Scegli un posto, poi il dio che porterai al tavolo.",26)
	var slots := hbox(body,8)
	for i in 3:
		button(slots,"%d · %s" % [i+1,Rules.FAVOR[game.equipped[i]][0].split("’")[0]],show_equipped.bind(i),i == slot)
	if selected != "":
		var info: Array = Rules.FAVOR[selected]
		text(body,info[0],29,GOLD)
		text(body,info[4] % info[3][0],26,IVORY)
		text(body,"Priorità %s   /   Costi %s · %s · %s" % [info[1],info[2][0],info[2][1],info[2][2]],23)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	body.add_child(grid)
	for id in Rules.FAVOR:
		var entry := button(grid,Rules.FAVOR[id][0],func():
			var old: int = game.equipped.find(id)
			if old >= 0:
				game.equipped[old]=game.equipped[slot]
			game.equipped[slot]=id
			game.save_settings()
			show_equipped(slot,id),id in game.equipped)
		entry.custom_minimum_size.x = (size.x-margins.x-margins.z-60)/2
		entry.add_theme_font_size_override("font_size",25)
	button(body,"Scelte confermate",close_dialog,true)

func favor_popup(id: String, actionable: bool) -> void:
	var data: Array = Rules.FAVOR[id]
	var body := sheet(data[0],true)
	text(body,"TATTICA  /  PRIORITÀ %d" % data[1],22,GOLD)
	var sacrifice := [1 if game.rules.hp[0] > 1 else 0]
	if actionable and id in ["reserve","exchange"]:
		text(body,"Pietre da offrire",26)
		var row := hbox(body)
		var amount := label(row,str(sacrifice[0]),40,GOLD)
		amount.size_flags_horizontal = SIZE_EXPAND_FILL
		amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var minus := button(row,"−",func():sacrifice[0]=maxi(0,sacrifice[0]-1);amount.text=str(sacrifice[0]))
		minus.custom_minimum_size.x = 100
		var plus := button(row,"+",func():sacrifice[0]=mini(game.rules.hp[0]-1,sacrifice[0]+1);amount.text=str(sacrifice[0]))
		plus.custom_minimum_size.x = 100
	for level in 3:
		text(body,data[4] % data[3][level],27,IVORY)
		var price := "%d GETTONI  ·  LIVELLO %d" % [data[2][level],level+1]
		if actionable:
			var entry := button(body,price,func():close_context();game.pick_favor(id,level,sacrifice[0]),true)
			var available: int = game.rules.gold[0]
			if data[1] > 5:
				available += game.rules.marks(0)
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

func finish(victory: bool) -> void:
	var body := sheet("Partita vinta" if victory else "La saga continua")
	text(body,"VITTORIA" if victory else "SCONFITTA",24,GOLD)
	text(body,"Pietre rimaste · Tu %d / Rivale %d" % game.rules.hp,28,IVORY)
	if game.lan and game.lan.active:
		if game.lan.role=="host":
			button(body,"UNA NUOVA SFIDA LAN",game.rematch_lan,true)
		else:
			text(body,"Il creatore della stanza può iniziare una nuova sfida.")
	else:
		var reward: Dictionary = game.progression.last_reward
		if reward.has("error"):
			text(body,str(reward.error),25,GOLD)
		elif victory and reward.has("xp"):
			text(body,"+%d XP  ·  SAGA OFFLINE" % reward.xp,30,MINT)
			if int(reward.levels) > 0:
				text(body,"LIVELLO %d → %d  ·  +%d PUNTI PASS" % [reward.from_level,reward.to_level,reward.points],27,GOLD)
			text(body,"Livello %d · %d / %d XP" % [game.progression.level(),game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],25)
			xp_bar(body)
		elif not victory:
			text(body,"Gli XP si guadagnano con le vittorie. I tuoi progressi e punti restano al sicuro.",25)
		button(body,"PASS · %d PUNTI DISPONIBILI" % game.progression.points(),show_pass)
		button(body,"UNA NUOVA SAGA",func():close_dialog();game.prepare(),true)
	button(body,"Torna al menu",game.menu)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		game.go_back()
		get_viewport().set_input_as_handled()

func chrome(texture: Texture2D, padding := 22) -> StyleBoxTexture:
	var skin := StyleBoxTexture.new()
	skin.texture = texture
	skin.texture_margin_left = 29
	skin.texture_margin_right = 29
	skin.texture_margin_top = 25
	skin.texture_margin_bottom = 25
	skin.content_margin_left = padding
	skin.content_margin_right = padding
	skin.content_margin_top = 12 if texture != FRAME else padding
	skin.content_margin_bottom = 12 if texture != FRAME else padding
	return skin

func show_play_modes() -> void:
	var body := sheet("Scegli il tuo rivale")
	var run: Dictionary = game.progression.create_run(game.difficulty)
	text(body,"SAGA OFFLINE · LIVELLO %d" % run.level,23,GOLD)
	text(body,"%s · Rivale %s · %d gettoni iniziali. Vittoria: %d XP." % [game.progression.TITLES[run.tier],["Esploratore","Guerriero","Maestro"][run.ai_level],run.enemy_gold,game.progression.victory_xp(run)],26,IVORY)
	button(body,"CONTINUA LA SAGA",game.prepare,true)
	text(body,"Vinci, sali di livello e ottieni 2 punti Pass a ogni avanzamento. I potenziamenti si attivano dalla prossima saga.",25)
	button(body,"SFIDA LAN · STESSO WI-FI",show_lan)
	text(body,"La LAN collega due dispositivi sulla stessa rete o hotspot. Regole standard, senza buff o ricompense XP. Nessun account obbligatorio, nessun server di gioco.",25)
	button(body,"Indietro",close_dialog)

func xp_bar(parent: Node) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = game.progression.xp_required(game.progression.level())
	bar.value = game.progression.xp_in_level()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	for key in ["background","fill"]:
		bar.add_theme_stylebox_override(key,style(MINT if key=="fill" else Color("#29413f"),Color.TRANSPARENT,0))
	parent.add_child(bar)
	return bar

func show_pass(scroll_y := 0) -> void:
	if game.phase not in ["menu","end"] or (game.lan and game.lan.active):
		return
	var progress: RefCounted = game.progression
	var body := sheet("Il Pass della saga")
	pass_panel = true
	var overview := hbox(body)
	var level_title := label(overview,"LIVELLO %d" % progress.level(),28,GOLD,true)
	level_title.size_flags_horizontal = SIZE_EXPAND_FILL
	label(overview,"%d PUNTI" % progress.points(),28,MINT,true)
	text(body,"%d / %d XP al prossimo livello · +2 punti" % [progress.xp_in_level(),progress.xp_required(progress.level())],24)
	xp_bar(body)
	text(body,"Solo saga offline. Ogni grado acquistato resta attivo nelle saghe successive. Puoi riassegnare tutti i punti gratis.",25)
	button(body,"Torna al risultato" if game.phase=="end" else "Torna al menu",close_pass)
	if not pass_note.is_empty():
		text(body,pass_note,25,MINT)
		pass_note = ""
	for id: String in progress.ORDER:
		var upgrade: Dictionary = progress.UPGRADES[id]
		var rank_index: int = progress.rank_of(id)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel",chrome(FRAME,18))
		body.add_child(card)
		var content := vbox(card,12)
		var heading := label(content,"%s  /  %s" % [upgrade.rune,upgrade.name],26,GOLD,true)
		heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		heading.custom_minimum_size.x = size.x-margins.x-margins.z-84
		text(content,"GRADO %d / %d" % [rank_index,upgrade.costs.size()],21,MINT if rank_index>0 else MUTED,36)
		text(content,upgrade.description,25,IVORY,36)
		var status: String = progress.purchase_status(id)
		if rank_index < upgrade.costs.size():
			text(content,"Prossimo grado · %d punti · Livello %d" % [upgrade.costs[rank_index],upgrade.levels[rank_index]],22,MUTED,36)
			var buy := button(content,"ACQUISTA · %d PUNTI" % upgrade.costs[rank_index] if status.is_empty() else status,buy_upgrade.bind(id),status.is_empty())
			buy.add_theme_font_size_override("font_size",24)
			buy.disabled = not status.is_empty()
		else:
			text(content,"TUTTI I GRADI ACQUISITI",22,MINT,36)
	text(body,"LA SAGA DIVENTA PIÙ DIFFICILE",23,GOLD)
	text(body,"Livello 4: rivale almeno Guerriero, +1 gettone iniziale. Livello 8: almeno Maestro, +2 gettoni. Livello 12: Maestro con più analisi tattica, +3 gettoni. Dadi e tiri restano equi.",25)
	text(body,"XP per vittoria: 100 / 130 / 160 secondo la sfida scelta, +10 per ogni soglia della saga raggiunta, più Esperienza sul campo. Le sconfitte e le partite interrotte non assegnano XP.",25)
	if progress.spent_points() > 0:
		button(body,"RIASSEGNA · %d PUNTI" % progress.spent_points(),confirm_refund)
	button(body,"Torna al risultato" if game.phase=="end" else "Torna al menu",close_pass,true)
	restore_pass_scroll.call_deferred(dialog,scroll_y)

func restore_pass_scroll(root: Control, position_y: int) -> void:
	# The sheet is laid out over a couple of frames; wait until its range can hold the saved position.
	for attempt in 12:
		await get_tree().process_frame
		if not is_instance_valid(root) or not root.has_node("Card/Scroll"):
			return
		var scroll: ScrollContainer = root.get_node("Card/Scroll")
		var bar := scroll.get_v_scroll_bar()
		if bar.max_value-bar.page >= position_y or attempt == 11:
			scroll.scroll_vertical = position_y
			return

func buy_upgrade(id: String) -> void:
	if game.phase not in ["menu","end"]:
		return
	var scroll_y := int(dialog.get_node("Card/Scroll").scroll_vertical)
	var error: Error = game.progression.purchase(id)
	pass_note = "%s · grado %d acquisito. Attivo dalla prossima saga." % [game.progression.UPGRADES[id].name,game.progression.rank_of(id)] if error==OK else "Acquisto non salvato. Nessun punto è stato speso."
	show_pass(scroll_y)

func confirm_refund() -> void:
	var body := sheet("Riscrivi il tuo destino")
	pass_panel = true
	text(body,"Restituisci i %d punti spesi e azzeri i gradi del Pass. Livello e XP restano invariati. La riassegnazione è gratuita." % game.progression.spent_points(),27,IVORY)
	button(body,"RESTITUISCI I PUNTI",func():
		var error: Error = game.progression.refund()
		pass_note = "Punti restituiti. Scegli il tuo nuovo percorso." if error==OK else "Riassegnazione non salvata. I potenziamenti restano attivi."
		show_pass(),true)
	button(body,"Mantieni i potenziamenti",show_pass)

func close_pass() -> void:
	if game.phase == "end":
		finish(game.rules.winner==0)
	else:
		show_menu()

func show_statistics() -> void:
	var data: Dictionary=game.stats_store.data
	var body := sheet("Le tue imprese")
	text(body,"STATISTICHE SU QUESTO DISPOSITIVO",22,GOLD)
	var grid := GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",24)
	grid.add_theme_constant_override("v_separation",20)
	body.add_child(grid)
	for pair in [["Partite",str(int(data.played))],["Vittorie",str(int(data.wins))],["Percentuale vittorie","%d%%" % game.stats_store.win_rate()],["Serie migliore",str(int(data.best_streak))],["Danni inflitti",str(int(data.damage_dealt))],["Danni subiti",str(int(data.damage_taken))],["Attacchi parati",str(int(data.blocked))],["Gettoni rubati",str(int(data.tokens_stolen))],["Lanci",str(int(data.rolls))],["Tempo di gioco","%d min" % (int(data.seconds)/60)]]:
		var card := PanelContainer.new()
		card.custom_minimum_size.x=(size.x-margins.x-margins.z-72)/2
		grid.add_child(card)
		var item := vbox(card,4)
		var caption := label(item,pair[0],22,MUTED)
		caption.clip_text=true
		label(item,pair[1],36,GOLD,true)
	text(body,"Manche concluse: %d · Partite interrotte: %d" % [data.rounds,data.abandoned],24)
	for mode in ["solo","lan"]:
		var info: Dictionary=data.modes.get(mode,{"played":0,"wins":0})
		text(body,"%s · %d partite / %d vittorie" % ["Computer" if mode=="solo" else "LAN",info.played,info.wins],26,IVORY)
	if not data.favors.is_empty():
		text(body,"FAVORI INVOCATI",22,GOLD)
		for id in data.favors:
			text(body,"%s · %d" % [Rules.FAVOR[id][0] if Rules.FAVOR.has(id) else id,data.favors[id]],24)
	text(body,"ULTIME PARTITE",22,GOLD)
	if data.history.is_empty():
		text(body,"La tua prima impresa deve ancora essere scritta.")
	for match_info in data.history.slice(0,12):
		text(body,"%s · %s · %d manche / %d:%02d" % ["Vittoria" if match_info.victory else "Sconfitta","LAN" if match_info.mode=="lan" else "Computer",match_info.rounds,int(match_info.seconds)/60,int(match_info.seconds)%60],25,IVORY)
	button(body,"Torna al menu",close_dialog,true)

func show_profile() -> void:
	var body := sheet("Il tuo profilo")
	profile_panel=true
	var account: Node=game.account
	if account.profile.is_empty():
		text(body,"Gioca come ospite oppure collega il tuo profilo Google. La LAN funziona anche senza accesso.",28)
		var login := button(body,"Accedi con Google",account.sign_in)
		for state in ["normal","hover","pressed","focus","disabled"]:
			var google_style := style(Color("#f2f2f2") if state in ["pressed","disabled"] else Color.WHITE,Color("#747775"),20)
			google_style.set_corner_radius_all(8)
			login.add_theme_stylebox_override(state,google_style)
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
			login.add_theme_color_override(key,Color("#1f1f1f"))
		login.add_theme_color_override("font_disabled_color",Color("#747775"))
		login.add_theme_font_override("font",BODY)
		login.disabled=account.busy or not account.available()
		if ResourceLoader.exists("res://assets/ui/google_logo.png"):
			login.icon=load("res://assets/ui/google_logo.png")
			login.add_theme_constant_override("icon_max_width",40)
		if not account.available():
			text(body,"Il pulsante Google è disponibile nella versione Android configurata.",24)
	else:
		text(body,str(account.profile.name),36,GOLD)
		text(body,str(account.profile.email),26,IVORY)
		button(body,"Esci dall’account Google",account.sign_out)
	if account.message!="":
		text(body,account.message,25,GOLD)
	text(body,"Nome e profilo vengono salvati solo qui. Statistiche e partite non sono caricate su cloud; l’accesso Google richiede Internet.",24)
	button(body,"Fatto",close_dialog,true)

func refresh_profile() -> void:
	if profile_panel:
		show_profile()

func show_lan() -> void:
	var body := sheet("Sfida nella rete locale")
	lan_panel=true
	var session: Node=game.lan
	session.enable_discovery(true)
	if lan_note!="":
		text(body,lan_note,25,GOLD)
	if session.role=="host":
		text(body,"STANZA CREATA",22,GOLD)
		text(body,"Codice · "+session.room_code,38,IVORY)
		var ips: PackedStringArray=session.local_addresses()
		text(body,"IP · "+(" / ".join(ips) if not ips.is_empty() else "Nessuna rete locale trovata"),26)
		text(body,session.status,27)
		if session.active:
			button(body,"INIZIA LA SFIDA",session.start_match,true)
	elif session.role=="guest":
		text(body,session.status,27,IVORY)
	else:
		text(body,"Due dispositivi sullo stesso Wi-Fi o hotspot. Il primo crea la stanza, il secondo usa l’IP e il codice mostrati.",27)
		button(body,"CREA STANZA",session.host_room,true)
		var address_input := LineEdit.new()
		address_input.placeholder_text="IP del creatore · es. 192.168.1.20"
		address_input.custom_minimum_size.y=96
		address_input.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_DEFAULT
		body.add_child(address_input)
		var code_input := LineEdit.new()
		code_input.placeholder_text="Codice stanza · 6 cifre"
		code_input.max_length=6
		code_input.custom_minimum_size.y=96
		code_input.virtual_keyboard_type=LineEdit.KEYBOARD_TYPE_NUMBER
		body.add_child(code_input)
		button(body,"UNISCITI ALLA STANZA",func():session.join_room(address_input.text.strip_edges(),code_input.text.strip_edges()))
		if not session.rooms.is_empty():
			text(body,"STANZE VICINE",22,GOLD)
			for ip in session.rooms:
				var entry: Dictionary=session.rooms[ip]
				button(body,entry.name+" · "+ip,func():address_input.text=ip)
		button(body,"Aggiorna stanze vicine",show_lan)
	text(body,"Se non vi vedete: controllate la rete, disattivate l’isolamento client del router oppure usate un hotspot. Non serve aprire porte su Internet.",23)
	button(body,"Chiudi stanza" if session.role!="" else "Indietro",close_dialog)

func refresh_lan() -> void:
	if lan_panel and not game.lan.started:
		show_lan()

func lan_problem(message: String) -> void:
	lan_note=message
	if game.phase=="menu":
		show_lan()

func show_updates() -> void:
	var update: Node=game.updater
	var body := sheet("Aggiornamenti")
	updates_panel=true
	updates_signature=update.state+str(update.release.get("version",""))
	text(body,"SESTRIA · VERSIONE "+update.current_version,24,GOLD)
	updates_message=text(body,update.message,27,IVORY)
	if update.state in ["downloading","verifying","ready"]:
		updates_meter=ProgressBar.new()
		updates_meter.max_value=1
		updates_meter.value=update.progress
		updates_meter.custom_minimum_size.y=18
		updates_meter.show_percentage=false
		body.add_child(updates_meter)
	if update.state=="available":
		text(body,"NUOVA VERSIONE · "+str(update.release.version),24,MINT)
		if not str(update.release.notes).is_empty():
			text(body,str(update.release.notes),24)
		button(body,"SCARICA AGGIORNAMENTO",update.download_update,true)
	elif update.state=="ready":
		if game.phase in ["menu","end"]:
			button(body,"INSTALLA AGGIORNAMENTO",update.install_update,true)
		else:
			text(body,"Torna al menu dopo la partita per installare l’aggiornamento.",25)
	elif update.state in ["checking","downloading"]:
		button(body,"Annulla",update.cancel)
	elif update.state!="verifying":
		button(body,"VERIFICA NUOVI AGGIORNAMENTI",update.check_updates,true)
	text(body,"Gli aggiornamenti provengono dalle release pubbliche di GitHub. Prima dell’installazione controlliamo integrità, versione e firma. La conferma finale viene richiesta da Android.",24)
	button(body,"Apri le release su GitHub",func():OS.shell_open(update.RELEASES))
	if not update.last_checked.is_empty():
		text(body,"Ultima verifica · "+update.last_checked,22)
	button(body,"Torna alle impostazioni",show_settings)

func refresh_updates() -> void:
	if not updates_panel:
		return
	var update: Node=game.updater
	if updates_signature!=update.state+str(update.release.get("version","")):
		if not updates_refresh_pending:
			updates_refresh_pending=true
			apply_updates_refresh.call_deferred()
	elif is_instance_valid(updates_message):
		updates_message.text=update.message
		if is_instance_valid(updates_meter):
			updates_meter.value=update.progress

func apply_updates_refresh() -> void:
	updates_refresh_pending=false
	if updates_panel and is_instance_valid(dialog):
		show_updates()

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
