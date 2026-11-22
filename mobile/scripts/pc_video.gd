extends RefCounted
# Impostazioni video per i computer (Windows e Mac): finestra, risoluzione, V-Sync, FPS, qualità grafica,
# anti-aliasing e upscaling FSR. Tutto è un Dictionary salvato nella sezione "pc" di user://sestria.cfg,
# così il pacchetto contenuti lo aggiorna senza toccare project.godot.
const SECTION := "pc"
const WINDOW_MODES := ["window","borderless","exclusive"]
const WINDOW_NAMES := {"window":"Finestra","borderless":"Schermo intero senza bordi","exclusive":"Schermo intero esclusivo"}
const VSYNC_MODES := ["off","on","adaptive","mailbox"]
const VSYNC_NAMES := {"off":"Disattivato","on":"Attivo","adaptive":"Adattivo","mailbox":"Triplo buffer"}
const FPS_CAPS := [0,30,60,90,120,144,165,240]
const MSAA_LEVELS := [0,2,4,8]
const AA_MODES := ["none","fxaa","taa"]
const AA_NAMES := {"none":"Nessuno","fxaa":"FXAA","taa":"TAA"}
const SCALING_MODES := ["native","bilinear","fsr1","fsr2"]
const SCALING_NAMES := {"native":"Nativo","bilinear":"Bilineare","fsr1":"FSR 1.0","fsr2":"FSR 2.2"}
const SSAO_LEVELS := ["off","low","medium","high"]
const SHADOW_LEVELS := ["off","low","medium","high"]
const LEVEL_NAMES := {"off":"Disattivate","low":"Basse","medium":"Medie","high":"Alte"}
const ANISO_LEVELS := [0,2,4,8,16]
const PRESETS := ["bassa","media","alta","ultra"]
const PRESET_NAMES := {"bassa":"Bassa","media":"Media","alta":"Alta","ultra":"Ultra","custom":"Personalizzata"}
const RESOLUTIONS := [Vector2i(1280,720),Vector2i(1366,768),Vector2i(1440,900),Vector2i(1600,900),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3440,1440),Vector2i(3840,2160)]
# Qualità FSR: percentuale di rendering rispetto alla finestra.
const FSR_QUALITY := {"ultra_quality":.77,"quality":.67,"balanced":.59,"performance":.50}
const FSR_NAMES := {"ultra_quality":"Qualità massima","quality":"Qualità","balanced":"Bilanciata","performance":"Prestazioni"}

static func defaults() -> Dictionary:
	var settings := preset("alta")
	settings.merge({"window_mode":"window","resolution":"1280x800","monitor":0,"vsync":"on","fps_cap":0,"ui_scale":1.0,"preset":"alta","fps_counter":false},true)
	return settings

# Parametri grafici di ogni livello. "alta" corrisponde all'aspetto di sempre; "bassa" alla vecchia "modalità prestazioni".
static func preset(name: String) -> Dictionary:
	match name:
		"bassa":
			return {"msaa":2,"aa":"none","scaling":"bilinear","render_scale":.89,"fsr_quality":"quality","sharpness":.2,"ssao":"off","glow":false,"shadows":"off","soft_shadows":false,"fog":false,"aniso":2,"particles":"low"}
		"media":
			return {"msaa":2,"aa":"fxaa","scaling":"native","render_scale":1.0,"fsr_quality":"quality","sharpness":.2,"ssao":"low","glow":true,"shadows":"low","soft_shadows":false,"fog":true,"aniso":4,"particles":"high"}
		"ultra":
			return {"msaa":8,"aa":"none","scaling":"native","render_scale":1.0,"fsr_quality":"quality","sharpness":.2,"ssao":"high","glow":true,"shadows":"high","soft_shadows":true,"fog":true,"aniso":16,"particles":"high"}
	return {"msaa":4,"aa":"none","scaling":"native","render_scale":1.0,"fsr_quality":"quality","sharpness":.2,"ssao":"medium","glow":true,"shadows":"medium","soft_shadows":true,"fog":true,"aniso":8,"particles":"high"}

static func resolution_text(size: Vector2i) -> String:
	return "%dx%d" % [size.x,size.y]

static func parse_resolution(text: Variant) -> Vector2i:
	var parts := str(text).split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var size := Vector2i(int(parts[0]),int(parts[1]))
	return size if size.x >= 640 and size.y >= 360 and size.x <= 16384 and size.y <= 16384 else Vector2i.ZERO

# Risoluzioni proposte per lo schermo indicato (solo quelle che ci stanno) più la risoluzione nativa.
static func resolution_options(screen: Vector2i) -> Array:
	var result: Array = []
	for size in RESOLUTIONS:
		if size.x <= screen.x and size.y <= screen.y:
			result.append(size)
	if screen.x >= 640 and screen.y >= 360 and not result.has(screen):
		result.append(screen)
	return result

static func clean(raw: Dictionary) -> Dictionary:
	var out := defaults()
	var base := out.duplicate()
	for key in base:
		if raw.has(key) and typeof(raw[key]) == typeof(base[key]):
			out[key] = raw[key]
		elif raw.has(key) and base[key] is float and raw[key] is int:
			out[key] = float(raw[key])
	out.window_mode = out.window_mode if WINDOW_MODES.has(out.window_mode) else "window"
	out.vsync = out.vsync if VSYNC_MODES.has(out.vsync) else "on"
	out.fps_cap = out.fps_cap if FPS_CAPS.has(out.fps_cap) else 0
	out.msaa = out.msaa if MSAA_LEVELS.has(out.msaa) else 4
	out.aa = out.aa if AA_MODES.has(out.aa) else "none"
	out.scaling = out.scaling if SCALING_MODES.has(out.scaling) else "native"
	out.fsr_quality = out.fsr_quality if FSR_QUALITY.has(out.fsr_quality) else "quality"
	out.ssao = out.ssao if SSAO_LEVELS.has(out.ssao) else "medium"
	out.shadows = out.shadows if SHADOW_LEVELS.has(out.shadows) else "medium"
	out.aniso = out.aniso if ANISO_LEVELS.has(out.aniso) else 8
	out.particles = out.particles if out.particles in ["low","high"] else "high"
	out.preset = out.preset if PRESETS.has(out.preset) or out.preset == "custom" else "custom"
	out.ui_scale = clampf(out.ui_scale,.75,1.5)
	out.render_scale = clampf(out.render_scale,.5,1.0)
	out.sharpness = clampf(out.sharpness,0.0,2.0)
	out.monitor = maxi(0,out.monitor)
	if parse_resolution(out.resolution) == Vector2i.ZERO:
		out.resolution = "1280x800"
	return out

# Combinazioni che il motore non regge: FSR 2 e TAA non convivono con MSAA, FXAA/TAA non servono a MSAA alto, ecc.
static func normalized(settings: Dictionary) -> Dictionary:
	var out := settings.duplicate()
	if out.scaling == "fsr2" or out.aa == "taa":
		out.msaa = 0
	return out

# Livello rilevato: se le opzioni coincidono con un livello è quello, altrimenti "custom".
static func detect_preset(settings: Dictionary) -> String:
	for name in PRESETS:
		var wanted := preset(name)
		var same := true
		for key in wanted:
			if settings.get(key) != wanted[key]:
				same = false
				break
		if same:
			return name
	return "custom"

static func with_preset(settings: Dictionary, name: String) -> Dictionary:
	var out := settings.duplicate()
	out.merge(preset(name),true)
	out.preset = name
	return out

static func load_from(config: ConfigFile) -> Dictionary:
	var raw := {}
	if config.has_section(SECTION):
		for key in config.get_section_keys(SECTION):
			raw[key] = config.get_value(SECTION,key)
	return clean(raw)

static func save_to(config: ConfigFile, settings: Dictionary) -> void:
	for key in settings:
		config.set_value(SECTION,key,settings[key])

static func is_nvidia() -> bool:
	return "nvidia" in RenderingServer.get_video_adapter_vendor().to_lower() or "nvidia" in RenderingServer.get_video_adapter_name().to_lower()

static func gpu_text() -> String:
	var name := RenderingServer.get_video_adapter_name()
	return name if not name.is_empty() else "Scheda grafica non rilevata"

static func upscaling_available() -> bool:
	return ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method") == "forward_plus"

static func level_value(level: String, values: Array) -> Variant:
	var index := ["off","low","medium","high"].find(level)
	return values[clampi(index,0,values.size()-1)]

# ---- Applicazione ----

static func apply_display(settings: Dictionary, window: Window) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := clampi(settings.monitor,0,DisplayServer.get_screen_count()-1)
	if DisplayServer.window_get_current_screen(window.get_window_id()) != screen:
		DisplayServer.window_set_current_screen(screen,window.get_window_id())
	var vsync := {"off":DisplayServer.VSYNC_DISABLED,"on":DisplayServer.VSYNC_ENABLED,"adaptive":DisplayServer.VSYNC_ADAPTIVE,"mailbox":DisplayServer.VSYNC_MAILBOX}
	DisplayServer.window_set_vsync_mode(vsync[settings.vsync],window.get_window_id())
	Engine.max_fps = settings.fps_cap
	window.content_scale_factor = settings.ui_scale
	match settings.window_mode:
		"window":
			window.mode = Window.MODE_WINDOWED
			if window.borderless:
				window.borderless = false
			# Dopo lo schermo intero il sistema ha bisogno di qualche fotogramma prima di accettare dimensione e posizione.
			for i in 3:
				await window.get_tree().process_frame
			var size := parse_resolution(settings.resolution)
			var usable := DisplayServer.screen_get_usable_rect(screen)
			if usable.size.x < 640 or usable.size.y < 360:
				usable = Rect2i(DisplayServer.screen_get_position(screen),DisplayServer.screen_get_size(screen))
			size = Vector2i(maxi(640,mini(size.x,usable.size.x)),maxi(360,mini(size.y,usable.size.y)))
			window.size = size
			window.position = usable.position+(usable.size-size)/2
		"borderless":
			window.mode = Window.MODE_FULLSCREEN
		"exclusive":
			window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN

# Applica la grafica a viewport e ambiente. `table` è la scena del tavolo (ambiente e luci).
static func apply_graphics(settings: Dictionary, viewport: Viewport, table: Node) -> void:
	var s := normalized(settings)
	var forward := upscaling_available()
	viewport.msaa_3d = {0:Viewport.MSAA_DISABLED,2:Viewport.MSAA_2X,4:Viewport.MSAA_4X,8:Viewport.MSAA_8X}[s.msaa]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if s.aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
	# FSR 2 ha già il suo anti-aliasing temporale: con lui il TAA del motore va spento.
	viewport.use_taa = forward and s.aa == "taa" and s.scaling != "fsr2"
	viewport.anisotropic_filtering_level = {0:Viewport.ANISOTROPY_DISABLED,2:Viewport.ANISOTROPY_2X,4:Viewport.ANISOTROPY_4X,8:Viewport.ANISOTROPY_8X,16:Viewport.ANISOTROPY_16X}[s.aniso]
	var mode: String = s.scaling
	if not forward and mode in ["fsr1","fsr2"]:
		mode = "bilinear"
	match mode:
		"fsr1":
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
			viewport.scaling_3d_scale = FSR_QUALITY[s.fsr_quality]
		"fsr2":
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
			viewport.scaling_3d_scale = FSR_QUALITY[s.fsr_quality]
		"bilinear":
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = s.render_scale
		_:
			viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			viewport.scaling_3d_scale = 1.0
	viewport.fsr_sharpness = s.sharpness
	if table != null and table.get("env") != null:
		table.apply_pc_graphics(s,forward)

static func apply_all(settings: Dictionary, window: Window, table: Node) -> void:
	apply_display(settings,window)
	apply_graphics(settings,window,table)
