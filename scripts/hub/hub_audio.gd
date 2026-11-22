extends Node
# Suoni del menu: effetti di legno, cuoio e pergamena e il tema del menu (liuto, bordone e tamburo), tutti sintetizzati
# da tools/make_ui_audio.py. Il tema sostituisce l'ambiente di gioco mentre il menu è aperto.
const NAMES := ["hover","click","back","open","confirm","error","seal","tab"]
var game: Node3D
var streams := {}
var players: Array[AudioStreamPlayer] = []
var cursor := 0
var music: AudioStreamPlayer
var music_tween: Tween
var theme_on := false

func setup(owner_game: Node3D) -> void:
	game = owner_game
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in NAMES:
		streams[name] = load("res://assets/audio/ui/ui_%s.wav" % name)
	for i in 6:
		var player := AudioStreamPlayer.new()
		add_child(player)
		players.append(player)
	music = AudioStreamPlayer.new()
	var song: AudioStreamWAV = load("res://assets/audio/ui/menu_theme.wav")
	song.loop_mode = AudioStreamWAV.LOOP_FORWARD
	song.loop_begin = 0
	song.loop_end = int(song.get_length()*song.mix_rate)-1
	music.stream = song
	music.volume_db = -60.0
	add_child(music)

func play_sfx(name: String) -> void:
	if game == null or game.integration or game.effects_volume <= 0.0 or not streams.has(name):
		return
	var player := players[cursor]
	cursor = (cursor+1)%players.size()
	player.stream = streams[name]
	player.pitch_scale = randf_range(.94,1.07)
	player.volume_db = linear_to_db(maxf(.0001,game.effects_volume*(.45 if name == "hover" else .8)))
	player.play()

func target_db() -> float:
	return linear_to_db(maxf(.0001,game.music_volume*.7))

func start_music() -> void:
	if game == null or game.integration or theme_on:
		return
	theme_on = true
	if game.music:
		game.music.stop()
	if not music.playing:
		music.volume_db = -60.0
		music.play()
	if music_tween:
		music_tween.kill()
	music_tween = create_tween()
	music_tween.tween_property(music,"volume_db",target_db(),1.6)

func stop_music() -> void:
	if not theme_on:
		return
	theme_on = false
	if music_tween:
		music_tween.kill()
	music_tween = create_tween()
	music_tween.tween_property(music,"volume_db",-60.0,.8)
	music_tween.tween_callback(music.stop)
	if game and game.music and not game.integration and not game.music.playing:
		game.music.play()

func refresh_volume() -> void:
	if theme_on and music:
		music.volume_db = target_db()
