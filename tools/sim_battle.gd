extends SceneTree
## Simulador da luta do Sineiro sem cena, com as mesmas regras de BattleRules e EconomyRules e a mesma jogada do --auto.
## Serve para calibrar números com milhares de lutas; o battle.tscn --auto confirma depois.
## godot --headless --path . --script tools/sim_battle.gd -- --n=4000 --hp=900 --timed=0.5 --charge=1 --bag=careful
## --bag: careful (2 Poções e a Pena, o perfil do balanceamento), start (só a bolsa inicial), 0 (sem itens).
const R := preload("res://scripts/battle_rules.gd")
const EC := preload("res://scripts/economy_rules.gd")

var timed_rate := R.AUTO_TIMED
var charge := 1.0
var atk_mult := 1.0       # --atk=: multiplica o ataque do chefe (golpe, badalada e dobre), só para procurar números
var spell_mult := -1.0    # --spell=: multiplica só badalada e dobre (sem ele, --atk vale para tudo)
var rage := R.RAGE_MULT   # --rage=: força do chefe furioso no lugar de R.RAGE_MULT

func _init() -> void:
	var n := 4000
	var hps := [R.SINEIRO.hp]
	var use_bag := "careful"
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=")
		match kv[0]:
			"n": n = int(kv[1])
			"hp": hps = Array(kv[1].split(",")).map(func(x): return int(x))
			"timed": timed_rate = float(kv[1])
			"charge": charge = float(kv[1])
			"bag": use_bag = kv[1]
			"atk": atk_mult = float(kv[1])
			"rage": rage = float(kv[1])
			"spell": spell_mult = float(kv[1])
	for hp in hps:
		var sum := {"win": 0, "rounds": 0.0, "fallen_any": 0, "fallen": 0.0, "taken_pct": 0.0, "taken_win": 0.0, "items": 0.0, "corte": 0.0, "escudo": 0.0}
		for i in n:
			var r := fight(hp, use_bag)
			sum.win += int(r.win)
			sum.rounds += r.rounds
			sum.fallen_any += int(r.fallen > 0)
			sum.taken_win += r.taken_pct if r.win else 0.0
			for k in ["fallen", "taken_pct", "items", "corte", "escudo"]:
				sum[k] += r[k]
		print("spell=%.2f rage=%.2f atk=%.2f hp=%d n=%d win=%.1f%% rounds=%.2f any_fallen=%.0f%% fallen=%.2f taken_pct=%.0f (wins %.0f) items=%.2f corte=%.2f escudo=%.2f" % [
			spell_mult, rage, atk_mult, hp, n, 100.0 * sum.win / n, sum.rounds / n, 100.0 * sum.fallen_any / n, sum.fallen / n, sum.taken_pct / n, sum.taken_win / maxi(1, sum.win),
			sum.items / n, sum.corte / n, sum.escudo / n])
	quit()

func fight(boss_hp: int, use_bag: String) -> Dictionary:
	var p := {}
	var pool := 0
	for id in R.ORDER:
		var hpmax := R.max_stat(id, 4, "hp", {})
		pool += hpmax
		p[id] = {"id": id, "hp": hpmax, "hpmax": hpmax, "mp": R.max_stat(id, 4, "mp", {}), "mpmax": R.max_stat(id, 4, "mp", {}),
			"en": R.ENERGY.start if R.HEROES[id].energy else 0, "defending": false, "atk": R.stat(id, 4, "atk"),
			"mag": R.stat(id, 4, "mag"), "def": R.stat(id, 4, "def"), "res": R.stat(id, 4, "res")}
	var boss := {"hp": boss_hp, "hpmax": boss_hp}
	var st := R.boss_state()
	var bag: Dictionary = {"careful": EC.CAREFUL_BAG, "start": EC.START_BAG}.get(use_bag, {}).duplicate()
	var combo := 0
	var out := {"win": false, "rounds": 0, "fallen": 0, "taken_pct": 0.0, "items": 0, "corte": 0, "escudo": 0, "taken": 0}
	while out.rounds < 60:
		out.rounds += 1
		for id in R.ORDER:
			var h: Dictionary = p[id]
			if h.hp <= 0 or boss.hp <= 0:
				continue
			h.defending = false
			var c := R.auto_choice(id, p, combo, st, bag)
			match c.type:
				"defend":
					h.defending = true
					combo = R.combo_gain(combo, R.combo_points("defend"))
					h.en = R.energy_after(id, h.en, "defend")
				"attack":
					var timed := randf() < timed_rate
					boss.hp -= R.attack_damage(h.atk, R.roll("dmg", randf()), timed)
					h.en = R.energy_after(id, h.en, "attack")
					combo = R.combo_gain(combo, R.combo_points("attack") + (R.combo_points("timed") if timed else 0))
				"item":
					EC.take(bag, c.id)
					EC.apply_item(c.id, p[c.target])
					out.items += 1
				"combo":
					combo -= int(R.COMBOS[c.id].cost)
					out[c.id] += 1
					if c.id == "corte":
						boss.hp -= R.combo_damage(p.aldo.atk, p.andilla.atk, R.SINEIRO.def, R.roll("soft", randf()))
					else:
						for k in R.alive_ids(p):
							p[k].hp = mini(p[k].hpmax, p[k].hp + R.combo_heal(p[k].hpmax))
							p[k].defending = true
				"skill":
					var s: Dictionary = R.SKILLS[c.id]
					combo = R.combo_gain(combo, R.combo_points("skill"))
					if s.cost_kind == "mp":
						h.mp -= s.cost
					else:
						h.en -= s.cost
					if s.kind == "heal":
						var t: Dictionary = p[c.target]
						t.hp = mini(t.hpmax, t.hp + R.heal_amount(s, h.mag, R.roll("soft", randf())))
					else:
						var d := R.skill_damage(s, h.atk, h.mag, R.SINEIRO.def, R.SINEIRO.res, R.SINEIRO.undead, R.roll("dmg", randf()))
						if c.id in ["golpe", "luz"]:
							d = R.charged(d, charge)
						boss.hp -= d
						if s.get("delay", false) and boss.hp > 0:
							R.freeze(st)
		if boss.hp <= 0:
			out.win = true
			break
		var move := R.boss_turn(st, float(boss.hp) / boss.hpmax)
		var alive := R.alive_ids(p)
		var blocked := randf() < timed_rate
		var hurt := func(a: Dictionary, dmg: int) -> int:
			var k := atk_mult if move == "hit" or spell_mult < 0.0 else spell_mult * (rage / R.RAGE_MULT if st.enraged else 1.0)
			dmg = R.taken(roundi(dmg * k), a.defending, blocked)
			a.hp = maxi(0, a.hp - dmg)
			out.taken += dmg     # o lambda copia variáveis soltas; o dicionário é compartilhado
			if a.hp <= 0:
				out.fallen += 1
			else:
				a.en = R.energy_after(a.id, a.en, "hurt")
			return dmg
		match move:
			"bell":
				for id in alive:
					hurt.call(p[id], R.bell_damage(p[id].res, st.enraged, R.roll("soft", randf())))
			"drain":
				var a: Dictionary = p[alive[randi() % alive.size()]]
				var d: int = hurt.call(a, R.drain_damage(a.res, R.roll("soft", randf())))
				boss.hp = mini(boss.hpmax, boss.hp + R.drain_heal(d))
			"hit":
				var a: Dictionary = p[alive[randi() % alive.size()]]
				hurt.call(a, R.boss_hit_damage(a.def, st.enraged, R.roll("dmg", randf())))
		if R.alive_ids(p).is_empty():
			break
	out.taken_pct = 100.0 * out.taken / pool
	return out
