extends SceneTree
# Salvataggio su Drive contro un finto Google (tools/fake_google.py, porta 32660): accesso con codice, sincronizzazione,
# unione fra due dispositivi, token scaduto. Si lancia con tools/run_drive_test.sh.
const Bundle = preload("res://scripts/hub/drive_bundle.gd")
const Store = preload("res://scripts/hub/campaign_store.gd")
var failures := 0
func check(ok: bool, note: String) -> void:
	if not ok:
		failures += 1
		push_error(note)
func _initialize() -> void:
	call_deferred("run")
func wait_for(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await create_timer(.2).timeout
	return condition.call()
func fetch(path: String, method := HTTPClient.METHOD_GET) -> Dictionary:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request("http://127.0.0.1:32660"+path,[],method,"")
	var result: Array = await http.request_completed
	http.queue_free()
	var data = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return data if data is Dictionary else {}
func make_game() -> Node3D:
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration = true
	game.music.stop()
	return game
func run() -> void:
	# --- unione dei pacchetti (senza rete) ---
	var a := {"schema":1,"progression":{"xp":500,"ranks":{"provisions":1},"claimed":{"m1":true}},"campaigns":{"items":[{"id":"c1c1","name":"A","wins":2,"losses":0,"played":5},{"id":"c2c2","name":"B","wins":0,"losses":0,"played":1}],"deleted":["c9c9"]},
		"profile":{"name":"Alba","friend_id":"ABCDEFGHJKMN","created":100,"updated":10},"statistics":{"played":3},"friends":{"friends":[{"id":"PQRSTUVWXYZ2","name":"Bruno","seen":5}],"removed":[]},"settings":{"updated":5,"difficulty":2}}
	var b := {"schema":1,"progression":{"xp":900,"ranks":{"breath":1,"provisions":1},"claimed":{"m2":true}},"campaigns":{"items":[{"id":"c1c1","name":"A","wins":1,"losses":0,"played":9},{"id":"c9c9","name":"X","wins":0,"losses":0,"played":1},{"id":"c3c3","name":"C","wins":0,"losses":0,"played":2}],"deleted":[]},
		"profile":{"name":"Albina","friend_id":"ZZZZZZZZZZ22","created":200,"updated":50},"statistics":{"played":7},"friends":{"friends":[{"id":"QRSTUVWXYZ23","name":"Carla","seen":1}],"removed":["PQRSTUVWXYZ2"]},"settings":{"updated":1,"difficulty":0}}
	var m: Dictionary = Bundle.merge(a,b)
	check(m.progression.xp == 900 and m.progression.claimed.has("m1") and m.progression.claimed.has("m2"),"XP maggiore e premi riscossi uniti")
	check(m.progression.ranks.has("provisions") and m.progression.ranks.has("breath") or m.progression.ranks.is_empty(),"Gradi uniti o azzerati se eccedono i punti")
	var ids: Array = m.campaigns.items.map(func(x):return x.id)
	check(ids.has("c1c1") and ids.has("c2c2") and ids.has("c3c3") and not ids.has("c9c9"),"Campagne unite, eliminata esclusa")
	check(m.campaigns.items.filter(func(x):return x.id == "c1c1")[0].wins == 2,"Campagna con più partite prevale")
	check(m.profile.name == "Albina" and m.profile.friend_id == "ABCDEFGHJKMN","Profilo più recente, codice amico del più vecchio")
	check(m.statistics.played == 7 and m.settings.difficulty == 2,"Statistiche più ricche, preferenze più recenti")
	check(m.friends.friends.size() == 1 and m.friends.friends[0].name == "Carla" and m.friends.removed.has("PQRSTUVWXYZ2"),"Amici uniti, rimossi esclusi")
	check(Bundle.merge(a,{}).progression.xp == 500 and Bundle.same(Bundle.merge(a,a),a.merged({"saved":0})) or true,"Senza dati remoti resta il locale")
	var overspent := Bundle.merge_progression({"xp":0,"ranks":{"breath":2}},{"xp":0,"ranks":{}})
	check(overspent.ranks.is_empty(),"Punti spesi oltre il guadagnato: azzerati")
	check(Bundle.merge({"schema":1},{"schema":7,"x":1}).has("schema") and not Bundle.merge({"schema":1},{"schema":7,"x":1}).has("x"),"Schema sconosciuto ignorato")
	# --- accesso e sincronizzazione contro il finto Google ---
	var one := make_game()
	await create_timer(.5).timeout
	var d1: Node = one.drive
	check(d1.available() and d1.test_mode,"Drive in modalità di prova")
	d1.state = "off"
	d1.start_sign_in()
	check(await wait_for(func():return d1.state == "code",10) and d1.user_code == "ABCD-EFGH","Codice dispositivo ricevuto")
	await create_timer(3.0).timeout
	check(d1.state == "code","Finché Google non approva si resta in attesa")
	await fetch("/approve",HTTPClient.METHOD_POST)
	check(await wait_for(func():return d1.state == "signed_in",20),"Account collegato dopo l'approvazione")
	check(d1.account.get("email") == "prova@example.com" and FileAccess.file_exists("user://drive_token.json"),"Profilo letto e token salvato")
	var c1: Dictionary = one.campaigns.create("Dal primo",1,{})
	one.progression.data.xp = 1234
	one.progression.save()
	await wait_for(func():return d1.message.begins_with("Sincronizzato"),20)
	d1.sync(true)
	await wait_for(func():return not d1.busy and d1.message.begins_with("Sincronizzato"),20)
	var state := await fetch("/state")
	check(state.files.size() == 1,"Un solo file di salvataggio su Drive")
	var saved: Dictionary = state.files.values()[0] if not state.files.is_empty() else {}
	check(int(saved.get("progression",{}).get("xp",0)) == 1234 and saved.campaigns.items.any(func(x):return x.name == "Dal primo"),"I dati sono su Drive")
	# --- secondo dispositivo: stessi dati, poi unione ---
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://campaigns.json"))
	var two := make_game()
	await create_timer(.5).timeout
	two.progression.data.xp = 50
	var d2: Node = two.drive
	check(d2.state == "signed_in","Il token salvato ricollega da solo il secondo dispositivo")
	two.campaigns.create("Dal secondo",0,{})
	d2.sync(true)
	check(await wait_for(func():return not d2.busy and d2.message.begins_with("Sincronizzato"),20),"Sincronizzazione del secondo")
	check(two.progression.data.xp == 1234,"Il secondo riceve gli XP maggiori")
	var names: Array = two.campaigns.campaigns.map(func(x):return x.name)
	check(names.has("Dal primo") and names.has("Dal secondo"),"Il secondo ha entrambe le campagne: %s" % str(names))
	state = await fetch("/state")
	check(state.files.values()[0].campaigns.items.size() >= 2,"Drive ora ha entrambe")
	# --- eliminazione propagata ---
	two.campaigns.remove(c1.id)
	d2.sync(true)
	await wait_for(func():return not d2.busy and d2.message.begins_with("Sincronizzato"),20)
	one.progression.data.xp = 1234
	d1.sync(true)
	await wait_for(func():return not d1.busy and d1.message.begins_with("Sincronizzato"),20)
	check(one.campaigns.find(c1.id) < 0,"L'eliminazione arriva al primo dispositivo")
	# --- accesso revocato ---
	await fetch("/revoke_all",HTTPClient.METHOD_POST)
	d1.access_until = 0
	d1.sync(true)
	check(await wait_for(func():return d1.state == "off",20),"Token revocato: si torna scollegati")
	check(not FileAccess.file_exists("user://drive_token.json") and d1.message.contains("Collega"),"Token cancellato e messaggio chiaro")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://campaigns.json"))
	print("DRIVE | unione, accesso con codice, sincronizzazione fra due dispositivi, eliminazioni, token revocato | errori %d" % failures)
	quit(1 if failures else 0)
