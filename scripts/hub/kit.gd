extends RefCounted
# Kit dell'interfaccia di SESTRIA 4.8, in stile rustico: legno di quercia con cantonali di ferro e rivetti, pergamena
# bruciacchiata, cuoio cucito, targhe di ottone, ceralacca. Le texture sono in assets/ui/rustic (tools/make_rustic_assets.gd).
# Serve sia al desktop e al web (orizzontale) sia ad Android (verticale): `portrait` ingrandisce misure e tocchi.
const DISPLAY_FONT = preload("res://assets/fonts/UncialAntiqua-Regular.ttf")
const BODY_FONT = preload("res://assets/fonts/Alegreya.ttf")
const MARK = preload("res://assets/ui/logo_mark.svg")
const SKIN := "res://assets/ui/rustic/"

# Colori del testo su legno scuro, su pergamena e accenti.
const TEXT := Color("#f6e8c6")
const MUTED := Color("#d2bd90")
const DIM := Color("#a89168")
const INK := Color("#2c1809")
const INK_SOFT := Color("#5a3a1c")
const WOOD := Color("#3c2413")
const WOOD_DARK := Color("#20120a")
const LEATHER := Color("#3b2214")
const LEATHER_LIGHT := Color("#5e3a22")
const BRASS := Color("#e0b04a")
const BRASS_DARK := Color("#9b6a22")
const EMBER := Color("#f0a23a")
const EMBER_LIGHT := Color("#ffd98a")
const MOSS := Color("#8fb86a")
const VERDIGRIS := Color("#6fb0a2")
const WINE := Color("#c4485a")
const MAUVE := Color("#b08ad0")
# Alias dei nomi usati dalle pagine.
const AZURE := VERDIGRIS
const MINT := MOSS
const ROSE := WINE
const VIOLET := MAUVE
const LINE := Color("#6b4a2a")
const NIGHT := WOOD_DARK
const BASE := WOOD
const RAISED := LEATHER
const HIGH := LEATHER_LIGHT

static var portrait := false
static var fonts := {}
static var cache := {}
static var audio: Node = null          # gestore dei suoni (hub_audio.gd), assegnato dal menu

static func scale(value: float) -> float:
	return value*(1.4 if portrait else 1.0)

# ---- Suoni ----

static func sfx(name: String) -> void:
	if audio != null and is_instance_valid(audio):
		audio.play_sfx(name)

# ---- Texture e stili ----

static func tex(name: String) -> Texture2D:
	var key := "t_"+name
	if not cache.has(key):
		cache[key] = load(SKIN+name+".png")
	return cache[key]

# Stile a 9 fette da una texture della pelle rustica. `edge` = bordo che non si deforma, `inner` = margine del contenuto.
static func tex_style(name: String, edge: float, inner: float, extra_h := 0.0, extra_v := 0.0) -> StyleBoxTexture:
	var key := "s_%s_%d_%d_%d_%d" % [name,edge,inner,extra_h,extra_v]
	if cache.has(key):
		return cache[key]
	var style := StyleBoxTexture.new()
	style.texture = tex(name)
	style.set_texture_margin_all(edge)
	style.set_content_margin_all(inner)
	style.content_margin_left = inner+extra_h
	style.content_margin_right = inner+extra_h
	style.content_margin_top = inner+extra_v
	style.content_margin_bottom = inner+extra_v
	cache[key] = style
	return style

static func flat(fill: Color, border := Color.TRANSPARENT, radius := 10, border_width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	return style

static func box_style(fill: Color, border := Color.TRANSPARENT, radius := 10, border_width := 1, shadow := 0) -> StyleBoxFlat:
	var style := flat(fill,border,radius,border_width)
	if shadow > 0:
		style.shadow_color = Color(0,0,0,.4)
		style.shadow_size = shadow
	return style

static func pad(style: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	style.content_margin_left = scale(horizontal)
	style.content_margin_right = scale(horizontal)
	style.content_margin_top = scale(vertical)
	style.content_margin_bottom = scale(vertical)
	return style

# ---- Tipografia ----

static func body_font(weight := 400) -> Font:
	var key := "b%d" % weight
	if not fonts.has(key):
		var font := FontVariation.new()
		font.base_font = BODY_FONT
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"):weight}
		font.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("lnum"):1}
		fonts[key] = font
	return fonts[key]

static func display_font(spacing := 0) -> Font:
	var key := "d%d" % spacing
	if not fonts.has(key):
		var font := FontVariation.new()
		font.base_font = DISPLAY_FONT
		font.spacing_glyph = spacing
		fonts[key] = font
	return fonts[key]

static func label(parent: Node, text: String, size := 16, color := TEXT, display := false, weight := 500) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font",display_font(1) if display else body_font(weight))
	item.add_theme_font_size_override("font_size",roundi(scale(size*(1.0 if display else 1.12))))
	item.add_theme_color_override("font_color",color)
	if color.get_luminance() > .55:
		item.add_theme_color_override("font_shadow_color",Color(0,0,0,.55))
		item.add_theme_constant_override("shadow_offset_x",1)
		item.add_theme_constant_override("shadow_offset_y",2)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(item)
	return item

static func paragraph(parent: Node, text: String, width := 0.0, size := 15, color := MUTED) -> Label:
	var item := label(parent,text,size,color,false,500)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		item.custom_minimum_size.x = width
	else:
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

# Titolo con contorno scuro e ombra, come inciso nel legno o dipinto sull'insegna.
static func title(parent: Node, text: String, size := 34, color := EMBER_LIGHT) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font",display_font(2))
	item.add_theme_font_size_override("font_size",roundi(scale(size)))
	item.add_theme_color_override("font_color",color)
	item.add_theme_color_override("font_outline_color",Color("#1b0e05"))
	item.add_theme_constant_override("outline_size",roundi(scale(size)*.16))
	item.add_theme_color_override("font_shadow_color",Color(0,0,0,.6))
	item.add_theme_constant_override("shadow_offset_x",2)
	item.add_theme_constant_override("shadow_offset_y",3)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(item)
	return item

# ---- Contenitori ----

# tone: wood (cornice di legno con ferro), bar (assi orizzontali), leather (scuro, per i riquadri), parchment
static func panel(parent: Node, tone := "wood", padding := 18.0, _radius := 0) -> PanelContainer:
	var frame := PanelContainer.new()
	match tone:
		"parchment":
			frame.add_theme_stylebox_override("panel",tex_style("parchment",22,18,scale(padding)-12.0,scale(padding)*.5))
		"leather","raised":
			var style := flat(Color(LEATHER.r,LEATHER.g,LEATHER.b,.92),Color("#150b05"),10,2)
			style.set_content_margin_all(scale(padding)*.75)
			style.shadow_color = Color(0,0,0,.35)
			style.shadow_size = 5
			frame.add_theme_stylebox_override("panel",style)
		"bar":
			frame.add_theme_stylebox_override("panel",tex_style("wood_bar",40,scale(10),scale(padding)))
		_:
			frame.add_theme_stylebox_override("panel",tex_style("wood_panel",40,scale(18),scale(padding)-8.0,scale(padding)-8.0))
	if parent:
		parent.add_child(frame)
	return frame

static func column(parent: Node, gap := 12.0) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",roundi(scale(gap)))
	if parent:
		parent.add_child(box)
	return box

static func row(parent: Node, gap := 10.0) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation",roundi(scale(gap)))
	if parent:
		parent.add_child(box)
	return box

static func spacer(parent: Node, expand := true, height := 0.0) -> Control:
	var space := Control.new()
	space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	space.custom_minimum_size.y = height
	parent.add_child(space)
	return space

static func margin(parent: Node, left: float, top: float, right: float, bottom: float) -> MarginContainer:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_left",roundi(scale(left)))
	holder.add_theme_constant_override("margin_top",roundi(scale(top)))
	holder.add_theme_constant_override("margin_right",roundi(scale(right)))
	holder.add_theme_constant_override("margin_bottom",roundi(scale(bottom)))
	if parent:
		parent.add_child(holder)
	return holder

# Zona scorrevole: restituisce il contenuto verticale. Un trascinamento con il dito o la rotella la fa scorrere.
static func scroll(parent: Node, gap := 14.0) -> VBoxContainer:
	var area := ScrollContainer.new()
	area.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(area)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation",roundi(scale(gap)))
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	area.add_child(inner)
	return inner

static func divider(parent: Node) -> void:
	var line := TextureRect.new()
	line.texture = tex("divider")
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.custom_minimum_size = Vector2(0,scale(14))
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

# ---- Animazioni ----

# Dissolvenza in ingresso, ritardata per far comparire gli elementi uno dopo l'altro.
static func appear(node: Control, delay := 0.0) -> void:
	if not node.is_inside_tree():
		return
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_interval(delay)
	tween.tween_property(node,"modulate:a",1.0,.3).set_ease(Tween.EASE_OUT)

# Piccola animazione di pressione e ingrandimento al passaggio del mouse, con suono.
static func juice(item: Control, hover_sound := "hover", press_sound := "click") -> void:
	item.resized.connect(func():item.pivot_offset = item.size*.5)
	item.mouse_entered.connect(func():
		if item is BaseButton and item.disabled:
			return
		sfx(hover_sound)
		var tween := item.create_tween()
		tween.tween_property(item,"scale",Vector2(1.035,1.035),.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))
	item.mouse_exited.connect(func():
		var tween := item.create_tween()
		tween.tween_property(item,"scale",Vector2.ONE,.12))
	if item is BaseButton:
		item.button_down.connect(func():
			sfx(press_sound)
			var tween := item.create_tween()
			tween.tween_property(item,"scale",Vector2(.965,.965),.05))
		item.button_up.connect(func():
			var tween := item.create_tween()
			tween.tween_property(item,"scale",Vector2(1.035,1.035),.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT))

# ---- Pulsanti ----

# kind: primary (targa d'ottone), secondary (cuoio), ghost (solo testo), danger (cuoio rosso)
static func button(parent: Node, text: String, callback: Callable, kind := "secondary", minimum := 0.0) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(scale(minimum),scale(50))
	item.add_theme_font_override("font",display_font(1))
	item.add_theme_font_size_override("font_size",roundi(scale(18)))
	var base := "brass" if kind == "primary" else "leather"
	if kind == "ghost":
		var empty := StyleBoxEmpty.new()
		empty.set_content_margin_all(scale(8))
		for key in ["normal","hover","pressed","disabled"]:
			item.add_theme_stylebox_override(key,empty)
	else:
		for state in ["normal","hover","pressed","disabled"]:
			var style: StyleBoxTexture = tex_style("%s_%s" % [base,state],22,scale(8),scale(14),scale(4)).duplicate()
			if kind == "danger":
				style.modulate_color = Color(1.15,.62,.62)
			item.add_theme_stylebox_override(state,style)
	var ink := INK if kind == "primary" else (MUTED if kind == "ghost" else TEXT)
	for key in ["font_color","font_pressed_color"]:
		item.add_theme_color_override(key,ink)
	item.add_theme_color_override("font_hover_color",INK if kind == "primary" else EMBER_LIGHT)
	item.add_theme_color_override("font_disabled_color",DIM)
	if kind != "primary":
		item.add_theme_color_override("font_shadow_color",Color(0,0,0,.7))
		item.add_theme_constant_override("shadow_offset_y",2)
	item.pressed.connect(callback)
	juice(item)
	if parent:
		parent.add_child(item)
	return item

# ---- Etichette e indicatori ----

# Targhetta: piccola etichetta di cuoio con bordo colorato.
static func chip(parent: Node, text: String, color := EMBER) -> PanelContainer:
	var frame := PanelContainer.new()
	var style := flat(Color(color.r*.25,color.g*.25,color.b*.25,.95),color.darkened(.1),8,2)
	style.content_margin_left = scale(10)
	style.content_margin_right = scale(10)
	style.content_margin_top = scale(3)
	style.content_margin_bottom = scale(3)
	frame.add_theme_stylebox_override("panel",style)
	label(frame,text,12,color.lightened(.35),false,700)
	if parent:
		parent.add_child(frame)
	return frame

class Meter extends Control:
	var value := 0.0
	var maximum := 1.0
	var groove: StyleBoxTexture
	var fill: StyleBoxTexture
	func _draw() -> void:
		draw_style_box(groove,Rect2(Vector2.ZERO,size))
		var ratio := clampf(value/maxf(maximum,.0001),0.0,1.0)
		if ratio > 0.0:
			var inset := size.y*.16
			var width := maxf(size.y*.7,(size.x-inset*2.0)*ratio)
			draw_style_box(fill,Rect2(Vector2(inset,inset),Vector2(width,size.y-inset*2.0)))
	func set_value(v: float, m: float) -> void:
		value = v
		maximum = m
		queue_redraw()

# Barra di avanzamento incisa nel legno, riempita di brace. `set_value()` sul controllo restituito.
static func meter(parent: Node, value: float, maximum: float, height := 14.0, _colors := []) -> Meter:
	var bar := Meter.new()
	bar.value = value
	bar.maximum = maximum
	bar.groove = tex_style("xp_groove",10,0)
	bar.fill = tex_style("xp_fill",8,0)
	bar.custom_minimum_size.y = scale(height)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(bar)
	return bar

# ---- Schede ----

# Barra di tavolette di legno. `items` = nomi; `callback(index)`. La scheda attiva è illuminata con un filo d'ottone.
static func tabs(parent: Node, items: Array, active: int, callback: Callable, fill := false) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation",roundi(scale(4)))
	if parent:
		parent.add_child(bar)
	for index in items.size():
		var selected := index == active
		var item := Button.new()
		item.text = str(items[index])
		item.focus_mode = Control.FOCUS_NONE
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.custom_minimum_size = Vector2(0,scale(50))
		item.add_theme_font_override("font",display_font(1))
		item.add_theme_font_size_override("font_size",roundi(scale(16)))
		item.add_theme_stylebox_override("normal",tex_style("tab_active" if selected else "tab_normal",18,scale(5),scale(8),scale(3)))
		item.add_theme_stylebox_override("hover",tex_style("tab_active" if selected else "tab_hover",18,scale(5),scale(8),scale(3)))
		item.add_theme_stylebox_override("pressed",tex_style("tab_pressed",18,scale(5),scale(8),scale(3)))
		var tone := EMBER_LIGHT if selected else MUTED
		item.add_theme_color_override("font_color",tone)
		item.add_theme_color_override("font_pressed_color",tone)
		item.add_theme_color_override("font_hover_color",EMBER_LIGHT if selected else TEXT)
		item.add_theme_color_override("font_shadow_color",Color(0,0,0,.8))
		item.add_theme_constant_override("shadow_offset_y",2)
		if fill:
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.pressed.connect(callback.bind(index))
		juice(item,"hover","tab")
		bar.add_child(item)
	return bar

# Scheda di scelta visuale: un foglio di pergamena con titolo e descrizione; quella scelta ha il sigillo di ceralacca.
class Card extends PanelContainer:
	signal chosen
	var selected := false
	var accent := Color("#f0a23a")
	var paper: StyleBoxTexture
	func _init(is_selected := false, color := Color("#f0a23a")) -> void:
		selected = is_selected
		accent = color
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var kit = load("res://scripts/hub/kit.gd")
		paper = kit.tex_style("parchment",22,16,12,6).duplicate()
		paper.modulate_color = Color(1.0,.92,.74) if selected else Color(.9,.84,.72)
		add_theme_stylebox_override("panel",paper)
		resized.connect(func():pivot_offset = size*.5)
		mouse_entered.connect(func():
			kit.sfx("hover")
			create_tween().tween_property(self,"scale",Vector2(1.015,1.015),.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			paper.modulate_color = Color(1.0,.96,.82))
		mouse_exited.connect(func():
			create_tween().tween_property(self,"scale",Vector2.ONE,.12)
			paper.modulate_color = Color(1.0,.92,.74) if selected else Color(.9,.84,.72))
	func _draw() -> void:
		if selected:
			var kit = load("res://scripts/hub/kit.gd")
			var side := minf(size.y*.5,34.0)
			draw_texture_rect(kit.tex("seal"),Rect2(size.x-side-12,10,side,side),false)
			draw_line(Vector2(size.x-side*.8-12,10+side*.52),Vector2(size.x-side*.5-12,10+side*.78),Color("#f6d8a8"),2.4,true)
			draw_line(Vector2(size.x-side*.5-12,10+side*.78),Vector2(size.x-side*.2-12,10+side*.3),Color("#f6d8a8"),2.4,true)
	# La scelta scatta al rilascio, se il dito non si è mosso: trascinare la lista non deve scegliere nulla.
	var press_at := Vector2.ZERO
	var pressing := false
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				press_at = event.global_position
				pressing = true
			elif pressing:
				pressing = false
				if event.global_position.distance_to(press_at) < 14.0:
					load("res://scripts/hub/kit.gd").sfx("click")
					chosen.emit()
					accept_event()

static func card(parent: Node, title_text: String, subtitle: String, selected: bool, callback: Callable, color := EMBER, icon := "") -> Card:
	var item := Card.new(selected,color)
	if parent:
		parent.add_child(item)
	var body := column(item,2)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := row(body,8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon.is_empty():
		var tag := label(head,icon,18,color.darkened(.35),true)
		tag.remove_theme_color_override("font_shadow_color")
	var name := label(head,title_text,19,INK,true)
	name.remove_theme_color_override("font_shadow_color")
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not subtitle.is_empty():
		var sub := paragraph(body,subtitle,0.0,14,INK_SOFT)
		sub.remove_theme_color_override("font_shadow_color")
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.chosen.connect(callback)
	return item

# Riga "etichetta · controllo" per le impostazioni.
static func setting_row(parent: Node, title_text: String, hint := "") -> HBoxContainer:
	var line := row(parent,16)
	var texts := column(line,0)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(texts,title_text,17,TEXT,false,600)
	if not hint.is_empty():
		paragraph(texts,hint,0.0,13,DIM)
	return line

# Selettore a segmenti: tasselli di cuoio, quello scelto è una targa d'ottone. `callback(index)`.
static func segments(parent: Node, items: Array, active: int, callback: Callable, _color := EMBER) -> Container:
	var bar: Container
	if portrait:
		bar = HFlowContainer.new()
		bar.add_theme_constant_override("h_separation",roundi(scale(4)))
		bar.add_theme_constant_override("v_separation",roundi(scale(4)))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		bar = HBoxContainer.new()
		bar.add_theme_constant_override("separation",roundi(scale(4)))
	if parent:
		parent.add_child(bar)
	for index in items.size():
		var selected := index == active
		var item := Button.new()
		item.text = str(items[index])
		item.focus_mode = Control.FOCUS_NONE
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.custom_minimum_size = Vector2(scale(52),scale(40))
		item.add_theme_font_override("font",body_font(700))
		item.add_theme_font_size_override("font_size",roundi(scale(16)))
		var base := "brass" if selected else "leather"
		item.add_theme_stylebox_override("normal",tex_style(base+"_normal",18,scale(6),scale(10),scale(2)))
		item.add_theme_stylebox_override("hover",tex_style(base+"_hover",18,scale(6),scale(10),scale(2)))
		item.add_theme_stylebox_override("pressed",tex_style(base+"_pressed",18,scale(6),scale(10),scale(2)))
		item.add_theme_color_override("font_color",INK if selected else TEXT)
		item.add_theme_color_override("font_hover_color",INK if selected else EMBER_LIGHT)
		item.add_theme_color_override("font_pressed_color",INK if selected else TEXT)
		item.pressed.connect(callback.bind(index))
		juice(item)
		bar.add_child(item)
	return bar

static func toggle(parent: Node, value: bool, callback: Callable) -> Button:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.custom_minimum_size = Vector2(scale(64),scale(38))
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.text = "SÌ" if value else "NO"
	item.add_theme_font_override("font",body_font(700))
	item.add_theme_font_size_override("font_size",roundi(scale(15)))
	var base := "brass" if value else "leather"
	for state in ["normal","hover","pressed"]:
		item.add_theme_stylebox_override(state,tex_style("%s_%s" % [base,state],18,scale(6),scale(10),scale(2)))
	for key in ["font_color","font_hover_color","font_pressed_color"]:
		item.add_theme_color_override(key,INK if value else TEXT)
	item.pressed.connect(func():callback.call(not value))
	juice(item)
	if parent:
		parent.add_child(item)
	return item

# Sigillo di ceralacca con un numero (il livello del giocatore).
static func seal(parent: Node, text: String, side := 44.0) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(scale(side),scale(side))
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var image := TextureRect.new()
	image.texture = tex("seal")
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_SCALE
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(image)
	var number := label(holder,text,side*.42,Color("#fbe6c2"),true)
	number.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if parent:
		parent.add_child(holder)
	return holder

# Cursore con scanalatura di legno e pomello d'ottone. `callback(valore)`.
static func slider(parent: Node, low: float, high: float, step: float, value: float, callback: Callable) -> HSlider:
	var control := HSlider.new()
	control.min_value = low
	control.max_value = high
	control.step = step
	control.value = value
	control.focus_mode = Control.FOCUS_NONE
	control.custom_minimum_size = Vector2(scale(180),scale(30))
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	control.add_theme_stylebox_override("slider",tex_style("xp_groove",10,0))
	control.add_theme_stylebox_override("grabber_area",tex_style("xp_fill",8,0))
	control.add_theme_stylebox_override("grabber_area_highlight",tex_style("xp_fill",8,0))
	var knob := tex("knob")
	control.add_theme_icon_override("grabber",knob)
	control.add_theme_icon_override("grabber_highlight",knob)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	control.value_changed.connect(callback)
	if parent:
		parent.add_child(control)
	return control

# Selettore con frecce per molte opzioni: «‹ valore ›».
static func stepper(parent: Node, names: Array, index: int, callback: Callable, minimum := 220.0) -> HBoxContainer:
	var line := row(parent,6)
	var back := button(line,"‹",func():callback.call((index-1+names.size())%names.size()),"secondary")
	back.custom_minimum_size.x = scale(48)
	var shown := label(line,str(names[clampi(index,0,names.size()-1)]),17,EMBER_LIGHT,false,700)
	shown.custom_minimum_size.x = scale(minimum)
	shown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var forward := button(line,"›",func():callback.call((index+1)%names.size()),"secondary")
	forward.custom_minimum_size.x = scale(48)
	return line

static func format_number(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	for i in text.length():
		if i > 0 and (text.length()-i)%3 == 0:
			out += "."
		out += text[i]
	return ("-" if value < 0 else "")+out
