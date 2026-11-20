extends SceneTree
const Stats = preload("res://scripts/statistics.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures+=1
		push_error(message)
func _initialize() -> void:
	var path := "res://build/android/statistics-unit.json"
	for file in [path,path+".tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	var stats=Stats.new(path)
	stats.start("solo",1)
	stats.tick(73)
	stats.rolled()
	stats.kept(4)
	var events := [{"kind":"hit","side":1,"amount":3},{"kind":"hit","side":0,"amount":2},{"kind":"block","side":0,"amount":2},{"kind":"favor","side":0,"amount":4,"extra":{"id":"impact"}},{"kind":"token","side":0,"amount":1,"extra":{"hand":true}}]
	stats.events(1,events)
	stats.events(1,events)
	stats.finish(true,[8,0])
	stats.finish(true,[8,0])
	var restored=Stats.new(path)
	check(restored.data.played==1 and restored.data.wins==1,"Risultato persistito una sola volta")
	check(restored.data.damage_dealt==3 and restored.data.damage_taken==2,"Danni dalla prospettiva locale")
	check(restored.data.rounds==1 and restored.data.tokens_stolen==1,"Eventi duplicati ignorati")
	check(restored.data.favors.impact==1 and restored.data.seconds==73,"Favori e durata salvati")
	restored.start("lan",0)
	restored.interrupt()
	restored.start("lan",0)
	restored.finish(false,[0,6])
	var latest=Stats.new(path)
	check(latest.data.played==2 and latest.data.losses==1 and latest.data.abandoned==1,"Interruzioni separate dai risultati")
	check(latest.win_rate()==50 and latest.data.best_streak==1 and latest.data.streak==0,"Percentuale e serie corrette")
	latest.start("solo",2)
	var crashed=Stats.new(path)
	check(crashed.data.abandoned==2,"Chiusura del processo recuperata senza falsa sconfitta")
	print("STATISTICHE | persistenza, doppioni, eventi, abbandoni e recupero | errori %d" % failures)
	quit(1 if failures else 0)
