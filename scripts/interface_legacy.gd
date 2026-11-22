extends Control
const OnlineLink = preload("res://scripts/online_link.gd")

const Rules = preload("res://scripts/rules.gd")
const Platform = preload("res://scripts/platform.gd")
const TITLES := ["Esploratore","Guerriero","Maestro"]
const TITLE_FONT = preload("res://assets/fonts/Cinzel.ttf")
const BODY_FONT = preload("res://assets/fonts/Manrope.ttf")
const MINT := Color("#85e7cb")
const IVORY := Color("#f1e0c4")
const MUTED := Color("#c4beb0")
const GOLD := Color("#d9ae70")
const TURQUOISE := Color("#7febdf")
const PRIMARY = preload("res://assets/ui/primary.png")
const HOVER = preload("res://assets/ui/hover.png")
const SECONDARY = preload("res://assets/ui/secondary.png")
const SELECTED = preload("res://assets/ui/selected.png")
const DISABLED = preload("res://assets/ui/disabled.png")
const FRAME = preload("res://assets/ui/panel.png")
const DIVIDER = preload("res://assets/ui/divider.png")
const BANNER = preload("res://assets/ui/brand_banner.svg")
const HEART = preload("res://assets/ui/stone_icon.png")
const TOKEN = preload("res://assets/ui/favor_icon.png")
const GEM = preload("res://assets/ui/gem.png")
const TAB = preload("res://assets/ui/tab.png")
const TAB_ACTIVE = preload("res://assets/ui/tab_active.png")
const SLIDER = preload("res://assets/ui/slider_bg.png")
const SLIDER_FILL = preload("res://assets/ui/slider_fill.png")
const RULES_TEXT := "Ogni giocatore dispone di sei dadi e quindici pietre. La moneta decide l’iniziativa, poi l’ordine si inverte a ogni manche. Si alternano fino a tre lanci. Dopo il terzo lancio tutti i dadi rimasti entrano in gioco.\n\nAscia ed elmo si contrastano. Freccia e scudo si contrastano. Un attacco senza difesa toglie una pietra. Il bordo dorato genera un gettone. La mano sottrae un gettone al rivale per ultima, anche tra quelli appena guadagnati. Le mani contrapposte si annullano a coppie.\n\nLe tattiche agiscono per priorità. I primi precedono i dadi e richiedono gettoni già in riserva. Gli ultimi possono spendere quelli appena guadagnati. Chi perde l’ultima pietra perde la partita.\n\nClic su un dado per tenerlo. Clic destro per ispezionarlo. Clic sui totem per consultare o attivare una tattica."
var game: Node3D
var screen: Control
var dialog: Control
var context_popup: Control
var prompt: PanelContainer
var prompt_layout: VBoxContainer
var health_count: Array[Label] = []
var token_count: Array[Label] = []
var health_segments: Array = [[],[]]
var stage_tabs: Array[Label] = []
var stage_styles: Array[StyleBoxTexture] = []
var combat_result: Label
var message_panel: PanelContainer
var phase_label: Label
var feedback: Label
var main_title: Font
var body_text: Font
var portrait := false
var inspect_mode := false
var touch_row: HBoxContainer
var touch_buttons: Array[Button] = []
var touch_signature := ""
var paused_for_menu := false
var target_tray: PanelContainer
var target_signature := ""
var touch_tray: PanelContainer
var primary_action: Button
var action_callback := Callable()
var lan_panel := false
var online_panel := false
var invite_text := ""
var pass_panel := false
var stats_panel := false
var updates_panel := false
var updates_signature := ""
var updates_message: Label
var updates_meter: ProgressBar
var updates_refresh_pending := false
var lan_note := ""
var pass_note := ""

func setup(owner_game: Node3D) -> void:
	game = owner_game
	portrait = game.portrait
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	main_title = TITLE_FONT
	body_text = BODY_FONT
	var palette := Theme.new()
	palette.default_font = body_text
	palette.default_font_size = 28 if portrait else 17
	palette.set_color("font_color","Label",IVORY)
	palette.set_font("font","Button",main_title)
	palette.set_font_size("font_size","Button",28 if portrait else 17)
	var button_art := {"normal":SECONDARY,"hover":HOVER,"pressed":SELECTED,"focus":HOVER,"disabled":DISABLED}
	for state in button_art:
		palette.set_stylebox(state,"Button",button_skin(button_art[state]))
		palette.set_color("font_color","Button",IVORY)
		palette.set_color("font_hover_color","Button",Color("#fff3e1"))
		palette.set_color("font_pressed_color","Button",Color("#ffe4b9"))
		palette.set_color("font_disabled_color","Button",Color("#938e87"))
	for state in ["normal","hover","pressed","disabled","focus"]:
		palette.set_stylebox(state,"OptionButton",button_skin(button_art[state]))
	palette.set_color("font_color","OptionButton",IVORY)
	palette.set_color("font_hover_color","OptionButton",IVORY)
	palette.set_stylebox("panel","PopupMenu",chrome(FRAME,27,27,15,12))
	palette.set_stylebox("hover","PopupMenu",skin(Color("#20484a"),GOLD,4))
	palette.set_stylebox("slider","HSlider",chrome(SLIDER,14,8,0,8))
	palette.set_stylebox("grabber_area","HSlider",chrome(SLIDER_FILL,13,8,0,8))
	palette.set_stylebox("grabber_area_highlight","HSlider",chrome(SLIDER_FILL,13,8,0,8))
	for state in ["grabber","grabber_highlight","grabber_disabled"]:
		palette.set_icon(state,"HSlider",GEM)
	theme = palette
	stage_styles = [chrome(TAB,22,11,11,9),chrome(TAB_ACTIVE,22,11,11,9)]
	if portrait:
		resized.connect(apply_safe_area)
		apply_safe_area.call_deferred()

func apply_safe_area() -> void:
	if not OS.has_feature("android"):
		return
	var safe := DisplayServer.get_display_safe_area()
	var pixels := Vector2(DisplayServer.window_get_size())
	if safe.size.x <= 0 or pixels.x <= 0:
		return
	var factor := get_viewport_rect().size / pixels
	offset_left = maxf(0,safe.position.x) * factor.x
	offset_top = maxf(0,safe.position.y) * factor.y
	offset_right = -maxf(0,pixels.x-safe.end.x) * factor.x
	offset_bottom = -maxf(0,pixels.y-safe.end.y) * factor.y

func chrome(texture: Texture2D, sx: int, sy: int, horizontal: int, vertical: int) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = sx
	style.texture_margin_right = sx
	style.texture_margin_top = sy
	style.texture_margin_bottom = sy
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	return style

func button_skin(texture: Texture2D) -> StyleBoxTexture:
	return chrome(texture,39,16,27,13)

func graphic(parent: Node, texture: Texture2D, minimum: Vector2) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = minimum
	art.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(art)
	return art

func skin(fill: Color, edge: Color, margin: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.set_corner_radius_all(3)
	s.content_margin_left = margin
	s.content_margin_right = margin
	s.content_margin_top = margin
	s.content_margin_bottom = margin
	return s

func position_control(node: Control, x: float, y: float, dx: float, dy: float) -> void:
	node.anchor_left = x
	node.anchor_right = x
	node.anchor_top = y
	node.anchor_bottom = y
	node.offset_left = dx
	node.offset_top = dy
	node.offset_right = dx
	node.offset_bottom = dy

func clear_screen() -> void:
	touch_buttons.clear()
	touch_signature = ""
	touch_row = null
	target_tray = null
	target_signature = ""
	close_dialog()
	close_context()
	if is_instance_valid(screen):
		remove_child(screen)
		screen.queue_free()
	screen = Control.new()
	screen.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(screen)
	screen.set_anchors_and_offsets_preset(PRESET_FULL_RECT)

func box(panel: Control, gap := 12) -> VBoxContainer:
	var aligner := VBoxContainer.new()
	aligner.add_theme_constant_override("separation",gap)
	aligner.mouse_filter = MOUSE_FILTER_IGNORE
	panel.add_child(aligner)
	return aligner

func panel(parent: Node, min_size: Vector2, opacity := .95) -> PanelContainer:
	var frame := PanelContainer.new()
	var trim := chrome(FRAME,29,32,22,20)
	trim.modulate_color = Color(1,1,1,opacity)
	frame.add_theme_stylebox_override("panel",trim)
	parent.add_child(frame)
	frame.custom_minimum_size = min_size
	return frame

func label(parent: Node, content: String, size := 17, color := IVORY, serif := false) -> Label:
	var title := Label.new()
	title.text = content
	title.add_theme_font_size_override("font_size",maxi(size,26) if portrait else size)
	title.add_theme_color_override("font_color",color)
	title.add_theme_font_override("font",main_title if serif else body_text)
	title.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(title)
	return title

func divider(parent: Node) -> void:
	graphic(parent,DIVIDER,Vector2(100,16))

func paragraph(parent: Node, content: String, width: float) -> Label:
	var text := label(parent,content,17,MUTED)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size.x = minf(width,self.size.x-144) if portrait else width
	return text

func button(parent: Node, content: String, callback: Callable, width := 0, primary := false) -> Button:
	var item := Button.new()
	item.text = content
	item.focus_mode = FOCUS_NONE
	item.custom_minimum_size.x = width
	if primary:
		item.add_theme_stylebox_override("normal",button_skin(PRIMARY))
	item.custom_minimum_size.y = 88 if portrait else 45
	item.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	item.pressed.connect(callback)
	parent.add_child(item)
	return item

func fade(node: Control) -> void:
	node.modulate.a = 0.0
	node.create_tween().tween_property(node,"modulate:a",1.0,.25)

func show_menu() -> void:
	clear_screen()
	if portrait:
		show_portrait_menu()
		return
	var card := panel(screen,Vector2(380,0),.96)
	position_control(card,.03,.03,0,0)
	var column := box(card,8)
	var plaque := graphic(column,BANNER,Vector2(336,200))
	var title := label(column,"SESTRIA",70,IVORY,true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_outline_color",Color("#66472d"))
	title.add_theme_constant_override("outline_size",3)
	var subtitle := label(column,"SEI DADI. MILLE STRATEGIE.",14,GOLD,true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider(column)
	button(column,"INIZIA LA SAGA",show_play_modes,336,true)
	button(column,"TATTICHE",show_equipped,336)
	button(column,"SFIDA · " + TITLES[game.difficulty].to_upper(),show_difficulty,336)
	var extras := HBoxContainer.new()
	extras.add_theme_constant_override("separation",8)
	column.add_child(extras)
	for entry in [["STATISTICHE",show_statistics],["PASS · %d" % game.progression.points(),show_pass]]:
		var small := button(extras,entry[0],entry[1])
		small.size_flags_horizontal = SIZE_EXPAND_FILL
		small.add_theme_font_size_override("font_size",14)
		small.add_theme_stylebox_override("normal",chrome(SECONDARY,19,13,8,10))
		small.add_theme_stylebox_override("hover",chrome(HOVER,19,13,8,10))
		small.add_theme_stylebox_override("pressed",chrome(SELECTED,19,13,8,10))
	button(column,"REGOLE",show_rules,336)
	button(column,"IMPOSTAZIONI",show_settings,336)
	if Platform.can_quit():
		button(column,"ESCI",func():get_tree().quit(),336)
	var progress_card := PanelContainer.new()
	progress_card.add_theme_stylebox_override("panel",skin(Color("#10252b"),GOLD,10))
	column.add_child(progress_card)
	var progress_content := box(progress_card,5)
	var progress_row := HBoxContainer.new()
	progress_content.add_child(progress_row)
	var current_level := label(progress_row,"LIVELLO %d" % game.progression.level(),14,GOLD,true)
	current_level.size_flags_horizontal = SIZE_EXPAND_FILL
	label(progress_row,"%d / %d XP" % [game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],14,IVORY)
	xp_bar(progress_content)
	fade(card)

func modal(title: String, width: float) -> VBoxContainer:
	close_dialog(true)
	close_context()
	dialog = Control.new()
	add_child(dialog)
	dialog.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.02,0.04,0.05,.58)
	dialog.add_child(shade)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var center := CenterContainer.new()
	dialog.add_child(center)
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	if portrait:
		width = minf(width,size.x-48)
	var card := panel(center,Vector2(width,0))
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_right",14)
	inset.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(inset)
	var body := box(inset,16 if portrait else 13)
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	fit_scroll.call_deferred(card,scroll,body,width)
	var heading := label(body,title,33,IVORY,true)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider(body)
	fade(card)
	return body

func fit_scroll(card: PanelContainer, scroll: ScrollContainer, body: VBoxContainer, width: float, max_height := 0.0) -> void:
	if not is_instance_valid(card):
		return
	var room := max_height if max_height > 0 else size.y-(144 if portrait else 96)
	scroll.custom_minimum_size = Vector2(width-(44 if portrait else 44),minf(body.get_combined_minimum_size().y,room))

func close_dialog(keep_pause := false) -> void:
	if (lan_panel or online_panel) and not keep_pause and game.lan and not game.lan.started:
		game.lan.close()
	lan_panel = false
	online_panel = false
	pass_panel = false
	stats_panel = false
	updates_panel = false
	if paused_for_menu and not keep_pause:
		get_tree().paused = false
		paused_for_menu = false
	if is_instance_valid(dialog):
		remove_child(dialog)
		dialog.queue_free()
		dialog = null

func close_context() -> void:
	if is_instance_valid(context_popup):
		screen.remove_child(context_popup)
		context_popup.queue_free()
		context_popup = null

func show_rules() -> void:
	var body := modal("Regole",570)
	var text := RULES_TEXT
	if portrait:
		text = text.replace("Clic su un dado per tenerlo. Clic destro per ispezionarlo. Clic sui totem per consultare o attivare una tattica.","Tocca un dado sul tavolo o nella barra per tenerlo. Attiva Ispeziona e tocca un dado per vedere le facce. Tocca i totem per consultare o attivare una tattica.")
	paragraph(body,text,530)
	button(body,"Chiudi",close_dialog)

func show_difficulty() -> void:
	var body := modal("Scegli la sfida",520)
	paragraph(body,"La sfida scelta è la base della saga. Ai livelli 4, 8 e 12 il rivale diventa più forte; il Pass ti aiuta a prepararti.",480)
	for i in TITLES.size():
		var item := button(body,["ESPLORATORE · Impara il rituale","GUERRIERO · Una sfida equilibrata","MAESTRO · Nessuna concessione"][i],choose_difficulty.bind(i))
		if i == game.difficulty:
			item.add_theme_stylebox_override("normal",button_skin(SELECTED))
	button(body,"Indietro",close_dialog)

func choose_difficulty(value: int) -> void:
	game.difficulty = value
	game.save_settings()
	show_menu()

func show_settings(active = 0) -> void:
	if Platform.pc_available() and not portrait and not game.pc.is_empty():
		# Windows e Mac: impostazioni complete in scripts/pc_settings.gd (0 schermo, 1 grafica, 2 comandi, 3 sistema).
		preload("res://scripts/pc_settings.gd").open(self,game,["schermo","grafica","comandi","sistema"][clampi(active,0,3)] if active is int else str(active))
		return
	var body := modal("Impostazioni",570)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation",5)
	body.add_child(tabs)
	for i in 4:
		var tab := button(tabs,["AUDIO","GRAFICA","COMANDI","INFO"][i],show_settings.bind(i),0,i==active)
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
	match active:
		0:
			slider(body,"Musica",game.music_volume,game.change_music)
			slider(body,"Effetti sonori",game.effects_volume,change_effects)
		1:
			for i in 2:
				var item := button(body,["Alta · Risoluzione nativa","Ridotta · Modalità prestazioni"][i],select_graphics.bind(i==1))
				if (i==1) == game.reduced:
					item.add_theme_stylebox_override("normal",button_skin(SELECTED))
			if Platform.fullscreen_available():
				button(body,"Esci dallo schermo intero" if Platform.is_fullscreen() else "Schermo intero",func():
					Platform.toggle_fullscreen()
					show_settings(1))
		2:
			if portrait:
				paragraph(body,"Tocca un dado sul tavolo o nella barra in basso per tenerlo. I dadi turchesi sono selezionati.\n\nAttiva Ispeziona e tocca un dado per vedere le sei facce.\n\nTocca un totem o i pulsanti dele tattiche per invocarlo. Menu e il tasto Indietro di Android aprono la pausa.",500)
			else:
				paragraph(body,"Clic sinistro · Seleziona un dado o un totem
Clic destro · Ispeziona le sei facce
Spazio / Invio · Lancia, conferma o avanza
Esc · Chiudi il pannello o lascia il tavolo",500)
		3:
			if game.updater:
				label(body,"SESTRIA · VERSIONE "+game.updater.current_version,17,GOLD,true)
				paragraph(body,"Gli aggiornamenti provengono dalle release pubbliche di GitHub e si applicano dall’app: firma e SHA-256 vengono verificate prima del riavvio.",500)
				button(body,"AGGIORNAMENTI",show_updates,0,true)
				button(body,"Apri le release su GitHub",func():OS.shell_open(game.updater.RELEASES))
			else:
				label(body,"SESTRIA · VERSIONE "+str(ProjectSettings.get_setting("application/config/version","")),17,GOLD,true)
				paragraph(body,"Edizione web: si aggiorna da sola. I progressi restano in questo browser.",500)
	if game.phase == "menu":
		button(body,"Passa alla nuova interfaccia",use_new_interface)
	button(body,"Indietro",close_dialog)

func change_effects(value: float) -> void:
	game.effects_volume = value
	game.save_settings()

func select_graphics(reduced: bool) -> void:
	game.change_quality(reduced)
	show_settings(1)

func slider(parent: Node, title: String, value: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",13)
	parent.add_child(row)
	var caption := label(row,title,17,IVORY,true)
	caption.custom_minimum_size.x = 130
	var control := HSlider.new()
	control.max_value = 1.0
	control.step = .01
	control.value = value
	control.custom_minimum_size.y = 88.0 if portrait else 26.0
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(control)
	var current := label(row,"%d%%" % roundi(value*100),16,GOLD,true)
	current.custom_minimum_size.x = 45
	control.value_changed.connect(func(next):
		current.text = "%d%%" % roundi(next*100)
		callback.call(next))

func show_equipped() -> void:
	var body := modal("Tattiche",920)
	var slots := VBoxContainer.new()
	body.add_child(slots)
	var select := OptionButton.new()
	select.custom_minimum_size.y = 88 if portrait else 45
	for i in 3:
		select.add_item("Posto %d · %s" % [i+1,Rules.FAVOR[game.equipped[i]][0]])
	slots.add_child(select)
	var detail := label(slots,"",15,MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 540 if portrait else 0
	detail.size_flags_horizontal = SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 2 if portrait else 5
	grid.add_theme_constant_override("h_separation",7)
	grid.add_theme_constant_override("v_separation",7)
	body.add_child(grid)
	var ids := Rules.FAVOR.keys()
	for index in ids.size():
		var id: String = ids[index]
		var entry := button(grid,Rules.FAVOR[id][0],func():
			var old: int = game.equipped.find(id)
			if old >= 0:
				game.equipped[old] = game.equipped[select.selected]
			game.equipped[select.selected] = id
			game.save_settings()
			var data: Array = Rules.FAVOR[id]
			detail.text = "%s\n%s · %s / %s / %s gettoni" % [data[0],data[4] % data[3][0],data[2][0],data[2][1],data[2][2]]
			for i in 3:
				select.set_item_text(i,"Posto %d · %s" % [i+1,Rules.FAVOR[game.equipped[i]][0]])
		,260 if portrait else 165)
		entry.icon = load("res://assets/icons/favor_%02d.svg"%index)
		entry.add_theme_constant_override("icon_max_width",22)
		entry.add_theme_font_size_override("font_size",24 if portrait else 13)
		if portrait:
			entry.clip_text = true
			entry.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		entry.mouse_entered.connect(func():
			var data: Array = Rules.FAVOR[id]
			detail.text = "%s · %s / %s / %s gettoni" % [data[4] % data[3][0],data[2][0],data[2][1],data[2][2]])
	button(body,"Indietro",close_dialog)

func hud_outline(text: Label) -> void:
	text.add_theme_color_override("font_outline_color",Color("#0b1516"))
	text.add_theme_constant_override("outline_size",5)

func match_layout() -> void:
	clear_screen()
	health_count = []
	token_count = []
	health_segments = [[],[]]
	stage_tabs = []
	for side in [1,0]:
		var width := (size.x-60)/2 if portrait else 237.0
		var crest := panel(screen,Vector2(width,0),.95)
		crest.mouse_filter = MOUSE_FILTER_IGNORE
		crest.add_theme_stylebox_override("panel",chrome(FRAME,27,25,24,10))
		position_control(crest,0 if side == 1 else 1,.0 if portrait else .023,24 if side == 1 else -width-24,20 if portrait else 0)
		if not portrait:
			position_control(crest,.025 if side == 1 else .975,.023,0 if side == 1 else -width,0)
		var card := box(crest,4)
		var nameplate := label(card,"AVVERSARIO" if side == 1 else "TU",14,GOLD)
		hud_outline(nameplate)
		nameplate.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if side == 1 else HORIZONTAL_ALIGNMENT_RIGHT
		var values := HBoxContainer.new()
		values.add_theme_constant_override("separation",6)
		values.alignment = BoxContainer.ALIGNMENT_BEGIN if side == 1 else BoxContainer.ALIGNMENT_END
		card.add_child(values)
		graphic(values,HEART,Vector2(22,22))
		health_count.push_front(label(values,"15",25,IVORY,true))
		label(values,"/ 15",13,MUTED)
		graphic(values,TOKEN,Vector2(22,22))
		token_count.push_front(label(values,"0",25,GOLD,true))
		var strip := HBoxContainer.new()
		strip.alignment = BoxContainer.ALIGNMENT_BEGIN if side == 1 else BoxContainer.ALIGNMENT_END
		strip.add_theme_constant_override("separation",4)
		card.add_child(strip)
		for i in 15:
			var cell := ColorRect.new()
			cell.custom_minimum_size = Vector2(8,3)
			cell.mouse_filter = MOUSE_FILTER_IGNORE
			strip.add_child(cell)
			health_segments[side].append(cell)
	var phases := box(screen,7)
	phases.custom_minimum_size.x = size.x-48 if portrait else 480
	position_control(phases,.5,0 if portrait else .022,-(size.x-48)/2 if portrait else -240,158 if portrait else 0)
	phase_label = label(phases,"",22,IVORY,true)
	hud_outline(phase_label)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var track := HBoxContainer.new()
	track.add_theme_constant_override("separation",5)
	phases.add_child(track)
	for name in ["LANCIO","ORDINA","TATTICHE","RISOLVI"]:
		var tab := label(track,name,13,MUTED,true)
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stage_tabs.append(tab)
	set_stage(0)
	var footer := label(screen,"Clic destro  ·  Ispeziona     1-6  ·  Dadi     Q W E  ·  Tattiche     Esc  ·  Menu" if Platform.pc_available() else "Clic destro  ·  Ispeziona     Esc  ·  Menu",13,IVORY)
	footer.visible = not portrait
	hud_outline(footer)
	position_control(footer,.035,.953,0,0)
	prompt = panel(screen,Vector2(225,0),.94)
	prompt.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	position_control(prompt,.965,.777,-225,0)
	prompt_layout = box(prompt,6)
	prompt.mouse_filter = MOUSE_FILTER_IGNORE
	message_panel = panel(screen,Vector2(231,0),.91)
	position_control(message_panel,.035,.170,0,0)
	message_panel.mouse_filter = MOUSE_FILTER_IGNORE
	var messages := box(message_panel,4)
	feedback = label(messages,"",23,IVORY,true)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.custom_minimum_size.x = 203
	combat_result = label(messages,"",14,GOLD)
	combat_result.hide()
	prompt.hide()
	message_panel.hide()
	if portrait:
		setup_touch_controls()
		layout_portrait_prompt()

func layout_portrait_prompt() -> void:
	if not portrait:
		return
	prompt.custom_minimum_size.x = size.x-48
	position_control(prompt,0,1,24,-204)
	message_panel.custom_minimum_size.x = size.x-48
	feedback.custom_minimum_size.x = size.x-92
	feedback.add_theme_font_size_override("font_size",28)
	position_control(message_panel,0,0,24,332)

func set_stage(active: int) -> void:
	for index in stage_tabs.size():
		stage_tabs[index].add_theme_color_override("font_color",TURQUOISE if index == active else MUTED)
		stage_tabs[index].add_theme_stylebox_override("normal",stage_styles[int(index==active)])

func stats(hp: Array, gold: Array, round_no: int, first: int) -> void:
	for side in 2:
		health_count[side].text = str(hp[side])
		health_count[side].add_theme_color_override("font_color",Color("#f0a878") if hp[side] <= 4 else IVORY)
		token_count[side].text = str(gold[side])
		for i in 15:
			health_segments[side][i].color = (Color("#eb9a65") if hp[side] <= 4 else Color("#69c1a9")) if i < hp[side] else Color("#3d4840")
	phase_label.text = "Manche %02d   ·   Iniziativa %s" % [round_no,"tua" if first == 0 else "avversaria"]

func reset_prompt() -> void:
	close_context()
	action_callback = Callable()
	primary_action = null
	for kid in prompt_layout.get_children():
		prompt_layout.remove_child(kid)
		kid.queue_free()
	prompt.hide()
	prompt.reset_size()
	feedback.text = ""
	combat_result.hide()
	position_control(message_panel,.035,.170,0,0)
	message_panel.reset_size()
	position_control(prompt,.965,.777,-225,0)
	layout_portrait_prompt()

func action(message: String, action_name: String, callback: Callable) -> void:
	reset_prompt()
	feedback.text = message
	message_panel.show()
	prompt.show()
	action_callback = callback
	primary_action = button(prompt_layout,action_name,invoke_action,0,true)
	fade(prompt)

func invoke_action() -> void:
	if action_callback.is_valid() and is_instance_valid(primary_action) and not primary_action.disabled:
		action_callback.call()

func status(message: String) -> void:
	reset_prompt()
	close_dialog()
	feedback.text = message
	message_panel.show()

func coin_prompt() -> void:
	var body := modal("Testa o croce?",420)
	paragraph(body,"La moneta decide chi lancia per primo.",380)
	button(body,"Testa",game.toss.bind(0),0,true)
	button(body,"Croce",game.toss.bind(1))

func favor_stage() -> void:
	action("Scegli un totem o passa", "Passa",game.resolve.bind({}))
	var row := HBoxContainer.new()
	prompt_layout.add_child(row)
	prompt_layout.move_child(row,0)
	for id in game.equipped:
		var short: String = Rules.FAVOR[id][0].split("’")[0]
		var entry := button(row,short,game.inspect_favor.bind(0,id),0)
		entry.add_theme_stylebox_override("normal",chrome(SECONDARY,19,13,7,10))
		entry.add_theme_stylebox_override("hover",chrome(HOVER,19,13,7,10))
		entry.add_theme_stylebox_override("pressed",chrome(SELECTED,19,13,7,10))
		entry.add_theme_font_size_override("font_size",26 if portrait else 13)
		entry.size_flags_horizontal = SIZE_EXPAND_FILL
	position_control(prompt,.965,.715,-225,0)
	layout_portrait_prompt()

func context_frame(width: float, y: float) -> VBoxContainer:
	close_context()
	if portrait:
		width = size.x-48
	context_popup = panel(screen,Vector2(width,0),.97)
	position_control(context_popup,.977,y,-width,0)
	var contents: VBoxContainer
	if portrait:
		position_control(context_popup,0,0,24,240)
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		context_popup.add_child(scroll)
		contents = box(scroll,12)
		contents.size_flags_horizontal = SIZE_EXPAND_FILL
		fit_scroll.call_deferred(context_popup,scroll,contents,width,size.y-328)
	else:
		contents = box(context_popup,8)
	fade(context_popup)
	return contents

func inspect_die(id: int, face: int) -> void:
	var contents := context_frame(224,.33)
	var data := Rules.die(id,face)
	label(contents,Rules.NAMES[data.kind],25,IVORY,true)
	paragraph(contents,["Danno corpo a corpo","Danno a distanza","Blocca un’ascia","Blocca una freccia","Sottrae un gettone"][data.kind],182)
	if data.gold:
		label(contents,"+1 gettone",14,GOLD)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation",4)
	grid.add_theme_constant_override("v_separation",4)
	contents.add_child(grid)
	for cell in [-1,2,-1,5,0,4,-1,3,-1,-1,1,-1]:
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(88,88) if portrait else Vector2(54,54)
		grid.add_child(tile)
		if cell >= 0:
			var info := Rules.die(id,cell)
			tile.add_theme_stylebox_override("panel",skin(Color("#d7b880"),GOLD if cell==face else Color("#6e583a"),0))
			var icon := TextureRect.new()
			icon.texture = load("res://assets/icons/face_%d%s.svg"%[info.kind,"_gold" if info.gold else ""])
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = MOUSE_FILTER_IGNORE
			tile.add_child(icon)
		else:
			tile.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	button(contents,"Chiudi",close_context)

func favor_popup(id: String, actionable: bool) -> void:
	var contents := context_frame(350,.26)
	var data: Array = Rules.FAVOR[id]
	label(contents,data[0],24,IVORY,true)
	label(contents,"Priorità %d" % data[1],15,GOLD)
	divider(contents)
	var sacrifice: SpinBox
	if actionable and id in ["reserve","exchange"]:
		label(contents,"Pietre da sacrificare",15,MUTED)
		sacrifice = SpinBox.new()
		sacrifice.custom_minimum_size.y = 88 if portrait else 45
		sacrifice.min_value = 1.0 if game.rules.hp[0] > 1 else 0.0
		sacrifice.max_value = maxi(0,game.rules.hp[0]-1)
		sacrifice.value = sacrifice.min_value
		if portrait:
			var stepper := HBoxContainer.new()
			stepper.add_theme_constant_override("separation",12)
			contents.add_child(stepper)
			button(stepper,"−",func():sacrifice.value -= 1,88)
			stepper.add_child(sacrifice)
			sacrifice.size_flags_horizontal = SIZE_EXPAND_FILL
			button(stepper,"+",func():sacrifice.value += 1,88)
		else:
			contents.add_child(sacrifice)
	for level in 3:
		var description: String = data[4] % data[3][level]
		var text := "%d gettoni · Livello %d" % [data[2][level],level+1]
		if actionable:
			button(contents,text,func():
				var units := int(sacrifice.value) if is_instance_valid(sacrifice) else 0
				close_context()
				game.pick_favor(id,level,units))
		else:
			label(contents,text,15,GOLD)
		paragraph(contents,description,302)
	button(contents,"Chiudi",close_context)

func selection_count(value: int, limit: int) -> void:
	feedback.text = "Seconda occasione · %d / %d dadi selezionati" % [value,limit]

func describe_event(event: Dictionary) -> void:
	combat_result.hide()
	var amount: int = event.amount
	feedback.text = "%s%s" % [event.text, "  ·  %d" % amount if amount > 0 else ""]
	message_panel.reset_size()
	position_control(message_panel,.035,.170,0,0)
	layout_portrait_prompt()

func combat_detail(title: String, amount: int, damage: bool) -> void:
	feedback.text = title
	combat_result.text = "%d %s" % [amount,
		("pietra persa" if amount == 1 else "pietre perse") if damage else ("attacco parato" if amount == 1 else "attacchi parati")]
	combat_result.add_theme_color_override("font_color",Color("#ffae7c") if damage else Color("#a3e4e9"))
	combat_result.show()
	position_control(message_panel,.035,.170,0,0)
	message_panel.reset_size()
	layout_portrait_prompt()

func finish(victory: bool) -> void:
	var body := modal("Vittoria" if victory else "La saga continua",520)
	paragraph(body,"Pietre rimaste   ·   Tu %d   /   Avversario %d" % game.rules.hp,480)
	if game.lan and game.lan.active:
		if game.lan.role == "host":
			button(body,"UNA NUOVA SFIDA LAN",game.rematch_lan,0,true)
		else:
			paragraph(body,"Il creatore della stanza può iniziare una nuova sfida.",480)
	else:
		var reward: Dictionary = game.progression.last_reward
		if reward.has("error"):
			paragraph(body,str(reward.error),480)
		elif victory and reward.has("xp"):
			label(body,"+%d XP  ·  SAGA OFFLINE" % reward.xp,22,MINT,true)
			if int(reward.levels) > 0:
				label(body,"LIVELLO %d → %d  ·  +%d PUNTI PASS" % [reward.from_level,reward.to_level,reward.points],17,GOLD,true)
			paragraph(body,"Livello %d · %d / %d XP" % [game.progression.level(),game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],480)
			xp_bar(body)
		elif not victory:
			paragraph(body,"Gli XP si guadagnano con le vittorie. I tuoi progressi e punti restano al sicuro.",480)
		button(body,"PASS · %d PUNTI DISPONIBILI" % game.progression.points(),show_pass)
		button(body,"UNA NUOVA SAGA",func():close_dialog();game.prepare(),0,true)
	button(body,"Menu principale",game.menu)

func ask_leave() -> void:
	paused_for_menu = true
	get_tree().paused = true
	var body := modal("Lasciare il tavolo?",420)
	button(body,"Continua a giocare",close_dialog,0,true)
	button(body,"Impostazioni",show_settings)
	button(body,"Torna al menu",game.menu)

func show_portrait_menu() -> void:
	var banner := graphic(screen,BANNER,Vector2(640,1200))
	position_control(banner,.5,0,-320,20)
	var column := box(screen,18)
	column.custom_minimum_size.x = 540
	position_control(column,.5,.13,-270,0)
	var title := label(column,"SESTRIA",94,IVORY,true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := label(column,"SEI DADI. MILLE STRATEGIE.",26,GOLD,true)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	divider(column)
	button(column,"NUOVA PARTITA",game.prepare,540,true)
	button(column,"TATTICHE",show_equipped,540)
	button(column,"DIFFICOLTÀ · " + TITLES[game.difficulty].to_upper(),show_difficulty,540)
	button(column,"REGOLE",show_rules,540)
	button(column,"IMPOSTAZIONI",show_settings,540)
	var hint := label(column,"Sei dadi. Tre tattiche. Il tuo destino.",23,MUTED)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fade(column)

func setup_touch_controls() -> void:
	inspect_mode = false
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation",12)
	screen.add_child(tools)
	position_control(tools,0,0,24,232)
	tools.custom_minimum_size.x = size.x-48
	button(tools,"Menu",game.go_back,180)
	var inspect := button(tools,"Ispeziona",func():pass)
	inspect.size_flags_horizontal = SIZE_EXPAND_FILL
	inspect.toggle_mode = true
	inspect.toggled.connect(func(enabled):
		inspect_mode = enabled
		inspect.text = "Ispeziona · ON" if enabled else "Ispeziona"
		touch_signature = "")
	var tray := panel(screen,Vector2(size.x-48,0))
	touch_tray = tray
	position_control(tray,0,1,24,-368)
	var contents := box(tray,8)
	label(contents,"I TUOI DADI  ·  Tocca per tenere",22,GOLD)
	touch_row = HBoxContainer.new()
	touch_row.add_theme_constant_override("separation",8)
	contents.add_child(touch_row)
	for id in 6:
		var entry := button(touch_row,"",touch_die.bind(id))
		entry.custom_minimum_size = Vector2(88,88)
		entry.size_flags_horizontal = SIZE_EXPAND_FILL
		entry.add_theme_constant_override("icon_max_width",48)
		entry.add_theme_stylebox_override("normal",chrome(SECONDARY,19,13,8,10))
		entry.expand_icon = true
		for state in ["normal","hover","pressed","disabled","focus"]:
			entry.add_theme_stylebox_override(state,touch_die_skin(false))
		touch_buttons.append(entry)
	target_tray = panel(screen,Vector2(size.x-48,0))
	position_control(target_tray,0,1,24,-620)
	target_tray.hide()
	update_touch_dice()

func touch_die_skin(selected: bool) -> StyleBoxFlat:
	var style := skin(Color("#a3e4da") if selected else Color("#ead7b2"),TURQUOISE if selected else GOLD,12)
	style.set_border_width_all(4 if selected else 2)
	style.set_corner_radius_all(10)
	return style

func touch_die(id: int) -> void:
	var cube: Node3D = game.cubes[0][id]
	if inspect_mode or game.phase not in ["select","target"] or (cube.committed and game.phase != "target"):
		inspect_die(id,cube.face)
	else:
		game.interact_die_or_favor(cube,false)
	touch_signature = ""

func update_touch_dice() -> void:
	if touch_buttons.is_empty():
		return
	update_target_tray()
	var signature: String = game.phase + str(inspect_mode)
	for cube in game.cubes[0].slice(0,6):
		signature += "%d:%s:%s;" % [cube.face,cube.selected,cube.committed]
	if signature == touch_signature:
		return
	touch_signature = signature
	for id in 6:
		var cube: Node3D = game.cubes[0][id]
		var data := Rules.die(id,cube.face)
		var entry := touch_buttons[id]
		entry.icon = load("res://assets/icons/face_%d%s.svg" % [data.kind,"_gold" if data.gold else ""])
		entry.disabled = game.phase not in ["select","roll","favor","target","between"]
		entry.modulate = Color(1,1,1,.58) if cube.committed else Color.WHITE
		entry.add_theme_stylebox_override("normal",touch_die_skin(cube.selected))

func update_target_tray() -> void:
	if not is_instance_valid(target_tray):
		return
	target_tray.visible = game.phase == "target"
	touch_tray.visible = not target_tray.visible
	if not target_tray.visible:
		target_signature = ""
		return
	var signature := str(game.targets)
	if signature == target_signature:
		return
	target_signature = signature
	for child in target_tray.get_children():
		target_tray.remove_child(child)
		child.queue_free()
	var contents := box(target_tray,8)
	label(contents,"SECONDA OCCASIONE · TOCCA I BERSAGLI",26,GOLD)
	for side in [1,0]:
		label(contents,"Avversario" if side == 1 else "Tu",26,MUTED)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		contents.add_child(row)
		for cube in game.cubes[side]:
			if not cube.committed or not cube.visible:
				continue
			var data := Rules.die(cube.die_id,cube.face)
			var entry := button(row,"",game.interact_die_or_favor.bind(cube,false))
			entry.custom_minimum_size = Vector2(88,88)
			entry.size_flags_horizontal = SIZE_EXPAND_FILL
			entry.icon = load("res://assets/icons/face_%d%s.svg" % [data.kind,"_gold" if data.gold else ""])
			entry.add_theme_constant_override("icon_max_width",48)
			entry.expand_icon = true
			for state in ["normal","hover","pressed","focus"]:
				entry.add_theme_stylebox_override(state,touch_die_skin(cube.selected))

func _unhandled_key_input(event: InputEvent) -> void:
	if paused_for_menu and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		game.go_back()
		get_viewport().set_input_as_handled()

func xp_bar(parent: Node) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.max_value = game.progression.xp_required(game.progression.level())
	bar.value = game.progression.xp_in_level()
	bar.show_percentage = false
	bar.custom_minimum_size.y = 8
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	for key in ["background","fill"]:
		bar.add_theme_stylebox_override(key,skin(MINT if key == "fill" else Color("#29413f"),Color.TRANSPARENT,0))
	parent.add_child(bar)
	return bar

func show_play_modes() -> void:
	var body := modal("Scegli il tuo rivale",600)
	var run: Dictionary = game.progression.create_run(game.difficulty)
	label(body,"SAGA OFFLINE · LIVELLO %d" % run.level,17,GOLD,true)
	paragraph(body,"%s · Rivale %s · %d gettoni iniziali. Vittoria: %d XP." % [game.progression.TITLES[run.tier],TITLES[run.ai_level],run.enemy_gold,game.progression.victory_xp(run)],560)
	button(body,"CONTINUA LA SAGA",game.prepare,0,true)
	paragraph(body,"Vinci, sali di livello e ottieni 2 punti Pass a ogni avanzamento. I potenziamenti si attivano dalla prossima saga.",560)
	if Platform.online_available():
		button(body,"PARTITA ONLINE · ELENCO E INVITO",show_online)
		paragraph(body,"Gioca contro persone di altre reti: scegli una stanza pubblica dall’elenco o entra con un codice invito. Nessun server di gioco e nessun account.",560)
	if Platform.lan_available():
		button(body,"SFIDA LAN · STESSA RETE",show_lan)
		paragraph(body,"La LAN collega due computer o dispositivi sulla stessa rete. Regole standard, senza buff o ricompense XP. Nessun account obbligatorio, nessun server di gioco.",560)
	button(body,"Indietro",close_dialog)

func show_pass(scroll_y := 0) -> void:
	if game.phase not in ["menu","end"] or (game.lan and game.lan.active):
		return
	var progress: RefCounted = game.progression
	var body := modal("Il Pass della saga",760)
	pass_panel = true
	var overview := HBoxContainer.new()
	body.add_child(overview)
	var level_title := label(overview,"LIVELLO %d" % progress.level(),22,GOLD,true)
	level_title.size_flags_horizontal = SIZE_EXPAND_FILL
	label(overview,"%d PUNTI" % progress.points(),22,MINT,true)
	paragraph(body,"%d / %d XP al prossimo livello · +2 punti" % [progress.xp_in_level(),progress.xp_required(progress.level())],700)
	xp_bar(body)
	paragraph(body,"Solo saga offline. Ogni grado acquistato resta attivo nelle saghe successive. Puoi riassegnare tutti i punti gratis.",700)
	if not pass_note.is_empty():
		var note := paragraph(body,pass_note,700)
		note.add_theme_color_override("font_color",MINT)
		pass_note = ""
	for id: String in progress.ORDER:
		var upgrade: Dictionary = progress.UPGRADES[id]
		var rank_index: int = progress.rank_of(id)
		var card := panel(body,Vector2(700,0),.9)
		card.add_theme_stylebox_override("panel",chrome(FRAME,27,25,18,12))
		var content := box(card,7)
		label(content,"%s  /  %s" % [upgrade.rune,upgrade.name],20,GOLD,true)
		var rank_label := label(content,"GRADO %d / %d" % [rank_index,upgrade.costs.size()],14,MINT if rank_index > 0 else MUTED)
		rank_label.mouse_filter = MOUSE_FILTER_IGNORE
		paragraph(content,upgrade.description,650).add_theme_color_override("font_color",IVORY)
		var status: String = progress.purchase_status(id)
		if rank_index < upgrade.costs.size():
			paragraph(content,"Prossimo grado · %d punti · Livello %d" % [upgrade.costs[rank_index],upgrade.levels[rank_index]],650)
			var buy := button(content,"ACQUISTA · %d PUNTI" % upgrade.costs[rank_index] if status.is_empty() else status,buy_upgrade.bind(id),0,status.is_empty())
			buy.disabled = not status.is_empty()
		else:
			label(content,"TUTTI I GRADI ACQUISITI",14,MINT)
	label(body,"LA SAGA DIVENTA PIÙ DIFFICILE",17,GOLD,true)
	paragraph(body,"Livello 4: rivale almeno Guerriero, +1 gettone iniziale. Livello 8: almeno Maestro, +2 gettoni. Livello 12: Maestro con più analisi tattica, +3 gettoni. Dadi e tiri restano equi.",700)
	paragraph(body,"XP per vittoria: 100 / 130 / 160 secondo la sfida scelta, +10 per ogni soglia della saga raggiunta, più Esperienza sul campo. Le sconfitte e le partite interrotte non assegnano XP.",700)
	if progress.spent_points() > 0:
		button(body,"RIASSEGNA · %d PUNTI" % progress.spent_points(),confirm_refund)
	button(body,"Torna al risultato" if game.phase == "end" else "Torna al menu",close_pass,0,true)
	restore_pass_scroll.call_deferred(dialog,scroll_y)

func restore_pass_scroll(root: Control, position_y: int) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(root):
		root.find_child("Scroll",true,false).scroll_vertical = position_y

func buy_upgrade(id: String) -> void:
	if game.phase not in ["menu","end"] or not is_instance_valid(dialog):
		return
	var scroll_y := int(dialog.find_child("Scroll",true,false).scroll_vertical)
	var error: Error = game.progression.purchase(id)
	pass_note = "%s · grado %d acquisito. Attivo dalla prossima saga." % [game.progression.UPGRADES[id].name,game.progression.rank_of(id)] if error == OK else "Acquisto non salvato. Nessun punto è stato speso."
	show_pass(scroll_y)

func confirm_refund() -> void:
	var body := modal("Riscrivi il tuo destino",520)
	pass_panel = true
	paragraph(body,"Restituisci i %d punti spesi e azzeri i gradi del Pass. Livello e XP restano invariati. La riassegnazione è gratuita." % game.progression.spent_points(),480)
	button(body,"RESTITUISCI I PUNTI",func():
		var error: Error = game.progression.refund()
		pass_note = "Punti restituiti. Scegli il tuo nuovo percorso." if error == OK else "Riassegnazione non salvata. I potenziamenti restano attivi."
		show_pass(),0,true)
	button(body,"Mantieni i potenziamenti",show_pass)

func close_pass() -> void:
	if game.phase == "end":
		finish(game.rules.winner == 0)
	else:
		show_menu()

func show_statistics() -> void:
	var data: Dictionary = game.stats_store.data
	var body := modal("Le tue imprese",760)
	stats_panel = true
	label(body,"STATISTICHE SU QUESTO COMPUTER",15,GOLD,true)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	body.add_child(grid)
	for pair in [["Partite",str(int(data.played))],["Vittorie",str(int(data.wins))],["Percentuale vittorie","%d%%" % game.stats_store.win_rate()],["Serie migliore",str(int(data.best_streak))],["Lanci",str(int(data.rolls))],["Danni inflitti",str(int(data.damage_dealt))],["Danni subiti",str(int(data.damage_taken))],["Attacchi parati",str(int(data.blocked))],["Gettoni rubati",str(int(data.tokens_stolen))],["Tempo di gioco","%d min" % (int(data.seconds)/60)]]:
		var card := PanelContainer.new()
		card.custom_minimum_size.x = 128
		card.add_theme_stylebox_override("panel",skin(Color("#10252b"),GOLD,10))
		grid.add_child(card)
		var item := box(card,2)
		var caption := label(item,pair[0],12,MUTED)
		caption.clip_text = true
		caption.custom_minimum_size.x = 100
		label(item,pair[1],24,GOLD,true)
	paragraph(body,"Manche concluse: %d · Partite interrotte: %d" % [data.rounds,data.abandoned],700)
	for mode in ["solo","lan"]:
		var info: Dictionary = data.modes.get(mode,{"played":0,"wins":0})
		paragraph(body,"%s · %d partite / %d vittorie" % ["Computer" if mode == "solo" else "LAN",info.played,info.wins],700).add_theme_color_override("font_color",IVORY)
	if not data.favors.is_empty():
		label(body,"TATTICHE INVOCATE",15,GOLD,true)
		for id in data.favors:
			paragraph(body,"%s · %d" % [Rules.FAVOR[id][0] if Rules.FAVOR.has(id) else id,data.favors[id]],700)
	label(body,"ULTIME PARTITE",15,GOLD,true)
	if data.history.is_empty():
		paragraph(body,"La tua prima impresa deve ancora essere scritta.",700)
	for match_info in data.history.slice(0,12):
		paragraph(body,"%s · %s · %d manche / %d:%02d" % ["Vittoria" if match_info.victory else "Sconfitta","LAN" if match_info.mode == "lan" else "Computer",match_info.rounds,int(match_info.seconds)/60,int(match_info.seconds)%60],700).add_theme_color_override("font_color",IVORY)
	button(body,"Torna al menu",close_dialog,0,true)

func show_lan() -> void:
	var body := modal("Sfida nella rete locale",620)
	lan_panel = true
	var session: Node = game.lan
	session.enable_discovery(true)
	if lan_note != "":
		paragraph(body,lan_note,580).add_theme_color_override("font_color",GOLD)
	if session.role == "host":
		label(body,"STANZA CREATA",15,GOLD,true)
		label(body,"Codice · "+session.room_code,30,IVORY,true)
		var ips: PackedStringArray = session.local_addresses()
		paragraph(body,"IP · "+(" / ".join(ips) if not ips.is_empty() else "Nessuna rete locale trovata"),580)
		paragraph(body,session.status,580).add_theme_color_override("font_color",IVORY)
		if session.active:
			button(body,"INIZIA LA SFIDA",session.start_match,0,true)
	elif session.role == "guest":
		paragraph(body,session.status,580).add_theme_color_override("font_color",IVORY)
	else:
		paragraph(body,"Due dispositivi sulla stessa rete. Il primo crea la stanza; il secondo la trova tra le stanze vicine e tocca Entra, senza codice. Per una connessione manuale usa IP e codice.",580)
		button(body,"CREA STANZA",session.host_room,0,true)
		var address_input := LineEdit.new()
		address_input.placeholder_text = "IP del creatore · es. 192.168.1.20"
		address_input.custom_minimum_size.y = 45
		body.add_child(address_input)
		var code_input := LineEdit.new()
		code_input.placeholder_text = "Codice stanza · 6 cifre"
		code_input.max_length = 6
		code_input.custom_minimum_size.y = 45
		body.add_child(code_input)
		button(body,"UNISCITI ALLA STANZA",func():session.join_room(address_input.text.strip_edges(),code_input.text.strip_edges()))
		if not session.rooms.is_empty():
			label(body,"STANZE VICINE",15,GOLD,true)
			for ip in session.rooms:
				var entry: Dictionary = session.rooms[ip]
				if str(entry.code) != "":
					button(body,"ENTRA · "+entry.name+" · "+ip,func():session.join_room(ip,str(entry.code)),0,true)
				else:
					button(body,entry.name+" · "+ip+" · serve il codice",func():address_input.text = ip)
		button(body,"Aggiorna stanze vicine",show_lan)
	paragraph(body,"Se non vi vedete: controllate la rete, disattivate l’isolamento client del router oppure usate un hotspot. Non serve aprire porte su Internet.",580)
	button(body,"Chiudi stanza" if session.role != "" else "Indietro",close_dialog)

func show_online() -> void:
	var body := modal("Partita online",640)
	online_panel = true
	var session: Node = game.lan
	if session.role == "" and not session.active and session.online.role != "browse":
		session.online_browse()
	if lan_note != "":
		paragraph(body,lan_note,600).add_theme_color_override("font_color",GOLD)
		lan_note = ""
	if session.role == "host":
		label(body,"STANZA ONLINE APERTA",15,GOLD,true)
		label(body,"Invito · "+OnlineLink.format_invite(session.invite_code),30,IVORY,true)
		paragraph(body,session.status,600).add_theme_color_override("font_color",IVORY)
		button(body,"COPIA IL CODICE INVITO",func():DisplayServer.clipboard_set(OnlineLink.format_invite(session.invite_code)))
		if session.active:
			button(body,"INIZIA LA SFIDA",session.start_match,0,true)
	elif session.role == "guest":
		paragraph(body,session.status,600).add_theme_color_override("font_color",IVORY)
	else:
		paragraph(body,"Crea una stanza e passa il codice invito a un amico, oppure rendila pubblica per farla comparire nell’elenco. Per entrare scegli una stanza o scrivi il codice invito.",600)
		button(body,"CREA STANZA PUBBLICA",func():session.host_online(true),0,true)
		button(body,"CREA STANZA CON INVITO",func():session.host_online(false))
		var invite_input := LineEdit.new()
		invite_input.placeholder_text = "Codice invito · es. K7QF-2M9X"
		invite_input.max_length = 9
		invite_input.text = invite_text
		invite_input.custom_minimum_size.y = 45
		invite_input.text_changed.connect(func(value:String):invite_text = value)
		body.add_child(invite_input)
		button(body,"ENTRA CON IL CODICE",func():session.join_online_invite(invite_input.text))
		label(body,"STANZE ONLINE",15,GOLD,true)
		var shown := 0
		for id in session.online.rooms:
			var entry: Dictionary = session.online.rooms[id]
			shown += 1
			if entry.free:
				button(body,"ENTRA · "+entry.name,func():session.join_online_room(id),0,true)
			else:
				paragraph(body,entry.name+" · stanza piena",600)
		if shown == 0:
			paragraph(body,"Nessuna stanza pubblica trovata per ora. L’elenco si aggiorna da solo; puoi crearne una tu.",600)
		button(body,"Cerca di nuovo",session.online.browse)
	paragraph(body,"Il collegamento è diretto: l’altro giocatore può vedere il tuo indirizzo IP. Per trovarsi si usano tracker pubblici gratuiti di terzi; se non rispondono, la sfida LAN resta disponibile.",600)
	button(body,"Chiudi stanza" if session.role != "" else "Indietro",close_dialog)

func refresh_lan() -> void:
	if game.lan.started:
		return
	if online_panel:
		show_online()
	elif lan_panel:
		show_lan()

func lan_problem(message: String) -> void:
	lan_note = message
	if game.phase == "menu":
		if online_panel:
			show_online()
		else:
			show_lan()

func show_updates() -> void:
	var update: Node = game.updater
	var body := modal("Aggiornamenti",620)
	updates_panel = true
	updates_signature = update.state+str(update.release.get("version",""))
	label(body,"SESTRIA · VERSIONE "+update.current_version,17,GOLD,true)
	updates_message = paragraph(body,update.message,580)
	updates_message.add_theme_color_override("font_color",IVORY)
	if update.state in ["downloading","verifying","ready"]:
		updates_meter = ProgressBar.new()
		updates_meter.max_value = 1
		updates_meter.value = update.progress
		updates_meter.custom_minimum_size.y = 14
		updates_meter.show_percentage = false
		body.add_child(updates_meter)
	if update.state == "available":
		label(body,"NUOVA VERSIONE · "+str(update.release.version),17,MINT,true)
		if not str(update.release.notes).is_empty():
			paragraph(body,str(update.release.notes),580)
		if update.release.get("mode","package")=="content":
			button(body,"AGGIORNA",update.download_update,0,true)
		else:
			button(body,"SCARICA PACCHETTO COMPLETO",update.download_update,0,true)
	elif update.state == "ready":
		if update.release.get("mode","package")=="content":
			if game.phase != "menu":
				paragraph(body,"Il riavvio chiude la partita in corso.",580)
			button(body,"RIAVVIA PER APPLICARE",update.restart_to_apply,0,true)
		else:
			button(body,"MOSTRA NELLA CARTELLA DOWNLOAD",update.reveal_update,0,true)
	elif update.state in ["checking","downloading"]:
		button(body,"Annulla",update.cancel)
	elif update.state != "verifying":
		button(body,"VERIFICA NUOVI AGGIORNAMENTI",update.check_updates,0,true)
	paragraph(body,"Gli aggiornamenti provengono dalle release pubbliche di GitHub. Premi Aggiorna: l’app scarica i nuovi contenuti, ne controlla firma e SHA-256 e li applica al riavvio. Se una versione cambia anche il motore, si scarica il pacchetto completo in Download e lo si sostituisce a mano.",580)
	button(body,"Apri le release su GitHub",func():OS.shell_open(update.RELEASES))
	if not update.last_checked.is_empty():
		paragraph(body,"Ultima verifica · "+update.last_checked,580)
	button(body,"Torna alle impostazioni",func():show_settings(3))

func refresh_updates() -> void:
	if not updates_panel:
		return
	var update: Node = game.updater
	if updates_signature != update.state+str(update.release.get("version","")):
		if not updates_refresh_pending:
			updates_refresh_pending = true
			apply_updates_refresh.call_deferred()
	elif is_instance_valid(updates_message):
		updates_message.text = update.message
		if is_instance_valid(updates_meter):
			updates_meter.value = update.progress

func apply_updates_refresh() -> void:
	updates_refresh_pending = false
	if updates_panel and is_instance_valid(dialog):
		show_updates()

# ---- Compatibilità con il gioco 4.8 (interfaccia classica) ----
var hub: Control = null

func refresh_friends() -> void:
	pass

func friend_invited(_from_name: String, _code: String) -> void:
	pass

# Passa e gioca si avvia solo dalla nuova interfaccia; questi due servono se si passa all'interfaccia classica a metà.
func handoff(next_name: String, ready: Callable) -> void:
	
	var body := modal("Passa il dispositivo",480)
	paragraph(body,"Ora tocca a %s. La tattica appena scelta resta segreta fino alla risoluzione." % next_name,440)
	button(body,"SONO %s, PRONTO" % next_name.to_upper(),func():
		close_dialog()
		ready.call(),0,true)

func finish_hotseat() -> void:
	game.menu()

# Passa alla nuova interfaccia (solo dal menu).
func use_new_interface() -> void:
	game.switch_ui(false)
