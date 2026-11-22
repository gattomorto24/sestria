extends SceneTree
# Passa e gioca: due persone controllano i due lati. La partita si gioca fino in fondo con scelte automatiche per entrambi.
var game: Node3D
var failures := 0
var handoffs := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	for i in 5:
		await process_frame
	game.start_hotseat("Alba","Bruno")
	check(game.hotseat and game.player_names == ["Alba","Bruno"],"Nomi dei due giocatori")
	check(not game.saga_run.get("enabled",true),"Nessun XP nel Passa e gioca")
	check(game.bot_loadout == game.equipped,"Stesse tattiche per entrambi")
	game.toss(0)
	var acted := {0:0,1:0}
	var guard := 0
	while game.phase != "end" and guard < 60000:
		guard += 1
		await process_frame
		match game.phase:
			"roll":
				acted[game.acting] += 1
				game.roll()
			"select":
				await game.get_tree().physics_frame
				var pick: Array = game.opponent.keep(game.rules,game.acting,game.pending,false)
				for id in pick:
					var cube: Node3D = game.cubes[game.acting][id]
					game.interact_at(game.camera.unproject_position(cube.global_position),false)
				game.confirm_selection()
			"favor":
				game.resolve(game.opponent.favor(game.rules,game.acting,game.equipped))
			"handoff":
				handoffs += 1
				var buttons: Array = game.ui.dialog.find_children("*","Button",true,false)
				check(not buttons.is_empty(),"La schermata di passaggio ha il pulsante")
				if not buttons.is_empty():
					buttons[0].pressed.emit()
			"between":
				game.next_round()
	check(game.phase == "end" and game.rules.winner >= 0,"La partita finisce con un vincitore")
	check(acted[0] > 0 and acted[1] > 0,"Entrambi i giocatori hanno lanciato: %s" % str(acted))
	check(handoffs >= game.rules.round_no,"Un passaggio del dispositivo per ogni manche: %d su %d" % [handoffs,game.rules.round_no])
	check(is_instance_valid(game.ui.dialog),"Schermata finale aperta")
	game.menu()
	check(not game.hotseat,"Tornando al menu il Passa e gioca finisce")
	print("PASSA E GIOCA | manche %d | vincitore %s | passaggi %d | errori %d" % [game.rules.round_no,game.player_names[game.rules.winner] if game.hotseat else "-",handoffs,failures])
	quit(1 if failures > 0 else 0)
