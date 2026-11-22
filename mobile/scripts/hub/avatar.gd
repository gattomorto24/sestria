extends Control
# Icona del giocatore: cerchio con sfumatura, anello e un emblema disegnato a mano (12 emblemi, 8 colori).
const COLORS := [
	[Color("#e8a64a"),Color("#8a4a1c")],[Color("#6fa6b8"),Color("#2c5468")],[Color("#8fb86a"),Color("#3f6330")],[Color("#c4485a"),Color("#6a1c2a")],
	[Color("#a58ac8"),Color("#4a3470")],[Color("#d8c27a"),Color("#7a6020")],[Color("#a0a0aa"),Color("#44444c")],[Color("#c88a6a"),Color("#6a3a24")]]
const EMBLEM_NAMES := ["Dado","Esagono","Fiamma","Fulmine","Corona","Ascia","Scudo","Freccia","Stella","Luna","Occhio","Sole"]
var emblem := 0
var color_index := 0
var ring := true
var badge := ""

func configure(new_emblem: int, new_color: int, show_ring := true) -> void:
	emblem = posmod(new_emblem,EMBLEM_NAMES.size())
	color_index = posmod(new_color,COLORS.size())
	ring = show_ring
	queue_redraw()

func _init(side := 56.0) -> void:
	custom_minimum_size = Vector2(side,side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

static func poly(points: Array, center: Vector2, radius: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for point in points:
		result.append(center+Vector2(point[0],point[1])*radius)
	return result

func _draw() -> void:
	var side := minf(size.x,size.y)
	var center := size*.5
	var radius := side*.5-1.0
	var pair: Array = COLORS[color_index]
	# sfondo: due cerchi sovrapposti per simulare la sfumatura
	draw_circle(center,radius,pair[1])
	draw_circle(center-Vector2(0,radius*.08),radius*.94,pair[1].lerp(pair[0],.35))
	draw_circle(center-Vector2(0,radius*.22),radius*.66,pair[1].lerp(pair[0],.55))
	if ring:
		# anello di ferro con filo d'ottone e otto rivetti
		var thick := maxf(2.5,side*.075)
		draw_arc(center,radius-thick*.5,0,TAU,64,Color("#26262b"),thick,true)
		draw_arc(center,radius-thick*.5,PI*1.05,PI*1.75,24,Color("#8c8c94"),maxf(1.0,thick*.35),true)
		draw_arc(center,radius-thick-.5,0,TAU,64,Color("#c8923a"),maxf(1.0,side*.02),true)
		for i in 8:
			draw_circle(center+Vector2.from_angle(TAU*i/8.0)*(radius-thick*.5),maxf(1.0,thick*.22),Color("#c9c9d0"))
	var ink := Color("#10142e")
	var light := Color(1,1,1,.96)
	var e := radius*.56
	match emblem:
		0:
			var d := e*.62
			for p in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,0),Vector2(1,0),Vector2(-1,1),Vector2(1,1)]:
				draw_circle(center+Vector2(p.x*d*.78,p.y*d*.92),e*.2,light)
		1:
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(center+Vector2.from_angle(TAU*i/6.0-PI/2)*e)
			draw_colored_polygon(hex,light)
			var inner := PackedVector2Array()
			for i in 6:
				inner.append(center+Vector2.from_angle(TAU*i/6.0-PI/2)*e*.5)
			draw_colored_polygon(inner,pair[1])
		2:
			draw_colored_polygon(poly([[0,-1],[.55,-.35],[.7,.35],[.35,.95],[-.35,.95],[-.7,.3],[-.5,-.35],[-.15,-.1]],center,e),light)
			draw_colored_polygon(poly([[0,.1],[.28,.5],[.15,.9],[-.15,.9],[-.28,.5]],center,e),pair[0])
		3:
			draw_colored_polygon(poly([[.1,-1],[-.65,.15],[-.05,.15],[-.2,1],[.7,-.25],[.05,-.25]],center,e),light)
		4:
			draw_colored_polygon(poly([[-.9,.75],[-.9,-.55],[-.45,-.05],[0,-.8],[.45,-.05],[.9,-.55],[.9,.75]],center,e),light)
			draw_rect(Rect2(center.x-e*.9,center.y+e*.5,e*1.8,e*.2),pair[1])
		5:
			draw_colored_polygon(poly([[-.08,-1],[-.08,1],[.08,1],[.08,-1]],center,e),light)
			draw_colored_polygon(poly([[.08,-.9],[.85,-.55],[.85,.15],[.08,.05]],center,e),light)
		6:
			draw_colored_polygon(poly([[-.8,-.8],[0,-1],[.8,-.8],[.8,.1],[0,1],[-.8,.1]],center,e),light)
			draw_colored_polygon(poly([[0,-.7],[.5,-.55],[.5,0],[0,.65],[-.5,0],[-.5,-.55]],center,e),pair[1])
		7:
			draw_colored_polygon(poly([[0,-1],[.65,-.2],[.2,-.2],[.2,1],[-.2,1],[-.2,-.2],[-.65,-.2]],center,e),light)
		8:
			var star := PackedVector2Array()
			for i in 10:
				var r := e if i%2 == 0 else e*.45
				star.append(center+Vector2.from_angle(TAU*i/10.0-PI/2)*r)
			draw_colored_polygon(star,light)
		9:
			draw_circle(center,e,light)
			draw_circle(center+Vector2(e*.45,-e*.15),e*.82,pair[1].lerp(pair[0],.45))
		10:
			draw_colored_polygon(poly([[-1,0],[-.5,-.5],[0,-.65],[.5,-.5],[1,0],[.5,.5],[0,.65],[-.5,.5]],center,e),light)
			draw_circle(center,e*.34,pair[1])
			draw_circle(center,e*.15,light)
		11:
			draw_circle(center,e*.5,light)
			for i in 8:
				var direction := Vector2.from_angle(TAU*i/8.0)
				draw_line(center+direction*e*.72,center+direction*e*1.0,light,maxf(2.0,e*.14),true)
	if not badge.is_empty():
		var font := ThemeDB.fallback_font
		var box := Rect2(size.x-side*.46,size.y-side*.3,side*.46,side*.3)
		draw_rect(box,Color("#0b1030"),true)
		draw_string(font,box.position+Vector2(4,box.size.y*.74),badge,HORIZONTAL_ALIGNMENT_LEFT,box.size.x-4,int(side*.2),Color.WHITE)
