extends RefCounted

const Rules = preload("res://scripts/rules.gd")
var rng := RandomNumberGenerator.new()
var level := 1

func score(match_rules: RefCounted, side: int, mine: Array, enemy: Array) -> float:
	var a := [0,0,0,0,0]
	var b := [0,0,0,0,0]
	var my_gold := 0
	var their_gold := 0
	for d in mine:
		a[d.kind] += 1
		my_gold += int(d.gold)
	for d in enemy:
		b[d.kind] += 1
		their_gold += int(d.gold)
	var other := 1-side
	var pressure := 1.15 + 3.4 / maxf(2.0,match_rules.hp[side])
	var aggression := 1.1 + 3.1 / maxf(2.0,match_rules.hp[other])
	var opposing_gold: int = match_rules.gold[other] + their_gold
	var attack := maxi(0,a[0]-b[2])+maxi(0,a[1]-b[3])
	var hurt := maxi(0,b[0]-a[2])+maxi(0,b[1]-a[3])
	var steal := mini(maxi(0,a[4]-b[4]),opposing_gold)
	var balance := minf(5.0,my_gold+steal)
	var payoff := attack*aggression - hurt*pressure + balance*.94 + steal*.50
	payoff += .12*mini(a[2]+a[3],2) + .15*a[4]
	if attack >= match_rules.hp[other]:
		payoff += 10.0
	if hurt >= match_rules.hp[side]:
		payoff -= 12.0
	return payoff

func keep(match_rules: RefCounted, side: int, landed: Array, last: bool) -> Array:
	var kept: Array = match_rules.board[side]
	var enemy: Array = match_rules.board[1-side]
	if last:
		return landed.map(func(d): return d.id)
	if level == 0:
		return landed.filter(func(d): return rng.randf() < (.75 if d.gold else .43)).map(func(d): return d.id)
	var trials := 8 if level == 1 else 24
	var best := -INF
	var chosen: Array = []
	var futures: Array = []
	for _k in trials:
		var own_samples := []
		var their_samples := enemy.duplicate()
		for d in landed:
			own_samples.append(Rules.die(d.id,rng.randi_range(0,5)))
		var present := their_samples.map(func(d): return d.id)
		for id in 6:
			if id not in present:
				their_samples.append(Rules.die(id,rng.randi_range(0,5)))
		futures.append([own_samples,their_samples])
	for mask in 1 << landed.size():
		var points := 0.0
		for scenario in futures:
			var simulated := kept.duplicate()
			for i in landed.size():
				simulated.append(landed[i] if mask & (1 << i) else scenario[0][i])
			points += score(match_rules,side,simulated,scenario[1])
		points /= trials
		if points > best:
			best = points
			chosen.clear()
			for i in landed.size():
				if mask & (1 << i):
					chosen.append(landed[i].id)
	return chosen

func favor(match_rules: RefCounted, side: int, equipped: Array) -> Dictionary:
	var choices: Array = [{}]
	var sacrifice := mini(3,maxi(0,match_rules.hp[side]-4))
	for id in equipped:
		for lev in 3:
			var data: Array = Rules.FAVOR[id]
			var available: int = match_rules.gold[side]
			if data[1] > 5:
				available += match_rules.marks(side) + match_rules.count(side,Rules.HAND)
			if available >= data[2][lev]:
				var plan := {"id":id,"level":lev,"sacrifice":sacrifice}
				if id == "reroll":
					var their := 1-side
					var targets: Array = match_rules.board[their].duplicate()
					targets.sort_custom(func(a,b): return int(a.gold)*2 + int(a.kind < 2) > int(b.gold)*2 + int(b.kind < 2))
					plan.targets = targets.slice(0,lev+2).map(func(d):return [their,d.id])
				choices.append(plan)
	if level == 0:
		return choices[rng.randi_range(0,choices.size()-1)]
	var scenarios: Array = [{}]
	if level == 2:
		var stock: int = match_rules.gold[1-side] + match_rules.marks(1-side)
		var best_thor := -1
		for lev in 3:
			if stock >= Rules.FAVOR.impact[2][lev]:
				best_thor = lev
		if best_thor >= 0:
			scenarios.append({"id":"impact","level":best_thor})
	var best_value := -INF
	var best: Dictionary = {}
	for plan in choices:
		var sum := 0.0
		for enemy in scenarios:
			var trial = Rules.new()
			trial.hp = match_rules.hp.duplicate()
			trial.gold = match_rules.gold.duplicate()
			trial.board = match_rules.board.duplicate(true)
			trial.first = match_rules.first
			trial.rng.seed = 301
			trial.resolve([plan,enemy] if side == 0 else [enemy,plan])
			sum += (
				trial.hp[side]*1.17-trial.hp[1-side]*1.15
				+.52*trial.gold[side]-.39*trial.gold[1-side]
				+(30.0 if trial.winner == side else (-30.0 if trial.winner == 1-side else 0.0))
			)
		if sum > best_value:
			best_value = sum
			best = plan
	return best
