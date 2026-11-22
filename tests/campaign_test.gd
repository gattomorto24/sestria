extends SceneTree
# Collaudo delle campagne: salvataggio, impostazioni, capitoli, moltiplicatore XP e applicazione alla partita.
const Store = preload("res://scripts/hub/campaign_store.gd")
const Profile = preload("res://scripts/hub/profile_store.gd")
var failures := 0
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var path := ProjectSettings.globalize_path("res://build/campaign-test.json")
	DirAccess.remove_absolute(path)
	var store := Store.new(path)
	check(store.campaigns.is_empty(),"Nessuna campagna all'inizio")
	check(Store.SETTINGS.size() == 10,"Dieci impostazioni")
	var defaults := Store.default_settings()
	check(defaults.size() == 10 and defaults.throws == 3 and defaults.first == "coin","Valori predefiniti")
	var dirty := Store.clean_settings({"throws":9,"first":"mago","hints":"si","bot_tokens":4,"speed":"fast","extra":1})
	check(dirty.throws == 3 and dirty.first == "coin" and dirty.hints == false and dirty.bot_tokens == -1 and dirty.speed == "fast" and not dirty.has("extra"),"Valori non validi ripuliti")
	var item := store.create("  La via\u0001 del bosco  ",2,{"first":"bot","throws":2,"hints":true,"bot_style":"aggressive","fixed_seed":true})
	check(not item.is_empty() and item.name == "La via del bosco" and item.difficulty == 2 and item.chapter == 1,"Creazione e nome ripulito")
	check(Store.new(path).campaigns.size() == 1 and Store.new(path).campaigns[0].settings.first == "bot","Salvataggio e lettura")
	check(Store.clean_name("") == "Campagna" and Store.clean_name("x".repeat(80)).length() == 24,"Nomi vuoti o lunghi")
	# capitoli
	check(Store.tier_for(1) == 0 and Store.tier_for(3) == 0 and Store.tier_for(4) == 1 and Store.tier_for(10) == 3 and Store.tier_for(99) == 3,"Livello del bot per capitolo")
	var setup := Store.match_setup(item)
	check(setup.ai_level == 2 and setup.throws == 2 and setup.first == "bot" and setup.enemy_gold == 0 and setup.seed > 0,"Parametri della partita")
	check(Store.match_setup(Store.sanitize({"id":"abcd1234","difficulty":0,"chapter":8})).enemy_gold == 2,"Gettoni automatici del bot secondo il livello")
	# moltiplicatore
	check(is_equal_approx(Store.xp_multiplier(defaults),1.0),"Moltiplicatore base")
	check(Store.xp_multiplier(item.settings) > 1.05 and Store.xp_multiplier(Store.clean_settings({"hints":true,"player_tokens":3})) < .8,"Più difficile rende di più, i suggerimenti meno")
	check(Store.xp_multiplier({"throws":2,"bot_tokens":5,"bot_style":"aggressive","first":"bot"}) <= 1.6,"Moltiplicatore limitato")
	# esito
	var result := store.record(item.id,true,130)
	check(result.promoted and result.chapter == 2 and store.campaigns[0].wins == 1 and store.campaigns[0].streak == 1 and store.campaigns[0].xp == 130,"Vittoria: capitolo, serie e XP")
	store.record(item.id,false,0)
	check(store.campaigns[0].chapter == 2 and store.campaigns[0].streak == 0 and store.campaigns[0].losses == 1 and store.campaigns[0].best_streak == 1,"Sconfitta: capitolo invariato, serie azzerata")
	store.rename(item.id,"Nuova rotta")
	check(Store.new(path).campaigns[0].name == "Nuova rotta","Rinomina")
	for i in 14:
		store.create("C%d" % i,1,{})
	check(store.campaigns.size() == Store.MAX_CAMPAIGNS,"Massimo di campagne")
	store.remove(item.id)
	check(store.find(item.id) < 0,"Eliminazione")
	check(Store.sanitize("x").is_empty() and Store.sanitize({"id":"ab"}).is_empty(),"Dati ostili scartati")
	# profilo
	var profile_path := ProjectSettings.globalize_path("res://build/profile-test.json")
	DirAccess.remove_absolute(profile_path)
	var profile := Profile.new(profile_path)
	check(Profile.valid_id(profile.data.friend_id) and Profile.parse_code(profile.code()) == profile.data.friend_id,"Codice amico generato e riletto")
	check(Profile.parse_code("abc") == "" and Profile.parse_code("0000-0000-0000") == "","Codici amico non validi")
	profile.update({"name":"A","emblem":99,"color":-3,"banner":50,"title":"legend"})
	check(profile.data.name == "Giocatore" and profile.data.emblem == 11 and profile.data.color == 0 and profile.data.banner == Profile.BANNERS.size()-1,"Profilo ripulito")
	check(Profile.new(profile_path).data.friend_id == profile.data.friend_id,"Il codice amico resta")
	check(profile.title_name(1) == "Novizio" and Profile.unlocked_titles(5).size() == 3,"Titoli sbloccati per livello")
	# applicazione alla partita
	var game: Node3D = load("res://scenes/table.tscn").instantiate()
	root.add_child(game)
	game.music.stop()
	for i in 4:
		await process_frame
	game.integration = false
	game.campaigns = Store.new(ProjectSettings.globalize_path("res://build/campaign-test2.json"))
	var campaign: Dictionary = game.campaigns.create("Prova",2,{"throws":2,"first":"player","speed":"fast","log":"brief","hints":true,"bot_style":"cautious","bot_tactics":"mirror","player_tokens":2,"bot_tokens":3,"fixed_seed":true})
	game.active_campaign = campaign.id
	game.match_setup = Store.match_setup(campaign)
	game.saga_run = game.progression.create_run(2)
	game.apply_match_setup()
	check(game.max_throws == 2 and game.speed_factor == .6 and not game.log_detail and game.hints_on and game.forced_first == 0,"Impostazioni applicate alla partita")
	check(game.saga_run.enemy_gold == 3 and game.saga_run.player_gold == 2 and is_equal_approx(game.saga_run.xp_multiplier,Store.xp_multiplier(campaign.settings)),"Gettoni e premio XP nella partita")
	check(game.opponent.aggression_bias < 1.0 and game.opponent.pressure_bias > 1.0,"Stile prudente del bot")
	game.saga_difficulty = 1
	check(game.pick_bot_loadout() == game.equipped,"Tattiche del bot come le tue")
	game.match_setup.tactics = "random"
	var one: Array = game.pick_bot_loadout()
	var two: Array = game.pick_bot_loadout()
	check(one.size() == 3 and one == two,"Tattiche casuali ma ripetibili con il seme")
	var run: Dictionary = game.saga_run
	run.enabled = true
	check(game.progression.victory_xp(run) == roundi(float(game.progression.victory_xp({"enabled":true,"difficulty":2,"tier":int(run.tier)}))*float(run.xp_multiplier)),"Premio XP moltiplicato")
	game.active_campaign = ""
	game.match_setup = {}
	game.apply_match_setup()
	check(game.max_throws == 3 and game.speed_factor == 1.0 and game.log_detail and not game.hints_on and game.forced_first == -1,"Partita al volo: valori di sempre")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(profile_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("res://build/campaign-test2.json"))
	print("CAMPAGNE | salvataggi, dieci impostazioni, capitoli, XP, profilo e applicazione alla partita | errori %d" % failures)
	quit(1 if failures > 0 else 0)
