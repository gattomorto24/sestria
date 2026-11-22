extends Control
const OnlineLink = preload("res://scripts/online_link.gd")

const Rules = preload("res://scripts/rules.gd")
const Platform = preload("res://scripts/platform.gd")
const TITLES := ["Esploratore","Guerriero","Maestro"]
const Kit = preload("res://scripts/hub/kit.gd")
const MINT := Color("#9cc878")
const IVORY := Color("#f6e8c6")
const MUTED := Color("#d2bd90")
const GOLD := Color("#ffd98a")
const TURQUOISE := Color("#7fc4b6")
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
	Kit.portrait = portrait
	main_title = Kit.display_font(1)
	body_text = Kit.body_font(500)
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
		palette.set_color("font_hover_color","Button",GOLD)
		palette.set_color("font_pressed_color","Button",GOLD)
		palette.set_color("font_disabled_color","Button",Kit.DIM)
	palette.set_constant("outline_size","Button",0)
	for state in ["normal","hover","pressed","disabled","focus"]:
		palette.set_stylebox(state,"OptionButton",button_skin(button_art[state]))
	palette.set_color("font_color","OptionButton",IVORY)
	palette.set_color("font_hover_color","OptionButton",GOLD)
	palette.set_stylebox("panel","PopupMenu",chrome(FRAME,27,27,15,12))
	palette.set_stylebox("hover","PopupMenu",skin(Kit.LEATHER_LIGHT,Kit.BRASS,4))
	palette.set_color("font_color","PopupMenu",IVORY)
	palette.set_stylebox("slider","HSlider",Kit.tex_style("xp_groove",10,0))
	palette.set_stylebox("grabber_area","HSlider",Kit.tex_style("xp_fill",8,0))
	palette.set_stylebox("grabber_area_highlight","HSlider",Kit.tex_style("xp_fill",8,0))
	for state in ["grabber","grabber_highlight","grabber_disabled"]:
		palette.set_icon(state,"HSlider",Kit.tex("knob"))
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

# Le vecchie texture dell'interfaccia (verde e oro) vengono sostituite dalla pelle rustica del nuovo kit.
func chrome(texture: Texture2D, sx: int, sy: int, horizontal: int, vertical: int) -> StyleBoxTexture:
	var skin_name := "leather_normal"
	var edge := 22.0
	if texture == PRIMARY or texture == SELECTED:
		skin_name = "brass_normal"
	elif texture == HOVER:
		skin_name = "leather_hover"
	elif texture == DISABLED:
		skin_name = "leather_disabled"
	elif texture == FRAME:
		skin_name = "wood_panel"
		edge = 40.0
	elif texture == TAB:
		skin_name = "tab_normal"
		edge = 18.0
	elif texture == TAB_ACTIVE:
		skin_name = "tab_active"
		edge = 18.0
	var style: StyleBoxTexture = Kit.tex_style(skin_name,edge,0).duplicate()
	var extra := 6.0 if skin_name != "wood_panel" else 0.0
	style.content_margin_left = maxf(horizontal,edge*.5)+extra
	style.content_margin_right = maxf(horizontal,edge*.5)+extra
	style.content_margin_top = maxf(vertical,edge*.25)
	style.content_margin_bottom = maxf(vertical,edge*.25)
	return style

func button_skin(texture: Texture2D) -> StyleBoxTexture:
	var style := chrome(texture,39,16,27,13)
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

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
	if hub != null:
		hub.visible = false
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
	title.add_theme_font_size_override("font_size",maxi(size,26) if portrait else (roundi(size*.88) if serif else roundi(size*1.1)))
	title.add_theme_color_override("font_color",color)
	title.add_theme_font_override("font",main_title if serif else body_text)
	title.mouse_filter = MOUSE_FILTER_IGNORE
	parent.add_child(title)
	return title

func divider(parent: Node) -> void:
	Kit.divider(parent)

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

var hub: Control

func show_menu() -> void:
	clear_screen()
	ensure_hub()
	hub.open()
	return

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

func ensure_hub() -> void:
	if hub == null:
		hub = preload("res://scripts/hub/hub.gd").new()
		add_child(hub)
		hub.setup(game,self,portrait)

# Le impostazioni stanno nella scheda Opzioni del menu; durante una partita si aprono sopra al tavolo.
func show_settings(active = 0) -> void:
	ensure_hub()
	var tab: String = active if active is String else ["audio","graphics","controls","system"][clampi(active,0,3)]
	hub.open("options",{"tab":tab,"overlay":game.phase != "menu"})
	return

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
		var nameplate := label(card,(str(game.player_names[side]).to_upper() if game.hotseat else ("AVVERSARIO" if side == 1 else "TU")),14,GOLD)
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
	action(("%s: scegli un totem o passa" % game.player_names[game.acting]) if game.hotseat else "Scegli un totem o passa", "Passa",game.resolve.bind({}))
	var row := HBoxContainer.new()
	prompt_layout.add_child(row)
	prompt_layout.move_child(row,0)
	for id in game.loadout(game.acting):
		var short: String = Rules.FAVOR[id][0].split("’")[0]
		var entry := button(row,short,game.inspect_favor.bind(game.acting,id),0)
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
		sacrifice.min_value = 1.0 if game.rules.hp[game.acting] > 1 else 0.0
		sacrifice.max_value = maxi(0,game.rules.hp[game.acting]-1)
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

# Passa e gioca: schermata di passaggio, così il secondo giocatore sceglie la tattica senza vedere l'altra.
func handoff(next_name: String, ready: Callable) -> void:
	var body := modal("Passa il dispositivo",480)
	paragraph(body,"Ora tocca a %s. La tattica appena scelta resta segreta fino alla risoluzione: consegna il dispositivo e premi il pulsante." % next_name,440)
	button(body,"SONO %s, PRONTO" % next_name.to_upper(),func():
		close_dialog()
		ready.call(),0,true)
	Kit.sfx("open")

func finish_hotseat() -> void:
	var winner: int = game.rules.winner
	var body := modal("Vince %s" % game.player_names[winner],520)
	paragraph(body,"Pietre rimaste   ·   %s %d   /   %s %d" % [game.player_names[0],game.rules.hp[0],game.player_names[1],game.rules.hp[1]],480)
	button(body,"RIVINCITA",func():
		close_dialog()
		game.start_hotseat(game.player_names[0],game.player_names[1]),0,true)
	button(body,"Menu principale",game.menu)

func finish(victory: bool) -> void:
	if game.hotseat:
		finish_hotseat()
		return
	var campaign: bool = game.active_campaign != ""
	var body := modal("Vittoria!" if victory else "La partita è persa",540)
	Kit.sfx("confirm" if victory else "back")
	paragraph(body,"Pietre rimaste   ·   Tu %d   /   Avversario %d" % game.rules.hp,480)
	if game.lan and game.lan.active:
		if game.lan.role == "host":
			button(body,"UNA NUOVA SFIDA",game.rematch_lan,0,true)
		else:
			paragraph(body,"Il creatore della stanza può iniziare una nuova sfida.",480)
	else:
		var reward: Dictionary = game.progression.last_reward
		if reward.has("error"):
			paragraph(body,str(reward.error),480)
		elif victory and reward.has("xp"):
			label(body,"+%d XP" % reward.xp,26,MINT,true)
			if int(reward.levels) > 0:
				label(body,"LIVELLO %d → %d  ·  +%d PUNTI" % [reward.from_level,reward.to_level,reward.points],17,GOLD,true)
			paragraph(body,"Livello %d · %d / %d XP" % [game.progression.level(),game.progression.xp_in_level(),game.progression.xp_required(game.progression.level())],480)
			Kit.meter(body,game.progression.xp_in_level(),game.progression.xp_required(game.progression.level()),16)
		elif not victory:
			paragraph(body,"Gli XP si guadagnano con le vittorie. I tuoi progressi e punti restano al sicuro.",480)
		if campaign:
			var index: int = game.campaigns.find(game.active_campaign)
			if index >= 0:
				var item: Dictionary = game.campaigns.campaigns[index]
				paragraph(body,"Campagna «%s» · %s · serie %d" % [item.name,game.campaigns.chapter_title(int(item.chapter)),int(item.streak)],480)
			button(body,"PROSSIMA PARTITA" if victory else "RIPROVA",func():
				close_dialog()
				game.start_campaign(game.active_campaign),0,true)
		else:
			button(body,"UN'ALTRA PARTITA",func():
				close_dialog()
				game.start_quick(),0,true)
		button(body,"I miei progressi",func():
			game.menu()
			hub.open("progress"))
	button(body,"Menu principale",game.menu)

func ask_leave() -> void:
	paused_for_menu = true
	get_tree().paused = true
	var body := modal("Lasciare il tavolo?",420)
	button(body,"Continua a giocare",close_dialog,0,true)
	button(body,"Impostazioni",show_settings)
	button(body,"Torna al menu",game.menu)

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

