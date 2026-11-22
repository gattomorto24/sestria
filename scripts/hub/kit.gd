extends RefCounted
# Kit dell'interfaccia di SESTRIA 4.8: tavolozza, tipografia e componenti (pannelli, pulsanti, schede, tab, barre).
# Serve sia al desktop e al web (orizzontale) sia ad Android (verticale): `portrait` ingrandisce misure e tocchi.
const DISPLAY_FONT = preload("res://assets/fonts/Marcellus-Regular.ttf")
const BODY_FONT = preload("res://assets/fonts/Outfit.ttf")
const MARK = preload("res://assets/ui/logo_mark.svg")

const NIGHT := Color("#080b18")
const BASE := Color("#101530")
const RAISED := Color("#182044")
const HIGH := Color("#222c5b")
const LINE := Color("#2c386e")
const TEXT := Color("#eef1ff")
const MUTED := Color("#aab5e6")
const DIM := Color("#8390c4")
const EMBER := Color("#ffa23d")
const EMBER_LIGHT := Color("#ffd08a")
const EMBER_DARK := Color("#d9622b")
const AZURE := Color("#5ad1ff")
const MINT := Color("#68e3ae")
const ROSE := Color("#ff6b86")
const VIOLET := Color("#9d7bff")

static var portrait := false
static var fonts := {}

static func scale(value: float) -> float:
	return value*(1.4 if portrait else 1.0)

# ---- Tipografia ----

static func body_font(weight := 400) -> Font:
	var key := "b%d" % weight
	if not fonts.has(key):
		var font := FontVariation.new()
		font.base_font = BODY_FONT
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"):weight}
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

static func label(parent: Node, text: String, size := 16, color := TEXT, display := false, weight := 400) -> Label:
	var item := Label.new()
	item.text = text
	item.add_theme_font_override("font",display_font(2 if size >= 26 else 1) if display else body_font(weight))
	item.add_theme_font_size_override("font_size",roundi(scale(size)))
	item.add_theme_color_override("font_color",color)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if parent:
		parent.add_child(item)
	return item

static func paragraph(parent: Node, text: String, width := 0.0, size := 15, color := MUTED) -> Label:
	var item := label(parent,text,size,color)
	item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0.0:
		item.custom_minimum_size.x = width
	else:
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return item

# ---- Stili ----

static func box_style(fill: Color, border := Color.TRANSPARENT, radius := 16, border_width := 1, shadow := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width if border.a > 0.0 else 0)
	style.set_corner_radius_all(radius)
	style.anti_aliasing = true
	if shadow > 0:
		style.shadow_color = Color(0,0,0,.38)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(0,shadow*.35)
	return style

static func pad(style: StyleBoxFlat, horizontal: float, vertical: float) -> StyleBoxFlat:
	style.content_margin_left = scale(horizontal)
	style.content_margin_right = scale(horizontal)
	style.content_margin_top = scale(vertical)
	style.content_margin_bottom = scale(vertical)
	return style

static func gradient_style(top: Color, bottom: Color, border: Color, radius := 14) -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([top,bottom])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0,0)
	texture.fill_to = Vector2(0,1)
	texture.width = 8
	texture.height = 64
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.modulate_color = Color.WHITE
	return style

# ---- Contenitori ----

static func panel(parent: Node, tone := "base", padding := 18.0, radius := 20) -> PanelContainer:
	var fills := {"base":BASE,"raised":RAISED,"high":HIGH,"night":NIGHT,"glass":Color(BASE.r,BASE.g,BASE.b,.72)}
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",pad(box_style(fills.get(tone,BASE),LINE if tone != "night" else Color.TRANSPARENT,radius,1,18 if tone != "night" else 0),padding,padding*.85))
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
	var line := ColorRect.new()
	line.color = Color(LINE.r,LINE.g,LINE.b,.7)
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

# ---- Pulsanti ----

# kind: primary (brace), secondary, ghost, danger
static func button(parent: Node, text: String, callback: Callable, kind := "secondary", minimum := 0.0) -> Button:
	var item := Button.new()
	item.text = text
	item.focus_mode = Control.FOCUS_NONE
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.custom_minimum_size = Vector2(scale(minimum),scale(46))
	item.add_theme_font_override("font",body_font(600))
	item.add_theme_font_size_override("font_size",roundi(scale(16)))
	var palette := {
		"primary":[EMBER,EMBER_DARK,Color("#1a0f05"),EMBER_LIGHT],
		"secondary":[HIGH,RAISED,TEXT,AZURE],
		"ghost":[Color(1,1,1,.03),Color(1,1,1,.0),MUTED,LINE],
		"danger":[Color("#5a1d2e"),Color("#3a1220"),Color("#ffd5dc"),ROSE]}
	var colors: Array = palette.get(kind,palette.secondary)
	var normal := box_style(colors[0],colors[3].darkened(.35) if kind != "primary" else EMBER_LIGHT,14,1,10 if kind == "primary" else 0)
	var hover := box_style(colors[0].lightened(.12),colors[3],14,1,12 if kind == "primary" else 4)
	var pressed := box_style(colors[1],colors[3],14,1,0)
	var disabled := box_style(Color(HIGH.r,HIGH.g,HIGH.b,.45),Color.TRANSPARENT,14,0,0)
	for style in [normal,hover,pressed,disabled]:
		pad(style,20,10)
	item.add_theme_stylebox_override("normal",normal)
	item.add_theme_stylebox_override("hover",hover)
	item.add_theme_stylebox_override("pressed",pressed)
	item.add_theme_stylebox_override("disabled",disabled)
	for key in ["font_color","font_hover_color","font_pressed_color"]:
		item.add_theme_color_override(key,colors[2])
	item.add_theme_color_override("font_disabled_color",DIM)
	item.pressed.connect(callback)
	if parent:
		parent.add_child(item)
	return item

# ---- Etichette e indicatori ----

static func chip(parent: Node, text: String, color := EMBER) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel",pad(box_style(Color(color.r,color.g,color.b,.16),Color(color.r,color.g,color.b,.5),99,1),10,3))
	label(frame,text,12,color,false,600)
	if parent:
		parent.add_child(frame)
	return frame

class Meter extends Control:
	var value := 0.0
	var maximum := 1.0
	var fill_a := Color("#ffd08a")
	var fill_b := Color("#ff8a3d")
	func _draw() -> void:
		var ratio := clampf(value/maxf(maximum,.0001),0.0,1.0)
		if ratio <= 0.0:
			return
		var w := maxf(size.y,size.x*ratio)
		draw_rect(Rect2(0,0,w,size.y),fill_b,true)
		draw_rect(Rect2(0,0,w,size.y*.5),fill_a,true)
	func set_value(v: float, m: float) -> void:
		value = v
		maximum = m
		queue_redraw()

# Barra con angoli tondi: un pannello arrotondato che ritaglia il riempimento. `set_value()` sul controllo restituito.
static func meter(parent: Node, value: float, maximum: float, height := 10.0, colors := [EMBER_LIGHT,EMBER]) -> Meter:
	var holder := PanelContainer.new()
	holder.add_theme_stylebox_override("panel",box_style(Color("#1b2350"),Color.TRANSPARENT,99,0))
	holder.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	holder.custom_minimum_size.y = scale(height)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := Meter.new()
	bar.value = value
	bar.maximum = maximum
	bar.fill_a = colors[0]
	bar.fill_b = colors[1]
	bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(bar)
	if parent:
		parent.add_child(holder)
	return bar

# ---- Schede ----

# Barra di schede a pillola. `items` = lista di nomi; `callback(index)`.
static func tabs(parent: Node, items: Array, active: int, callback: Callable, fill := false) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation",roundi(scale(6)))
	if parent:
		parent.add_child(bar)
	for index in items.size():
		var selected := index == active
		var item := Button.new()
		item.text = str(items[index])
		item.focus_mode = Control.FOCUS_NONE
		item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		item.custom_minimum_size = Vector2(0,scale(44))
		item.add_theme_font_override("font",body_font(600))
		item.add_theme_font_size_override("font_size",roundi(scale(15)))
		var normal := pad(box_style(Color(EMBER.r,EMBER.g,EMBER.b,.16) if selected else Color(1,1,1,.0),EMBER if selected else Color.TRANSPARENT,12,1),18,8)
		var hover := pad(box_style(Color(1,1,1,.06),Color.TRANSPARENT,12,0),18,8)
		item.add_theme_stylebox_override("normal",normal)
		item.add_theme_stylebox_override("hover",hover)
		item.add_theme_stylebox_override("pressed",normal)
		var tone := EMBER_LIGHT if selected else MUTED
		for key in ["font_color","font_hover_color","font_pressed_color"]:
			item.add_theme_color_override(key,tone if key != "font_hover_color" else TEXT)
		if fill:
			item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.pressed.connect(callback.bind(index))
		bar.add_child(item)
	return bar

# Scheda di scelta visuale: titolo, descrizione e simbolo disegnato; evidenziata se selezionata.
class Card extends PanelContainer:
	signal chosen
	var selected := false
	var accent := Color("#ffa23d")
	var hovered := false
	func _init(is_selected := false, color := Color("#ffa23d")) -> void:
		selected = is_selected
		accent = color
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		refresh()
		mouse_entered.connect(func():
			hovered = true
			refresh())
		mouse_exited.connect(func():
			hovered = false
			refresh())
	func refresh() -> void:
		var fill := Color("#182044") if not hovered else Color("#202a58")
		var border := accent if selected else Color("#2c386e")
		var style := StyleBoxFlat.new()
		style.bg_color = Color(accent.r,accent.g,accent.b,.14) if selected else fill
		style.border_color = border
		style.set_border_width_all(2 if selected else 1)
		style.set_corner_radius_all(18)
		style.anti_aliasing = true
		style.set_content_margin_all(14)
		if selected or hovered:
			style.shadow_color = Color(accent.r,accent.g,accent.b,.28 if selected else .12)
			style.shadow_size = 12
		add_theme_stylebox_override("panel",style)
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			chosen.emit()
			accept_event()
		elif event is InputEventScreenTouch and event.pressed:
			chosen.emit()

static func card(parent: Node, title: String, subtitle: String, selected: bool, callback: Callable, color := EMBER, icon := "") -> Card:
	var item := Card.new(selected,color)
	if parent:
		parent.add_child(item)
	var body := column(item,4)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var head := row(body,8)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not icon.is_empty():
		label(head,icon,22,color,true)
	var name := label(head,title,17,TEXT if selected else Color("#dfe4ff"),false,600)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if selected:
		label(head,"✓",16,color,false,700)
	if not subtitle.is_empty():
		var sub := paragraph(body,subtitle,0.0,13,MUTED)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.chosen.connect(callback)
	return item

# Riga "etichetta · controllo" per le impostazioni.
static func setting_row(parent: Node, title: String, hint := "") -> HBoxContainer:
	var line := row(parent,16)
	var texts := column(line,2)
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(texts,title,16,TEXT,false,500)
	if not hint.is_empty():
		paragraph(texts,hint,0.0,13,DIM)
	return line

# Selettore a segmenti (poche opzioni, una scelta). `callback(index)`.
static func segments(parent: Node, items: Array, active: int, callback: Callable, color := EMBER) -> HBoxContainer:
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
		item.custom_minimum_size = Vector2(scale(54),scale(40))
		item.add_theme_font_override("font",body_font(600))
		item.add_theme_font_size_override("font_size",roundi(scale(14)))
		var normal := pad(box_style(Color(color.r,color.g,color.b,.9) if selected else HIGH,Color.TRANSPARENT,10,0),14,6)
		var hover := pad(box_style(Color(color.r,color.g,color.b,1.0) if selected else Color("#2b3770"),Color.TRANSPARENT,10,0),14,6)
		item.add_theme_stylebox_override("normal",normal)
		item.add_theme_stylebox_override("hover",hover)
		item.add_theme_stylebox_override("pressed",normal)
		var tone := Color("#1a0f05") if selected else MUTED
		for key in ["font_color","font_hover_color","font_pressed_color"]:
			item.add_theme_color_override(key,tone if selected or key != "font_hover_color" else TEXT)
		item.pressed.connect(callback.bind(index))
		bar.add_child(item)
	return bar

static func toggle(parent: Node, value: bool, callback: Callable) -> Button:
	var item := Button.new()
	item.focus_mode = Control.FOCUS_NONE
	item.toggle_mode = true
	item.button_pressed = value
	item.custom_minimum_size = Vector2(scale(58),scale(32))
	item.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	item.text = "SÌ" if value else "NO"
	item.add_theme_font_override("font",body_font(700))
	item.add_theme_font_size_override("font_size",roundi(scale(12)))
	var on := box_style(MINT,Color.TRANSPARENT,99,0)
	var off := box_style(HIGH,Color.TRANSPARENT,99,0)
	var current := on if value else off
	for key in ["normal","hover","pressed"]:
		item.add_theme_stylebox_override(key,current)
	for key in ["font_color","font_hover_color","font_pressed_color"]:
		item.add_theme_color_override(key,Color("#06241a") if value else MUTED)
	item.pressed.connect(func():
		callback.call(not value))
	if parent:
		parent.add_child(item)
	return item

static func format_number(value: int) -> String:
	var text := str(absi(value))
	var out := ""
	for i in text.length():
		if i > 0 and (text.length()-i)%3 == 0:
			out += "."
		out += text[i]
	return ("-" if value < 0 else "")+out
