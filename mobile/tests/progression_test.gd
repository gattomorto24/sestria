extends SceneTree
const Progress = preload("res://scripts/progression.gd")
const Rules = preload("res://scripts/rules.gd")
const Stats = preload("res://scripts/statistics.gd")
const PATH := "res://build/android/progression-unit.json"
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func level_xp(target: int) -> int:
	var result := 0
	for current in range(1,target):
		result += Progress.xp_required(current)
	return result

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for file in [PATH,PATH+".tmp",PATH+".stats",PATH+".stats.tmp"]:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	var progress := Progress.new(PATH)
	check(progress.level()==1 and progress.points()==0,"Nuova saga al livello 1 senza punti gratuiti")
	check(Progress.xp_required(1)==100 and Progress.xp_required(2)==140 and Progress.xp_required(3)==190,"Curva XP progressiva")
	for current in range(2,60):
		check(Progress.xp_required(current)>Progress.xp_required(current-1),"Soglie sempre crescenti")
	var run_data := progress.create_run(0)
	var reward := progress.complete_match("first","solo",true,run_data)
	check(reward.xp==100 and reward.points==2 and progress.level()==2 and progress.xp_in_level()==0,"Vittoria, livello e due punti nello stesso salvataggio")
	progress = Progress.new(PATH)
	check(progress.points()==2 and progress.data.claimed.has("first"),"XP, punti e ricompensa persistenti")
	check(progress.complete_match("first","solo",true,run_data).is_empty() and progress.data.xp==100,"Ricompensa duplicata respinta dopo riavvio")
	check(progress.complete_match("loss","solo",false,run_data).is_empty(),"Nessun XP per sconfitta")
	check(progress.complete_match("lan","lan",true,run_data).is_empty(),"Nessun XP LAN anche con un profilo saga")
	check(progress.complete_match("disabled","solo",true,progress.create_run(2,false)).is_empty(),"Nessun XP per sessione disabilitata")
	check(progress.complete_match("","solo",true,run_data).is_empty(),"Nessun XP senza una partita identificata")
	check(progress.purchase("invalid")==ERR_UNAVAILABLE,"Potenziamento inesistente rifiutato")
	check(progress.purchase("provisions")==OK and progress.points()==0 and progress.rank_of("provisions")==1,"Acquisto e addebito esatti")
	check(progress.purchase("provisions")==ERR_UNAVAILABLE,"Requisito di livello rispettato")
	check(progress.purchase("wisdom")==ERR_UNAVAILABLE,"Saldo insufficiente rispettato")
	progress = Progress.new(PATH)
	check(progress.rank_of("provisions")==1 and progress.points()==0,"Acquisto persistito")
	check(progress.refund()==OK and progress.points()==2 and progress.rank_of("provisions")==0 and progress.data.xp==100,"Riassegnazione gratuita conserva XP e livello")
	progress.data.xp=99
	var big_run := progress.create_run(2)
	big_run.tier=3
	big_run.ranks={"wisdom":3}
	reward=progress.complete_match("multi","solo",true,big_run)
	check(reward.xp==219 and reward.levels==2 and reward.points==4 and progress.xp_in_level()==78,"Più livelli in una vittoria, XP residui e punti completi")
	for milestone in [[1,0,0],[4,1,1],[8,2,2],[12,2,3],[40,2,3]]:
		progress.data.xp=level_xp(milestone[0])
		var profile := progress.create_run(0)
		check(profile.ai_level==milestone[1] and profile.enemy_gold==milestone[2],"Difficoltà progressiva con tetto ai vantaggi del rivale")
		check(profile.trials_extra<=8,"Analisi AI limitata per lo smartphone")
	progress.data.xp=level_xp(30)
	for id in Progress.ORDER:
		while progress.purchase_status(id).is_empty():
			check(progress.purchase(id)==OK,"Acquisto dei gradi disponibili")
		check(progress.rank_of(id)==Progress.UPGRADES[id].costs.size() and progress.purchase(id)==ERR_UNAVAILABLE,"Grado massimo rispettato")
	check(progress.points()>=0 and progress.spent_points()+progress.points()==progress.earned_points(),"Conservazione dei punti")
	progress=Progress.new(PATH)
	var offline := progress.create_run(2)
	var combat := Rules.new()
	combat.reset(0)
	Progress.round_bonuses(combat,offline)
	check(combat.gold==[3,3],"Scorta e vantaggio rivale applicati solo all’avvio")
	Progress.round_bonuses(combat,offline)
	check(combat.gold==[3,3],"Bonus della manche non duplicati")
	combat.round_no=3
	combat.hp[0]=5
	Progress.round_bonuses(combat,offline)
	check(combat.gold==[7,3] and offline.rescue_used,"Offerta e Ultima risorsa limitate ai propri gradi")
	combat.round_no=4
	combat.hp[0]=14
	Progress.round_bonuses(combat,offline)
	check(combat.hp[0]==15 and combat.gold[0]==7,"Cura entro 15 pietre, emergenza non ripetuta")
	combat.round_no=5
	combat.hp[0]=1
	Progress.round_bonuses(combat,offline)
	check(combat.hp[0]==1 and combat.gold[0]==7,"Abilità consumate non si rigenerano ogni manche")
	combat.reset(0)
	combat.round_no=4
	combat.hp[0]=4
	Progress.round_bonuses(combat,progress.create_run(2))
	check(combat.hp[0]==6 and combat.gold[0]==2,"La cura non annulla l’emergenza quando la manche inizia sotto soglia")
	combat.reset(0)
	combat.round_no=4
	combat.hp[0]=0
	combat.winner=1
	Progress.round_bonuses(combat,progress.create_run(2))
	check(combat.hp[0]==0 and combat.gold[0]==0,"Nessun bonus dopo una sconfitta")
	var frozen := progress.create_run(2)
	progress.refund()
	check(frozen.ranks.get("provisions")==3,"Gradi congelati all’avvio della saga")
	var lan_run := progress.create_run(2,false)
	combat.reset(0)
	Progress.round_bonuses(combat,lan_run)
	check(combat.gold==[0,0] and combat.hp==[15,15] and Progress.victory_xp(lan_run)==0,"LAN senza vantaggi né XP")
	# The actual game result path credits only a completed offline match, exactly once.
	var game = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.integration=true
	game.music.stop()
	game.progression=Progress.new(PATH)
	game.stats_store=Stats.new(PATH+".stats")
	game.saga_run=game.progression.create_run(1)
	game.stats_store.start("solo",1)
	var before := int(game.progression.data.xp)
	game.rules.winner=0
	game.rules.hp=[6,0]
	game.integration=false
	game.record_match_result()
	game.record_match_result()
	check(game.progression.data.xp==before+Progress.victory_xp(game.saga_run) and game.stats_store.data.played==1,"Collegamento reale risultato → XP e statistiche, una sola volta")
	game.stats_store.start("lan",1)
	before=int(game.progression.data.xp)
	game.record_match_result()
	check(game.progression.data.xp==before,"Risultato LAN non assegna XP anche con vecchio profilo offline")
	game.progression.data.ranks={"provisions":1}
	game.prepare()
	check(game.saga_run.enabled and game.opponent.level==2 and game.opponent.trials_extra==8,"Preparazione reale applica la difficoltà della saga")
	game.integration=true
	game.toss(0)
	for frame in 5:
		await process_frame
	check(game.rules.gold==[1,3],"Lancio della moneta applica i bonus dopo il reset delle risorse")
	game.stats_store.interrupt()
	game.menu()
	game.queue_free()
	await process_frame
	print("PROGRESSIONE | %d controlli: XP, livelli, punti, acquisti, salvataggi, buff, difficoltà, LAN e risultato reale | errori %d" % [checks,failures])
	quit(1 if failures else 0)
