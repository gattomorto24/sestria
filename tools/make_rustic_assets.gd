extends SceneTree
# Genera la pelle rustica dell'interfaccia (legno di quercia con ferro e rivetti, pergamena, cuoio, ottone, sigillo di ceralacca)
# in assets/ui/rustic/*.png. Uso: godot --headless --path . --script res://tools/make_rustic_assets.gd
const OUT := "res://assets/ui/rustic/"
var wood_noise := FastNoiseLite.new()
var grain_noise := FastNoiseLite.new()
var fine_noise := FastNoiseLite.new()
var stain_noise := FastNoiseLite.new()
var cell_noise := FastNoiseLite.new()

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	wood_noise.seed = 11
	wood_noise.frequency = 0.012
	wood_noise.fractal_octaves = 3
	grain_noise.seed = 23
	grain_noise.frequency = 0.9
	fine_noise.seed = 5
	fine_noise.frequency = 0.7
	stain_noise.seed = 71
	stain_noise.frequency = 0.02
	stain_noise.fractal_octaves = 4
	cell_noise.seed = 3
	cell_noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell_noise.frequency = 0.22
	make_wood_panel("wood_panel",192,192)
	make_wood_panel("wood_bar",256,96)
	make_parchment("parchment",192,192)
	for state in ["normal","hover","pressed","disabled"]:
		make_button("leather_"+state,176,60,"leather",state)
		make_button("brass_"+state,176,60,"brass",state)
		make_tab("tab_"+state,150,54,state)
	make_tab("tab_active",150,54,"active")
	make_seal("seal",112)
	make_groove("xp_groove",256,22)
	make_fill("xp_fill",256,22)
	make_divider("divider",320,20)
	make_wood_plank("plank",128,128)
	print("PELLE RUSTICA | texture generate in ",OUT)
	quit()

# ---- Utilità ----

func mixc(a: Color, b: Color, t: float) -> Color:
	return a.lerp(b,clampf(t,0.0,1.0))

func shade(c: Color, f: float) -> Color:
	return Color(clampf(c.r*f,0,1),clampf(c.g*f,0,1),clampf(c.b*f,0,1),c.a)

func over(base: Color, top: Color) -> Color:
	var a := top.a
	return Color(base.r*(1-a)+top.r*a,base.g*(1-a)+top.g*a,base.b*(1-a)+top.b*a,maxf(base.a,a))

func save(image: Image, name: String) -> void:
	image.save_png(ProjectSettings.globalize_path(OUT+name+".png"))

func rounded_distance(x: float, y: float, w: float, h: float, r: float) -> float:
	# distanza (positiva dentro) dal bordo di un rettangolo arrotondato
	var px := absf(x-w*.5+.5)-(w*.5-r)
	var py := absf(y-h*.5+.5)-(h*.5-r)
	var outside := Vector2(maxf(px,0.0),maxf(py,0.0)).length()
	var inside := minf(maxf(px,py),0.0)
	return r-(outside+inside)

# ---- Legno ----

func oak(x: float, y: float, plank_w := 64.0, light := 1.0) -> Color:
	var plank := floori(x/plank_w)
	var local := fposmod(x,plank_w)
	var shift := hash_float(plank)*400.0
	var long := wood_noise.get_noise_2d(local*1.8+shift,y*0.18+plank*90.0)
	var grain := grain_noise.get_noise_2d(local*1.3+shift,y*0.045+plank*13.0)
	var fine := fine_noise.get_noise_2d(x*0.8,y*0.9)
	var base := mixc(Color("#2a170b"),Color("#6a4424"),.5+long*.55)
	base = shade(base,.88+.2*grain+.05*fine)
	base = shade(base,.9+.2*hash_float(plank+7))
	var seam := smoothstep(2.4,0.0,local)+smoothstep(2.4,0.0,plank_w-local)
	base = shade(base,1.0-seam*.55)
	return shade(base,light)

func hash_float(n: int) -> float:
	return float((n*2654435761)%1000)/1000.0

func make_wood_plank(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			image.set_pixel(x,y,oak(x,y,64.0))
	save(image,name)

func iron(x: float, y: float) -> Color:
	var n := fine_noise.get_noise_2d(x*1.4,y*1.4)
	return shade(Color("#2c2c32"),.9+n*.25)

func rivet(image: Image, cx: float, cy: float, r := 3.4) -> void:
	for y in range(int(cy-r-2),int(cy+r+3)):
		for x in range(int(cx-r-2),int(cx+r+3)):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var d := Vector2(x-cx,y-cy).length()
			if d <= r+1.2:
				var c := Color("#14100c")
				if d <= r:
					var lit := clampf(1.0-Vector2(x-cx+r*.35,y-cy+r*.35).length()/(r*1.3),0,1)
					c = mixc(Color("#4a4a52"),Color("#d2d0c4"),lit)
				image.set_pixel(x,y,c)

func bracket(image: Image, corner: int, size: int, thick: int) -> void:
	var w := image.get_width()
	var h := image.get_height()
	for y in size:
		for x in size:
			if x < thick or y < thick:
				var px := x if corner%2 == 0 else w-1-x
				var py := y if corner < 2 else h-1-y
				var c := iron(px,py)
				# luce sul bordo alto/sinistro
				if x == 0 or y == 0:
					c = shade(c,1.7)
				if x == thick-1 and y < thick or y == thick-1 and x < thick:
					c = shade(c,.55)
				image.set_pixel(px,py,c)
	var offset := 5.0
	var far := float(size)-5.0
	var points := [Vector2(offset,offset),Vector2(far,offset),Vector2(offset,far)]
	for point in points:
		var px: float = point.x if corner%2 == 0 else w-1-point.x
		var py: float = point.y if corner < 2 else h-1-point.y
		rivet(image,px,py)

func make_wood_panel(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := minf(minf(x,y),minf(w-1-x,h-1-y))
			var c := oak(x,y,float(w)/3.0 if w > 200 else 64.0,1.0)
			if d < 9:
				# cornice: legno scuro con smussatura
				c = shade(c,.55)
				var top := y < 9 and y <= x and y <= w-1-x
				var left := x < 9 and x < y and x <= h-1-y
				if top or left:
					c = shade(c,1.25)
				if d < 1:
					c = Color("#120a05")
			elif d < 11:
				c = Color("#150c06")
			else:
				# campo incavato, leggermente più scuro, con ombra interna in alto e a sinistra
				var depth := clampf((d-11.0)/10.0,0,1)
				c = shade(c,.74+.1*depth)
				if d < 15:
					c = shade(c,.78)
			image.set_pixel(x,y,c)
	var size := 34
	for corner in 4:
		bracket(image,corner,size,9)
	save(image,name)

# ---- Pergamena ----

func make_parchment(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var d := minf(minf(x,y),minf(w-1-x,h-1-y))
			var edge_n := stain_noise.get_noise_2d(x*3.2,y*3.2)*7.0+fine_noise.get_noise_2d(x*1.5,y*1.5)*2.0
			var m := d+edge_n
			if m < 1.5:
				image.set_pixel(x,y,Color(0,0,0,0))
				continue
			var stains := stain_noise.get_noise_2d(x,y)
			var fibre := fine_noise.get_noise_2d(x*.5,y*2.2)
			var c := mixc(Color("#d8bd8a"),Color("#f0dcae"),.55+stains*.6)
			c = shade(c,.96+fibre*.06)
			var burn := smoothstep(20.0,2.0,m)
			c = mixc(c,Color("#5a3516"),burn*.78)
			c = mixc(c,Color("#1c0e06"),smoothstep(5.0,1.5,m)*.85)
			c.a = smoothstep(1.5,3.5,m)
			image.set_pixel(x,y,c)
	save(image,name)

# ---- Pulsanti ----

func make_button(name: String, w: int, h: int, kind: String, state: String) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var light: float = {"normal":1.0,"hover":1.16,"pressed":.82,"disabled":.6}[state]
	for y in h:
		for x in w:
			var dist := rounded_distance(x,y,w,h,12.0)
			if dist < 0:
				continue
			var c := Color.BLACK
			if kind == "leather":
				var n := cell_noise.get_noise_2d(x,y)
				c = mixc(Color("#3b2214"),Color("#5e3a22"),.5+n*.5)
				c = shade(c,.92+fine_noise.get_noise_2d(x*1.2,y*1.2)*.2)
				c = shade(c,1.12-float(y)/float(h)*.28)
			else:
				var hammer := cell_noise.get_noise_2d(x*1.3,y*1.3)
				c = mixc(Color("#a8702a"),Color("#f0c460"),.55+hammer*.35-float(y)/float(h)*.55)
			c = shade(c,light)
			if state == "disabled":
				var gray := (c.r+c.g+c.b)/3.0
				c = mixc(c,Color(gray,gray,gray),.7)
			if dist < 3.0:
				c = Color("#150b05") if dist < 1.6 else shade(c,.55)
			elif dist < 5.0:
				var top := y < h*.5
				c = shade(c,1.3 if top else .7)
			if kind == "leather" and dist > 7.0 and dist < 8.6:
				# cucitura tratteggiata
				var along := (x+y)
				if int(along/4.0)%2 == 0 and dist > 7.4 and dist < 8.3:
					c = Color("#c9a56a") if state != "disabled" else Color("#8a7a62")
			if state == "pressed":
				c = shade(c,.92)
			image.set_pixel(x,y,c)
	if kind == "brass":
		rivet(image,10,h*.5,2.6)
		rivet(image,w-11,h*.5,2.6)
	save(image,name)

func make_tab(name: String, w: int, h: int, state: String) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var active := state == "active"
	for y in h:
		for x in w:
			var dist := rounded_distance(x,y,w,h,10.0)
			if dist < 0:
				continue
			var c := oak(x,y,float(w),1.0)
			var light: float = {"normal":.78,"hover":.98,"pressed":.7,"disabled":.5,"active":1.18}[state]
			c = shade(c,light)
			if dist < 2.4:
				c = Color("#150b05")
			elif dist < 4.5:
				c = shade(c,1.25 if y < h*.5 else .6)
			if active:
				if y > h-9:
					c = mixc(c,Color("#e8b44c"),smoothstep(h-9.0,h-3.0,float(y)))
				c = shade(c,1.0+.12*smoothstep(0.0,float(h),float(h-y)))
			image.set_pixel(x,y,c)
	save(image,name)

# ---- Sigillo di ceralacca ----

func make_seal(name: String, s: int) -> void:
	var image := Image.create(s,s,false,Image.FORMAT_RGBA8)
	var center := Vector2(s*.5,s*.5)
	for y in s:
		for x in s:
			var p := Vector2(x,y)-center
			var angle := p.angle()
			var radius := s*.46*(1.0+.07*sin(angle*7.0)+.045*sin(angle*13.0+1.0)+.03*stain_noise.get_noise_2d(x*2.0,y*2.0))
			var d := p.length()
			if d > radius:
				continue
			var lit := clampf(.5-(p.x+p.y)/(s*1.3),0,1)
			var c := mixc(Color("#6e1018"),Color("#c0283a"),.35+lit*.55)
			c = shade(c,.92+stain_noise.get_noise_2d(x*1.5,y*1.5)*.18)
			var edge := radius-d
			if edge < 3.0:
				c = shade(c,.55+edge*.12)
			# anello inciso interno
			var ring := absf(d-s*.31)
			if ring < 1.6:
				c = shade(c,.62)
			elif ring < 2.8 and p.x+p.y < 0:
				c = shade(c,1.25)
			image.set_pixel(x,y,c)
	save(image,name)

# ---- Barra XP ----

func make_groove(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dist := rounded_distance(x,y,w,h,h*.5)
			if dist < 0:
				continue
			var c := shade(oak(x,y,float(w),1.0),.42)
			if dist < 2.0:
				c = Color("#0c0603")
			elif dist < 5.0 and y < h*.5:
				c = shade(c,.55)
			elif dist < 3.5:
				c = shade(c,1.4)
			image.set_pixel(x,y,c)
	save(image,name)

func make_fill(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var dist := rounded_distance(x,y,w,h,h*.5)
			if dist < 0:
				continue
			var t := float(y)/float(h)
			var c := mixc(Color("#ffd27a"),Color("#d9741c"),t)
			c = shade(c,.95+fine_noise.get_noise_2d(x*.6,y*.6)*.12)
			if t < .28:
				c = mixc(c,Color("#fff0b8"),.5)
			if dist < 2.0:
				c = shade(c,.7)
			image.set_pixel(x,y,c)
	save(image,name)

func make_divider(name: String, w: int, h: int) -> void:
	var image := Image.create(w,h,false,Image.FORMAT_RGBA8)
	var mid := h*.5
	for x in w:
		var t := absf(float(x)-w*.5)/(w*.5)
		var alpha := smoothstep(1.0,.2,t)
		for y in range(int(mid)-1,int(mid)+1):
			image.set_pixel(x,y,Color(.12,.07,.03,alpha))
		image.set_pixel(x,int(mid)+1,Color(.85,.62,.3,alpha*.5))
	for y in h:
		for x in w:
			var dx := absf(x-w*.5)
			var dy := absf(y-mid)
			if dx+dy < 7.0:
				var c := mixc(Color("#f0c460"),Color("#9b6a22"),(dx+dy)/7.0)
				if dx+dy > 5.5:
					c = Color("#2a1608")
				image.set_pixel(x,y,c)
	save(image,name)
