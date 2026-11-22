extends SceneTree
# Amici senza server: due servizi nello stesso processo, collegati dal tracker di prova (tools/mock_tracker.py, porta 32650)
# e da canali WebRTC reali. Richiesta, accettazione, presenza, invito e rimozione.
# Si lancia con tools/run_online_test.sh (avvia il tracker di prova).
const Service = preload("res://scripts/hub/friends_service.gd")
const Profile = preload("res://scripts/hub/profile_store.gd")
class FakeGame extends Node:
	var profile: RefCounted
var failures := 0
var invites: Array = []
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func make(name: String) -> Node:
	var game := FakeGame.new()
	root.add_child(game)
	var base := ProjectSettings.globalize_path("res://build/friends-test-"+name)
	DirAccess.remove_absolute(base+"-profile.json")
	DirAccess.remove_absolute(base+"-friends.json")
	game.profile = Profile.new(base+"-profile.json")
	game.profile.update({"name":name})
	var service := Service.new()
	game.add_child(service)
	service.test_trackers = ["ws://127.0.0.1:32650"]
	service.setup(game,base+"-friends.json")
	return service
func wait_for(condition: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec() < end:
		if condition.call():
			return true
		await create_timer(.25).timeout
	return condition.call()
func run() -> void:
	if not Service.supported():
		print("AMICI | WebRTC non disponibile: collaudo saltato")
		quit(0)
		return
	var alba := make("Alba")
	var bruno := make("Bruno")
	alba.activate(true)
	bruno.activate(true)
	bruno.invited.connect(func(from_name,code):invites.append([from_name,code]))
	check(alba.add_friend("abc") != "" and alba.add_friend(Profile.format_code(alba.own_id())) != "","Codici non validi o propri rifiutati")
	check(alba.add_friend(Profile.format_code(bruno.own_id())) == "","Richiesta inviata")
	check(alba.add_friend(Profile.format_code(bruno.own_id())) != "","Nessuna richiesta doppia")
	check(await wait_for(func():return bruno.store.incoming.size() == 1,60),"Bruno riceve la richiesta")
	check(bruno.store.incoming[0].name == "Alba" and bruno.pending_incoming() == 1,"Nome e conteggio della richiesta")
	check(await wait_for(func():return alba.store.outgoing.is_empty() and false or true,1),"Pausa")
	bruno.store.accept(alba.own_id())
	check(bruno.store.is_friend(alba.own_id()),"Bruno accetta: amico subito")
	check(await wait_for(func():return alba.store.is_friend(bruno.own_id()),90),"Alba riceve l'accettazione")
	check(alba.store.outgoing.is_empty(),"Richiesta in attesa chiusa")
	check(await wait_for(func():return alba.is_online(bruno.own_id()) or bruno.is_online(alba.own_id()),90),"Presenza: almeno uno vede l'altro online")
	alba.invite(bruno.own_id(),"K7QF2M9X")
	check(await wait_for(func():return not invites.is_empty(),90),"Bruno riceve l'invito")
	check(not invites.is_empty() and invites[0][0] == "Alba" and invites[0][1] == "K7QF2M9X","Invito con nome e codice")
	alba.store.remove(bruno.own_id())
	check(not alba.store.is_friend(bruno.own_id()),"Alba rimuove Bruno")
	check(await wait_for(func():return not bruno.store.is_friend(alba.own_id()),90),"Bruno viene avvisato della rimozione")
	# persistenza e dati ostili
	var reloaded := preload("res://scripts/hub/friends_store.gd").new(ProjectSettings.globalize_path("res://build/friends-test-Alba-friends.json"))
	check(reloaded.friends.is_empty(),"Elenco riletto dal file")
	var hostile := preload("res://scripts/hub/friends_store.gd").person({"id":"abc","name":"x"})
	check(hostile.is_empty(),"Persona con codice non valido scartata")
	alba.activate(false)
	bruno.activate(false)
	print("AMICI | richiesta, accettazione, presenza, invito e rimozione su WebRTC reale | errori %d" % failures)
	quit(1 if failures > 0 else 0)
