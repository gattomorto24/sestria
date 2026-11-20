extends Control
var tint := Color("#d8b47b")
func _ready() -> void:
	mouse_filter=MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
func _draw() -> void:
	var edge := minf(size.x,size.y)*.62
	var origin := (size-Vector2.ONE*edge)*.5
	var frame := StyleBoxFlat.new()
	frame.bg_color=Color.TRANSPARENT
	frame.border_color=Color(tint,.35)
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(int(edge*.18))
	draw_style_box(frame,Rect2(origin,Vector2.ONE*edge))
	for x in [0.32,0.68]:
		for y in [0.24,0.5,0.76]:
			draw_circle(origin+Vector2(x,y)*edge,edge*.055,Color(tint,.7),true,-1,true)
