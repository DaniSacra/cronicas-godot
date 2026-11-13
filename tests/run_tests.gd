extends SceneTree
## Testes de lógica pura. Rodar: godot --headless --path . --script tests/run_tests.gd
const C := preload("res://scripts/controls.gd")
const R := preload("res://scripts/battle_rules.gd")
const U := preload("res://scripts/ui.gd")
const F := preload("res://scripts/fx.gd")
const D := preload("res://scripts/dialogue_rules.gd")
const EC := preload("res://scripts/economy_rules.gd")
const AU := preload("res://scripts/audio_rules.gd")
const SV := preload("res://scripts/save_rules.gd")
const VR := preload("res://scripts/valmor_rules.gd")
var fails := 0

func check(name: String, cond: bool) -> void:
	print(("ok   " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _init() -> void:
	check("combine picks the stronger vector", C.combine(Vector2(0.2, 0), Vector2(0, -0.9)) == Vector2(0, -0.9))
	check("combine never exceeds length 1", C.combine(Vector2(3, 4), Vector2.ZERO).length() <= 1.0001)
	check("combine of two zeros is zero", C.combine(Vector2.ZERO, Vector2.ZERO) == Vector2.ZERO)
	check("stick inside dead zone is zero", C.stick_vector(Vector2(50, 50), Vector2(52, 51), 46.0) == Vector2.ZERO)
	check("stick at the rim is a unit vector", C.stick_vector(Vector2.ZERO, Vector2(46, 0), 46.0).is_equal_approx(Vector2(1, 0)))
	check("stick beyond the rim is clamped", C.stick_vector(Vector2.ZERO, Vector2(0, 400), 46.0).is_equal_approx(Vector2(0, 1)))
	check("stick half way is half strength", absf(C.stick_vector(Vector2.ZERO, Vector2(-23, 0), 46.0).x + 0.5) < 0.001)
	# regras da batalha (portadas de src/party.js)
	check("hero stat follows base + grow x (lv-1)", R.stat("aldo", 5, "atk") == 25 and R.stat("lyra", 1, "hp") == 30)
	check("defense cuts about a quarter at 25 points", absf(R.cut_pct(25.0) - 25.0) < 0.001)
	check("cut never reaches the maximum", R.cut_pct(100000.0) < 80.0)
	check("phys damage never below 1", R.phys_dmg(1, 9999) == 1)
	check("phys damage example (atk 25 vs def 25)", R.phys_dmg(25, 25) == 19)
	check("piercing ignores defense", R.skill_damage(R.SKILLS.golpeBaixo, 20, 0, 25, 0, false) == 26)
	check("holy is 1.5x against the undead", R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, true) == int(1.5 * R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, false)))
	check("heal amount", R.heal_amount(R.SKILLS.cura, 10) == 40)
	check("boss cycle: hit, drain, hit, bell", [R.boss_move(0, false), R.boss_move(1, false), R.boss_move(2, false), R.boss_move(3, false)] == ["hit", "drain", "hit", "bell"])
	check("enraged boss rings the bell more often", R.boss_move(2, true) == "bell")
	check("enraged boss hits harder", R.boss_atk(24, true) > R.boss_atk(24, false))
	check("cannot pay without enough energy", not R.can_pay(R.SKILLS.golpe, 0, 10) and R.can_pay(R.SKILLS.golpe, 0, 20))
	# combo
	check("combo points are capped", R.combo_gain(7, 3) == R.COMBO_MAX and R.combo_gain(0) == 1)
	check("combo needs enough points", not R.combo_ready("corte", 2, ["aldo", "andilla"]) and R.combo_ready("corte", 3, ["aldo", "andilla"]))
	check("combo needs both members alive", not R.combo_ready("corte", 8, ["aldo"]) and R.combo_ready("escudo", 4, ["teo", "lyra", "aldo"]))
	check("combo points come only from the basic attack", R.combo_points("attack") == 1 and R.combo_points("defend") == 0 and R.combo_points("skill") == 0 and R.combo_points("item") == 0)
	check("each hero only sees the combos they join", R.combos_of("aldo") == ["corte"] and R.combos_of("lyra") == ["escudo"])
	check("combo damage beats one plain hit", R.combo_damage(25, 20, 25) > R.phys_dmg(25, 25))
	check("shield combo heals 40 percent", R.combo_heal(50) == 20)
	check("boss forecast follows the cycle", R.boss_forecast(R.boss_state()) == ["hit", "drain", "hit"])
	_forecast_tests()
	_scene_rules_tests()
	_timed_tests()
	_economy_tests()
	_ui_tests()
	_font_tests()
	_touch_tests()
	_dialogue_tests()
	_dialogue_data_tests()
	_audio_tests()
	_save_tests()
	_shop_tests()
	_choice_tests()
	_npc_tests()
	quit(1 if fails > 0 else 0)

## A previsão nunca mente: o golpe executado é sempre o primeiro ícone mostrado, mesmo cruzando a fúria em qualquer
## turno, e o ciclo não tem buracos (nunca duas badaladas seguidas, sempre ao menos 2 turnos entre elas).
func _forecast_tests() -> void:
	var lied := 0
	var bad_gap := 0
	var raged_ok := true
	for cross in 12:                      # turno em que a vida cai abaixo de 40%
		var st := R.boss_state()
		var seq := []
		for turn in 16:
			var shown: String = R.boss_forecast(st)[0]
			var frac := 0.3 if turn >= cross else 0.9
			var did := R.boss_turn(st, frac)
			if did != shown:
				lied += 1
			seq.append(did)
		raged_ok = raged_ok and st.enraged
		var last := -99
		for i in seq.size():
			if seq[i] == "bell":
				if i - last < 3:
					bad_gap += 1
				last = i
	check("forecast first icon is always the move made (%d lies)" % lied, lied == 0)
	check("no back to back bells after fury (%d short gaps)" % bad_gap, bad_gap == 0)
	check("boss stays enraged", raged_ok)
	var st2 := R.boss_state()
	R.boss_turn(st2, 0.9)                 # turno 0: golpe; o próximo anunciado é o dobre
	check("fury keeps the announced move", R.boss_forecast(st2)[0] == "drain" and R.boss_turn(st2, 0.2) == "drain")
	check("fury restarts the cycle", st2.step == 0 and R.boss_forecast(st2) == ["hit", "drain", "bell"])

## Regras que moravam na cena da batalha (Sprint 4.1): sorteio, dano do chefe, defesa, energia, carga e --auto.
func _scene_rules_tests() -> void:
	check("roll maps 0..1 onto the range", is_equal_approx(R.roll("dmg", 0.0), 0.88) and is_equal_approx(R.roll("dmg", 1.0), 1.12) and is_equal_approx(R.roll("soft", 0.5), 1.0))
	check("max_stat adds the matching bonus only", R.max_stat("aldo", 4, "hp", {"hp": 5, "mp": 9}) == R.stat("aldo", 4, "hp") + 5 and R.max_stat("lyra", 4, "mp", {"hp": 5}) == R.stat("lyra", 4, "mp"))
	check("bell: BELL_RAW through resistance, fury multiplies", R.bell_damage(21, false) == R.mag_dmg(R.BELL_RAW, 21) and R.bell_damage(21, true) == R.mag_dmg(R.BELL_RAW * R.RAGE_MULT, 21) and R.bell_damage(21, true) > R.bell_damage(21, false))
	check("drain: DRAIN_RAW through resistance", R.drain_damage(7) == R.mag_dmg(R.DRAIN_RAW, 7))
	check("boss hit uses its atk and fury", R.boss_hit_damage(37, false) == R.phys_dmg(R.SINEIRO.atk, 37) and R.boss_hit_damage(37, true) == R.phys_dmg(R.SINEIRO.atk * R.RAGE_MULT, 37))
	check("defending halves damage, never below 1", R.taken(21, true) == 10 and R.taken(1, true) == 1 and R.taken(21, false) == 21)
	check("energy: attack +15, defend +10, capped at 100", R.energy_after("aldo", 10, "attack") == 25 and R.energy_after("andilla", 95, "defend") == 100)
	check("energy: only Aldo gains when hurt, mages have none", R.energy_after("aldo", 10, "hurt") == 18 and R.energy_after("andilla", 10, "hurt") == 10 and R.energy_after("lyra", 0, "attack") == 0)
	check("full charge adds 30 percent, none adds nothing", R.charged(70, 1.0) == 91 and R.charged(70, 0.0) == 70)
	_role_tests()
	var p := {}
	for id in R.ORDER:
		p[id] = {"hp": R.stat(id, 4, "hp"), "hpmax": R.stat(id, 4, "hp"), "mp": R.stat(id, 4, "mp"), "en": 10}
	check("auto: Lyra opens with her first spell, Aldo without energy attacks", R.auto_choice("lyra", p, 0) == {"type": "skill", "id": "fogo"} and R.auto_choice("aldo", p, 0) == {"type": "attack"})
	p.aldo.hp = 10
	check("auto: Teo heals the hurt hero", R.auto_choice("teo", p, 0) == {"type": "skill", "id": "cura", "target": "aldo"})
	p.lyra.hp = 10
	check("auto: shield with two hurt and enough points", R.auto_choice("teo", p, R.COMBOS.escudo.cost).id == "escudo")
	check("auto: only a member starts a combo", R.auto_choice("aldo", p, 8).get("id", "") == "corte" and R.auto_choice("lyra", p, 8).get("id", "") != "corte")
	p.andilla.hp = 0
	check("auto: no Double Cut with Andilla down", R.auto_choice("aldo", p, 8).get("id", "") != "corte")

## Papéis (Sprint 4.2): Luz de 45 a 55 no Sineiro, Lyra o maior dano, Gelo tira a vez do chefe, Dobre drena tudo.
func _role_tests() -> void:
	var dmg := func(sid: String, hid: String) -> int:
		return R.skill_damage(R.SKILLS[sid], R.stat(hid, 4, "atk"), R.stat(hid, 4, "mag"), R.SINEIRO.def, R.SINEIRO.res, true)
	var luz: int = dmg.call("luz", "teo")
	check("Holy Light on the Sineiro is 45 to 55 at level 4 (%d)" % luz, luz >= 45 and luz <= 55)
	var best := {}
	for hid in R.ORDER:
		best[hid] = R.HEROES[hid].skills.map(func(sid): return dmg.call(sid, hid) if R.SKILLS[sid].kind != "heal" else 0).max()
	check("Lyra has the biggest single hit (%s)" % [best], R.ORDER.all(func(h): return h == "lyra" or best[h] < best.lyra))
	var st := R.boss_state()
	check("ice freezes a fresh boss", R.freeze(st) and not R.freeze(st))
	check("frozen boss loses the turn and keeps the announced move", R.boss_turn(st, 0.9) == "frozen" and R.boss_forecast(st)[0] == "hit" and st.step == 0)
	check("just thawed boss resists ice for one round", not R.freeze(st) and R.boss_turn(st, 0.9) == "hit" and R.freeze(st))
	var st2 := R.boss_state()
	R.freeze(st2)
	R.boss_turn(st2, 0.1)
	check("fury waits for the boss to thaw", not st2.enraged and R.boss_turn(st2, 0.1) == "hit" and st2.enraged)
	var lied := 0
	var st3 := R.boss_state()
	for turn in 30:
		if turn % 3 == 0:
			R.freeze(st3)
		var shown: String = R.boss_forecast(st3)[0]
		var did := R.boss_turn(st3, 0.9 if turn < 12 else 0.2)
		if did != "frozen" and did != shown:
			lied += 1
	check("forecast never lies with ice in the mix (%d)" % lied, lied == 0)
	var lyra_worst := R.boss_hit_damage(R.stat("lyra", 4, "def"), true, R.ROLL.dmg.y)
	check("enraged hit never one-shots a full Lyra (worst roll %d)" % lyra_worst, lyra_worst < R.stat("lyra", 4, "hp"))
	check("drain gives back all it took", R.drain_heal(17) == 17)
	var p := {}
	for id in R.ORDER:
		p[id] = {"hp": 50, "hpmax": 50, "mp": 30, "en": 0}
	var bell := R.boss_state()
	bell.step = 3
	check("auto casts Ice before the bell, Fire otherwise", R.auto_choice("lyra", p, 0, bell).id == "gelo" and R.auto_choice("lyra", p, 0, R.boss_state()).id == "fogo")
	bell.thawed = true
	check("auto skips Ice when the boss resists", R.auto_choice("lyra", p, 0, bell).id == "fogo")

## Ação no tempo certo (Sprint 4.4): janela de 150 ms em volta do impacto, só o primeiro aperto conta.
func _timed_tests() -> void:
	check("timed window is about 150 ms", R.TIMED_EARLY_MS + R.TIMED_LATE_MS == 150)
	check("press inside the window counts", R.timed_ok(1000, 1000) and R.timed_ok(1000 - R.TIMED_EARLY_MS, 1000) and R.timed_ok(1000 + R.TIMED_LATE_MS, 1000))
	check("press too early, too late or none misses", not R.timed_ok(1000 - R.TIMED_EARLY_MS - 1, 1000) and not R.timed_ok(1000 + R.TIMED_LATE_MS + 1, 1000) and not R.timed_ok(-1, 1000))
	check("timed attack hits 50 percent harder", R.attack_damage(22, 1.0, true) == R.phys_dmg(22, R.SINEIRO.def, 1.5) and R.attack_damage(22, 1.0, true) > R.attack_damage(22))
	check("timed attack gives one extra combo point", R.combo_points("attack") + R.combo_points("timed") == 2)
	check("block halves, and stacks with defend", R.taken(20, false, true) == 10 and R.taken(20, true, true) == 5 and R.taken(1, true, true) == 1)
	check("tap prompt per device", C.prompt_for("tap", "keys") == "aperte E" and C.prompt_for("tap", "pad") == "aperte A" and C.prompt_for("tap", "touch") == "toque na tela")

## Itens da batalha (Sprint 4.5): bolsa fixa, Poção, Éter, Pena Vital e a escolha do --auto.
func _economy_tests() -> void:
	check("start bag is 2 Potions (the Feather is bought), and is a copy", EC.start_bag() == {"pocao": 2} and not is_same(EC.start_bag(), EC.START_BAG))
	check("balance profile (careful player) is 2 Potions and 1 Feather", EC.CAREFUL_BAG == {"pocao": 2, "pena": 1})
	check("item ids never change (save keys)", EC.ITEMS.keys() == ["pocao", "eter", "pena"])
	var t := {"hp": 10, "hpmax": 78, "mp": 0, "mpmax": 0}
	check("potion heals 50 and reports the amount", EC.apply_item("pocao", t) == 50 and t.hp == 60)
	check("potion stops at max", EC.apply_item("pocao", t) == 18 and t.hp == 78)
	check("potion is not for the full or the fallen", not EC.can_use("pocao", t) and not EC.can_use("pocao", {"hp": 0, "hpmax": 78}))
	var down := {"hp": 0, "hpmax": 45, "mp": 3, "mpmax": 32}
	check("feather only on the fallen, back with half HP", EC.can_use("pena", down) and EC.apply_item("pena", down) == 22 and down.hp == 22 and not EC.can_use("pena", down))
	check("ether only for who has MP missing", EC.can_use("eter", down) and not EC.can_use("eter", t) and EC.apply_item("eter", down) == 20 and down.mp == 23)
	var bag := {"pocao": 1}
	check("take empties the bag, then refuses", EC.take(bag, "pocao") and bag.pocao == 0 and not EC.take(bag, "pocao") and not EC.take(bag, "pena"))
	EC.add(bag, "pocao", 500)
	check("stacks are capped at 99", bag.pocao == 99)
	var p := {}
	for id in R.ORDER:
		p[id] = {"hp": 50, "hpmax": 50, "mp": 30, "mpmax": 30, "en": 0}
	check("usable needs stock and a target", not EC.usable({"pena": 1}, "pena", p, R.ORDER) and not EC.usable({}, "pocao", {"aldo": {"hp": 5, "hpmax": 50}}, R.ORDER))
	p.lyra.hp = 0
	check("targets list the fallen for the feather", EC.targets("pena", p, R.ORDER) == ["lyra"])
	check("auto raises the fallen first", R.auto_choice("aldo", p, 8, {}, {"pena": 1}) == {"type": "item", "id": "pena", "target": "lyra"})
	check("auto never revives without a feather", R.auto_choice("aldo", p, 0, {}, {}).type != "item")
	p.lyra.hp = 45
	p.aldo.hp = 10
	check("auto: potion on the badly hurt when the hero cannot cure", R.auto_choice("andilla", p, 0, {}, {"pocao": 2}) == {"type": "item", "id": "pocao", "target": "aldo"})
	check("auto: Teo cures instead of using a potion", R.auto_choice("teo", p, 0, {}, {"pocao": 2}).get("id", "") == "cura")

func _ui_tests() -> void:
	check("safe area keeps 16 px from every edge", U.safe_area(Vector2(640, 360)) == Rect2(16, 16, 608, 328))
	check("safe area adds the device cutout", U.safe_area(Vector2(800, 360), Vector2(30, 0), Vector2(0, 10)) == Rect2(46, 16, 738, 318))
	var area := Rect2(16, 16, 608, 328)
	check("panel inside stays where it is", U.clamp_in(Vector2(300, 100), Vector2(112, 88), area) == Vector2(300, 100))
	check("panel past the right and bottom edges is pulled back", U.clamp_in(Vector2(600, 330), Vector2(112, 88), area) == Vector2(512, 256))
	check("panel past the top left is pulled in", U.clamp_in(Vector2(-5, 2), Vector2(112, 88), area) == Vector2(16, 16))
	var sizes_ok := true
	for k in U.ICONS:
		sizes_ok = sizes_ok and U.ICONS[k].size() == 16 and U.ICONS[k].all(func(r): return r.length() == 16)
		sizes_ok = sizes_ok and U.ICON_COLOR.has(k)
	check("every pixel icon is 16x16 with a colour", sizes_ok)
	check("keyboard prompt is E, touch and pad prompt is A", C.prompt_for("confirm", "keys") == "E" and C.prompt_for("confirm", "touch") == "A" and C.prompt_for("confirm", "pad") == "A")
	check("unknown prompt falls back to the action name", C.prompt_for("xyz", "keys") == "xyz")
	check("every action with keys has a keyboard prompt", ["confirm", "cancel", "menu", "fullscreen"].all(func(a): return C.KEYS.has(a) and C.PROMPTS.keys.has(a)))

## A fonte do jogo precisa ter todo caractere que o jogador pode ver, e o texto não usa travessão.
func _font_tests() -> void:
	var font := load(U.BODY_FONT) as FontFile
	var pt := "áàâãéêíóôõúüçÁÀÂÃÉÊÍÓÔÕÚÇ#&<>[]@%+=*/:;!?'\"()-.,0123456789"
	var miss := ""
	for i in pt.length():
		if not font.has_char(pt.unicode_at(i)):
			miss += pt[i]
	check("UI font has the Portuguese letters and symbols (missing: '%s')" % miss, miss == "")
	var bad := ""
	var dash := ""
	for file in DirAccess.get_files_at("res://scripts"):
		if not file.ends_with(".gd") and not file.ends_with(".json"):
			continue
		for line in FileAccess.get_file_as_string("res://scripts/" + file).split("\n"):
			if line.strip_edges().begins_with("#"):
				continue
			for i in line.length():
				var c := line.unicode_at(i)
				if c == 0x2014 or c == 0x2013:
					dash += file + " "
				elif c > 127 and not font.has_char(c) and not bad.contains(line[i]):
					bad += line[i]
	check("game scripts have no em or en dash (%s)" % dash.strip_edges(), dash == "")
	check("every non-ASCII character in scripts exists in the UI font (missing: '%s')" % bad, bad == "")
	var ts := TextServerManager.get_primary_interface()
	var line := TextLine.new()
	line.add_string("fica", U.body_font(), 12)
	check("body font draws 'fi' as two letters (no ligature: it read as 'A')", ts.shaped_text_get_glyph_count(line.get_rid()) == 4)

## Toque (Sprint 2): segurar, dois toques, botões sem zona em comum, orçamento do celular, menu de pausa.
func _touch_tests() -> void:
	check("hold: the confirm button always counts", C.holding(true, false, 0) and C.holding(true, true, 0))
	check("hold: any finger counts only in touch mode", C.holding(false, true, 1) and not C.holding(false, false, 1) and not C.holding(false, true, 0))
	check("hold prompt reads 'o dedo na tela' on touch and E on keys", C.prompt_for("hold", "touch") == "o dedo na tela" and C.prompt_for("hold", "keys") == "E" and C.prompt_for("hold", "pad") == "A")
	check("two taps: first tap only marks the row", not U.tap_confirms("", "Fogo", true) and not U.tap_confirms("Gelo", "Fogo", true))
	check("two taps: second tap on the same row confirms", U.tap_confirms("Fogo", "Fogo", true))
	check("keyboard and pad confirm on the first press", U.tap_confirms("", "Fogo", false))
	# A e B do toque (UI.ab_spots) em 640x360, 800x360 e 640x400: o mais perto vence e nada fica de fora
	var r := 22.0 * 1.5
	var spaced := true
	for s in [Vector2(640, 360), Vector2(800, 360), Vector2(640, 400)]:
		var a: Vector2 = U.ab_spots(s)[0]
		var b: Vector2 = U.ab_spots(s)[1]
		spaced = spaced and a.distance_to(b) >= 2.0 * r and C.nearest([a, b], a, r) == 0 and C.nearest([a, b], b + Vector2(-20, 0), r) == 1
		spaced = spaced and C.nearest([a, b], Vector2(s.x / 2.0, s.y / 2.0), r) == -1
	check("touch A and B hit zones never overlap", spaced)
	check("nearest picks the closer of two overlapping zones", C.nearest([Vector2(0, 0), Vector2(40, 0)], Vector2(25, 0), 33.0) == 1)
	check("touch keeps only the first MAX_LIGHTS_TOUCH lights", F.light_on(F.MAX_LIGHTS_TOUCH - 1, true) and not F.light_on(F.MAX_LIGHTS_TOUCH, true) and F.light_on(50, false))
	check("touch halves the particles, never below 1", F.particles(26, true) == 13 and F.particles(1, true) == 1 and F.particles(26, false) == 26)
	check("touch: dialogue mode (back button, tap to advance) only while the game runs", C.dialogue_mode(true, false) and not C.dialogue_mode(true, true) and not C.dialogue_mode(false, false))
	check("pause menu: desktop has all four items", U.pause_items(false, false) == ["Continuar", "Opções", "Tela cheia", "Sair"])
	check("pause menu: no Quit on the web", U.pause_items(true, false) == ["Continuar", "Opções", "Tela cheia"])
	check("pause menu: phone has Continue and Options", U.pause_items(false, true) == ["Continuar", "Opções"])
	check("touch rows are 44 px and the touch text doubles the native 12", U.ROW_TOUCH >= 44 and U.TEXT_TOUCH == 24)
	var num := load(U.NUM_FONT) as FontFile
	var need := "0123456789PVENMPC+-/ "
	var miss := ""
	for i in need.length():
		if not num.has_char(need.unicode_at(i)):
			miss += need[i]
	check("number font has digits and card letters (missing: '%s')" % miss, miss == "")

## Diálogo (Sprint 3): regras puras.
func _dialogue_tests() -> void:
	var flags := {"a": true}
	check("dialogue if: all conditions must hold", D.check(["flag:a", "!flag:b", "party:teo"], flags, ["teo"]) and not D.check(["flag:a", "flag:b"], flags, []))
	check("dialogue if: negated party and empty list", D.check(["!party:lyra"], {}, ["teo"]) and D.check([], {}, []))
	var lines := [{"id": "x", "if": ["flag:z"], "next": "end"}, {"id": "y", "next": "w"}, {"id": "v"}, {"id": "w", "next": "end"}]
	check("dialogue skips lines whose if fails", D.first_valid(lines, 0, {}, []) == 1 and D.first_valid(lines, 0, {"z": true}, []) == 0)
	check("dialogue follows next and end", D.after(lines, 1) == 3 and D.after(lines, 0) == -1 and D.after(lines, 3) == -1 and D.after(lines, 2) == 3)
	check("dialogue with no valid line is empty", D.first_valid([{"id": "q", "if": ["flag:z"]}], 0, {}, []) == -1)
	check("dialogue ids are found or -1", D.index_of(lines, "w") == 3 and D.index_of(lines, "nope") == -1)
	var f2 := {"old": true}
	var rest := D.apply_events(["set:new", "clear:old", "battle:sineiro", "emit:x"], f2)
	check("dialogue do: set and clear flags, others go back to the scene", f2 == {"new": true} and rest == ["battle:sineiro", "emit:x"])
	check("dialogue names fill {aldo}", D.fill("{aldo} ouviu. {aldo}!", {"aldo": "Aldo"}) == "Aldo ouviu. Aldo!")
	check("dialogue [em] becomes yellow bbcode, other brackets are escaped", D.to_bbcode("a [em]b[/em] [x]") == "a [color=#ffe080]b[/color] [lb]x]")
	var font := U.body_font()
	var w := D.wrap_lines("um dois três quatro cinco seis sete oito nove dez onze doze treze", font, 12, 100.0)
	var fits := w.size() > 1
	for ln in w:
		fits = fits and font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x <= 100.0
	check("dialogue wrap keeps every line inside the width (%d lines)" % w.size(), fits and " ".join(w) == "um dois três quatro cinco seis sete oito nove dez onze doze treze")
	check("dialogue wrap ignores [em] markup width", D.wrap_lines("[em]abc[/em] de", font, 12, font.get_string_size("abc de", 0, -1, 12).x).size() == 1)
	check("dialogue wrap never splits a long word", D.wrap_lines("abcdefghijklmnop", font, 12, 10.0) == PackedStringArray(["abcdefghijklmnop"]))
	check("typing: 50 cps is 0.02 s per letter", is_equal_approx(D.char_time("abc", 1, 50), 0.02))
	check("typing: a full stop adds 0.25 s, a comma 0.10 s", is_equal_approx(D.char_time("a. b", 2, 50), 0.27) and is_equal_approx(D.char_time("a, b", 2, 50), 0.12))
	check("typing: three dots pause once at the end (0.30 s)", D.pause_after("a... b", 1) == 0.0 and D.pause_after("a... b", 2) == 0.0 and is_equal_approx(D.pause_after("a... b", 3), 0.30))
	check("typing: no pause inside a token (3.5) or for the last letter of the text", D.pause_after("3.5", 1) == 0.0 and is_equal_approx(D.pause_after("fim.", 3), 0.25))
	check("typing: slow and fast scale the pauses, instant is zero", is_equal_approx(D.char_time("a. b", 2, 30), 1.0 / 30.0 + 0.25 * 50.0 / 30.0) and D.char_time("a. b", 2, 0) == 0.0)
	check("typing speeds are 30, 50, 80 and instant", D.SPEEDS.values() == [30, 50, 80, 0])
	check("confirm is ignored for 0.15 s after opening", not D.accepts_confirm(0.1) and D.accepts_confirm(0.15))
	var safe := U.safe_area(Vector2(640, 360))
	check("dialogue box is 544x88 at x 48, y 256 or 16", D.box_rect(640, safe, false) == Rect2(48, 256, 544, 88) and D.box_rect(640, safe, true) == Rect2(48, 16, 544, 88))
	check("dialogue box stays 544 and centred on wide screens", D.box_rect(800, U.safe_area(Vector2(800, 360)), false) == Rect2(128, 256, 544, 88))
	var bottom := D.box_rect(640, safe, false)
	var top := D.box_rect(640, safe, true)
	check("box goes up when the speaker stands behind it", D.box_on_top(D.speaker_rect(Vector2(300, 300)), bottom, top))
	check("box stays down for a speaker up high, for narration, and when both would cover", not D.box_on_top(D.speaker_rect(Vector2(300, 200)), bottom, top) and not D.box_on_top(Rect2(), bottom, top) and not D.box_on_top(Rect2(0, 0, 640, 360), bottom, top))
	var menu := Vector2(640 - 16 - 22, 16 + 22)
	var low := D.touch_spots(bottom, false, menu, 22.0)
	var high := D.touch_spots(top, true, menu, 22.0)
	check("touch back button is 44x44 at (48,204) above a low box and (48,112) below a high one", low[0] == Vector2(70, 226) and high[0] == Vector2(70, 134))
	check("touch menu button stays in the corner unless the high box covers it, then drops below", low[1] == menu and high[1] == Vector2(menu.x, 134))
	check("touch menu button keeps the corner on wide screens", D.touch_spots(D.box_rect(800, U.safe_area(Vector2(800, 360)), true), true, Vector2(762, 38), 22.0)[1] == Vector2(762, 38))
	check("translation key is dlg.<scene>.<id>", D.key("abertura", "l01") == "dlg.abertura.l01")

## Teste de dados: todo arquivo de data/dialogue passa nas regras (nomes proibidos, travessão, 3 linhas, glifos,
## falante e retrato existentes, ids, next, verbos). E o validador pega cada erro de propósito.
func _dialogue_data_tests() -> void:
	var font := U.body_font()
	var spk := D.speakers()
	var face := func(id: String) -> bool: return F.FACE_CENTER.has(id) and F.new_art(id)
	check("speakers.json opens", not spk.is_empty())
	var n := 0
	for file in DirAccess.get_files_at(D.DIR):
		if not file.ends_with(".json") or file == "speakers.json":
			continue
		n += 1
		var data: Variant = D.load_json(D.DIR + file)
		if not data is Dictionary:
			check("%s opens as JSON" % file, false)
			continue
		var errs: Array = D.validate(data, spk, font, face)
		check("%s passes the dialogue rules %s" % [file, errs], errs.is_empty())
	check("found the dialogue scenes (%d)" % n, n >= 9)
	var bad := {"lines": [
		{"id": "a", "speaker": "narrador", "text": "O dragão e a Irmandade de Velkor \u2014 Morvath."},
		{"id": "a", "speaker": "ninguem", "text": "oi"},
		{"id": "c", "speaker": "narrador", "text": "Letra estranha \u2605", "if": ["xis:y"], "do": ["voar:alto"], "next": "zz"},
		{"id": "d", "speaker": "narrador", "text": "palavra ".repeat(60)},
		{"id": "e", "speaker": "semface", "text": "oi"}]}
	var bspk := spk.duplicate()
	bspk["semface"] = {"name": "X", "portrait": true}
	var errs := " ".join(D.validate(bad, bspk, font, face))
	var caught := ["velkor", "morvath", "irmandade", "dragã", "travessão", "repetido", "ninguem", "\u2605", "xis:y", "voar:alto", "'zz'", "linhas", "sem retrato"]
	var missed := caught.filter(func(k): return not errs.contains(k))
	check("validator catches every planted error (missed: %s)" % [missed], missed.is_empty())

## Som: cada nome aponta para um arquivo que existe e carrega; laço só em música e ambiente; barramentos; escolha de
## voz; volumes e ducking; esperas; clique da digitação; passos sem repetir; navegador só depois do primeiro toque.
func _audio_tests() -> void:
	var missing := []
	var lens := {}
	for n in AU.SOUNDS:
		var s: AudioStream = load(AU.path(n)) if ResourceLoader.exists(AU.path(n)) else null
		if s == null:
			missing.append(n)
		else:
			lens[n] = s.get_length()
	check("every sound name loads (missing: %s)" % [missing], missing.is_empty())
	check("all 38 audio files are named", AU.SOUNDS.values().reduce(func(acc, v): return acc if acc.has(v) else acc + [v], []).size() == 38)
	check("the charge riser lasts exactly the 1.0 s of the charge", absf(float(lens.get("carga", 0.0)) - 1.0) < 0.01)
	check("unknown sound has no path", AU.path("velkor") == "")
	check("music and ambience loop, jingles and effects do not", AU.loops("valmor_noite") and AU.loops("cripta_gotas")
		and not AU.loops("vitoria") and not AU.loops("badalada") and not AU.loops("cursor"))
	check("bus by folder", AU.bus_of("chefe_sineiro") == "Music" and AU.bus_of("derrota") == "Music" and AU.bus_of("valmor_vento") == "Ambience"
		and AU.bus_of("cursor") == "UI" and AU.bus_of("digitar") == "UI" and AU.bus_of("badalada") == "SFX" and AU.bus_of("passo_neve_2") == "SFX")
	check("bus layout has Music, Ambience, SFX and UI", AU.BUSES.all(func(b): return AudioServer.get_bus_index(b) > 0))
	check("voice: first free one", AU.pick_voice([true, false, false], [1.0, 2.0, 3.0]) == 1)
	check("voice: all busy cuts the oldest", AU.pick_voice([true, true, true], [5.0, 2.0, 3.0]) == 1)
	check("voice limit is 8 effects at most", AU.MAX_VOICES.SFX <= 8)
	check("level 10 is the mix volume, 0 is mute", AU.level_db(10) == 0.0 and AU.level_db(0) == AU.MUTE_DB)
	check("level 5 is about -6 dB", absf(AU.level_db(5) + 6.02) < 0.05)
	check("ducking only lowers the music", AU.bus_db("Music", 10, AU.DUCK_DB) == AU.BUS_DB.Music + AU.DUCK_DB
		and AU.bus_db("SFX", 10, AU.DUCK_DB) == AU.BUS_DB.SFX)
	check("ducking is 4 to 6 dB, in 0.3 s", AU.DUCK_DB <= -4.0 and AU.DUCK_DB >= -6.0 and AU.DUCK_IN == 0.3)
	check("a muted option stays muted even ducked", AU.bus_db("Music", 0, AU.DUCK_DB) == AU.MUTE_DB)
	check("music option drives Music, effects drive the rest", AU.option_of("Music") == "music" and AU.option_of("Ambience") == "sfx" and AU.option_of("UI") == "sfx")
	var seen := [10]
	for i in AU.LEVELS.size():
		seen.append(AU.level_next(seen[-1]))
	check("volume option cycles 10, 8, 6, 4, 2, 0 and back", seen == [10, 8, 6, 4, 2, 0, 10])
	check("odd level goes back to full", AU.level_next(7) == AU.DEFAULT_LEVEL)
	check("volume text", AU.level_text(8) == "80%" and AU.level_text(0) == "0%")
	check("wait_left never negative", AU.wait_left(3.0, 2.5) == 0.0 and AU.wait_left(1.0, 2.5) == 1.5)
	check("victory jingle waits the last toll and a silence", AU.LAST_TOLL + AU.SILENCE >= float(lens.get("ultimo_toque", 99.0)) - 1.5)
	check("typing clicks on letters, not on spaces or punctuation", AU.click_due("a", 1.0) and not AU.click_due(" ", 1.0) and not AU.click_due(".", 1.0))
	check("typing clicks are spaced", not AU.click_due("a", AU.CLICK_GAP * 0.5))
	var last := -1
	var repeats := 0
	var used := {}
	for i in 200:
		var k := AU.step_pick(last, float(i % 37) / 37.0)
		repeats += int(k == last)
		used[k] = true
		last = k
	check("snow steps never repeat and use all four", repeats == 0 and used.size() == 4)
	check("steps are named sounds", AU.STEPS.all(func(n): return AU.SOUNDS.has(n)))
	check("on the web loops wait for the first touch", not AU.may_start(true, false) and AU.may_start(true, true) and AU.may_start(false, false))

## Save (Sprint 5.1): ida e volta, migração do v0 guardado em tests/fixtures, arquivo estragado volta ao padrão.
func _save_tests() -> void:
	var g := SV.new_game()
	check("new game: level 4, full HP, 60 coins, 2 Potions, no chest", g.party.aldo.lv == 4 and g.party.aldo.hp == R.max_stat("aldo", 4, "hp", {}) and g.gold == 60 and g.inv == {"pocao": 2} and g.opened.is_empty())
	g.flags = {"sineiro_morto": true, "abertura_vista": true}
	g.gold = 5
	g.inv = {"pena": 1}
	g.opened = ["valmor:quintal"]
	g.pos = [300.0, 410.0]
	g.party.lyra.hp = 12
	var opts := {"text_speed": "rapida", "music": 6, "sfx": 0}
	var back := SV.parse(SV.pack(g, opts, 123))
	check("save round trip keeps game, options and version", back.version == SV.VERSION and back.saved_at == 123 and back.game == g and back.options == opts)
	check("save without a game has only options (no Continue)", not SV.parse(SV.pack(null, opts)).has("game"))
	var v0 := FileAccess.get_file_as_string("res://tests/fixtures/save_v0.json")
	var m := SV.parse(v0)
	check("v0 fixture opens", m.has("game") and v0 != "")
	if m.has("game"):
		var mg: Dictionary = m.game
		check("v0 migrates: flags, party and position kept", mg.flags == {"abertura_vista": true, "sineiro_morto": true} and mg.party.lyra.mp == 12 and mg.pos == [312.0, 498.5])
		check("v0 migrates: economy fields get the start values", mg.gold == EC.START_GOLD and mg.inv == EC.START_BAG and mg.opened.is_empty())
		check("v0 migrates: text speed goes to options, others default", m.options == {"text_speed": "rapida", "music": AU.DEFAULT_LEVEL, "sfx": AU.DEFAULT_LEVEL})
		check("v0 migrates: HP clamped to 1..max (999 and 0)", mg.party.teo.hp == R.max_stat("teo", 4, "hp", {}) and mg.party.andilla.hp == 1)
	var broken := ["", "{", "[1, 2]", "null", "\"texto\"", "{\"version\": 1, \"game\": 7}"]
	check("broken files read as no save, without crashing", broken.all(func(x): return not SV.parse(x).has("game")))
	check("broken JSON is empty (falls to the backup)", SV.parse("{").is_empty() and SV.parse("[1]").is_empty())
	var junk := SV.parse(JSON.stringify({"version": 1, "options": {"text_speed": "turbo", "music": 7, "sfx": "x"},
		"game": {"scene": "lua", "pos": ["a", 1], "flags": {"a": 1, "b": true}, "party": {"aldo": {"lv": -3, "hp": "x"}, "zeca": {}},
		"gold": -50, "inv": {"pocao": 500, "pena": -2, "item_futuro": 3}, "opened": ["valmor:poco", 9, "valmor:poco"]}}))
	var jg: Dictionary = junk.game
	check("junk options fall back to defaults", junk.options == SV.default_options())
	check("junk game: bad fields fall back, good ones stay", jg.scene == "valmor" and jg.pos == null and jg.flags == {"b": true} and jg.party.aldo.lv == 1 and not jg.party.has("zeca") and jg.party.lyra == SV.new_game().party.lyra)
	check("junk game: gold, stacks and chest list clamped", jg.gold == 0 and jg.inv == {"pocao": 99, "item_futuro": 3} and jg.opened == ["valmor:poco"])
	check("a save from a newer version still reads", SV.parse(JSON.stringify({"version": 99, "game": {"gold": 7}, "campo_novo": 1})).game.gold == 7)
	var wrong := {"options": {"text_speed": "lenta"}, "game": {"gold": 33, "flags": {"abertura_vista": true}}}
	var kept := true
	for v in ["x", null, [], {}, true, "1", 1.0]:
		wrong["version"] = v
		var p := SV.parse(JSON.stringify(wrong))
		kept = kept and p.has("game") and p.game.gold == 33 and p.game.flags == {"abertura_vista": true} and p.options.text_speed == "lenta" and p.version == SV.VERSION
	check("a version of the wrong type keeps the game (read as v1 by its shape)", kept)
	check("version: numbers and numeric text count, the shape decides the rest", SV.version_of({"version": 3}) == 3 and SV.version_of({"version": " 2 "}) == 2 and SV.version_of({"version": "x", "party": {}}) == 0 and SV.version_of({"game": {}}) == 1 and SV.version_of({}) == 0)
	var v0bad := SV.parse(JSON.stringify({"version": "x", "party": {"aldo": {"lv": 5}}, "flags": {"sineiro_morto": true}}))
	check("an old v0 draft with a broken version still migrates", v0bad.has("game") and v0bad.game.flags == {"sineiro_morto": true} and v0bad.game.party.aldo.lv == 5)
	check("chest and item ids are fixed (save keys)", EC.CHESTS.keys() == ["valmor:poco", "valmor:quintal"] and EC.ITEMS.keys() == ["pocao", "eter", "pena"])

## Moedas, loja e baús (Sprint 5.2).
func _shop_tests() -> void:
	check("prices: Potion 15, Ether 30, Feather 80", EC.price("pocao") == 15 and EC.price("eter") == 30 and EC.price("pena") == 80)
	check("selling pays half, rounded down", EC.sell_price("pocao") == 7 and EC.sell_price("eter") == 15 and EC.sell_price("pena") == 40)
	check("the Feather only fits with the hidden chest's coins", EC.START_GOLD < EC.price("pena") and EC.START_GOLD + int(EC.CHESTS["valmor:quintal"].gold) >= EC.price("pena"))
	var st := {"gold": 85, "inv": {"pocao": 2}}
	check("buy max counts money and stack room", EC.buy_max(85, {}, "pocao") == 5 and EC.buy_max(85, {"pocao": 97}, "pocao") == 2 and EC.buy_max(10, {}, "pocao") == 0)
	check("buy takes the price and adds one", EC.buy(st, "pena") and st.gold == 5 and st.inv.pena == 1)
	check("cannot buy without money; nothing changes", not EC.buy(st, "pocao") and st.gold == 5 and st.inv.pocao == 2)
	check("missing coins for the shop line", EC.missing(5, "pocao") == 10 and EC.missing(50, "pocao") == 0)
	check("sell gives half back and takes one", EC.sell(st, "pena") and st.gold == 45 and st.inv.pena == 0)
	check("cannot sell what is not in the bag", not EC.sell(st, "pena") and not EC.sell(st, "eter") and st.gold == 45)
	var full := {"gold": 999, "inv": {"pocao": 99}}
	check("a full stack refuses to buy", not EC.buy(full, "pocao") and full.gold == 999)
	var opened: Array = []
	var bag := {"gold": 60, "inv": {}}
	var a := EC.open_chest(opened, bag, "valmor:quintal")
	var b := EC.open_chest(opened, bag, "valmor:quintal")
	check("chest opens once: 25 coins, the second time nothing", a.get("gold", 0) == 25 and b.is_empty() and bag.gold == 85 and opened == ["valmor:quintal"])
	check("visible chest gives a Potion", EC.open_chest(opened, bag, "valmor:poco").get("item", "") == "pocao" and bag.inv.pocao == 1)
	check("unknown chest gives nothing", EC.open_chest(opened, bag, "lua:x").is_empty() and opened.size() == 2)
	check("loot text", EC.loot_text({"gold": 25}) == "25 moedas" and EC.loot_text({"item": "pocao", "n": 1}) == "Poção")

## Escolhas no diálogo (Sprint 5.3).
func _choice_tests() -> void:
	var ln := {"id": "q", "text": "?", "choices": [{"id": "a", "text": "A", "next": "x"}, {"id": "b", "text": "B", "if": ["flag:k"]},
		{"id": "c", "text": "C", "next": "end", "cancel": true}]}
	var lines := [ln, {"id": "y", "text": "y"}, {"id": "x", "text": "x"}]
	check("choices hide the ones whose if fails", D.choices_for(ln, {}, []).map(func(c): return c.id) == ["a", "c"] and D.choices_for(ln, {"k": true}, []).size() == 3)
	check("cancel picks the marked option, or none", D.cancel_choice(ln.choices) == 2 and D.cancel_choice([{"id": "a"}]) == -1)
	check("choice next: the option's next, end, or the following line", D.choice_next(lines, 0, ln.choices[0]) == 2 and D.choice_next(lines, 0, ln.choices[2]) == -1 and D.choice_next(lines, 0, ln.choices[1]) == 1)
	check("choice rows: 44 on touch, 26 on keys", D.choice_row_h(true) == 44 and D.choice_row_h(false) == 26)
	var font := U.body_font()
	check("choice panel width: 160 to 300 on keys", D.choice_width(["Sim"], font, 12) == 160.0 and D.choice_width(["x".repeat(80)], font, 12) == 300.0)
	var box := Rect2(48, 256, 544, 88)
	check("choice panel sits 6 px above a low box, right edges aligned (4 touch rows = 188 px)", D.choice_rect(box, false, 4, 44, 220) == Rect2(372, 62, 220, 188))
	check("choice panel goes below a high box", D.choice_rect(Rect2(48, 16, 544, 88), true, 2, 26, 160) == Rect2(432, 110, 160, 64))
	var spk := {"narrador": {"name": "", "portrait": false}}
	var five := {"lines": [{"id": "q", "speaker": "narrador", "text": "?", "choices": [
		{"id": "a", "text": "Um", "next": "end"}, {"id": "b", "text": "Dois"}, {"id": "c", "text": "Três"}, {"id": "d", "text": "Quatro"}, {"id": "e", "text": "Cinco"}]}]}
	var e1 := " ".join(D.validate(five, spk, font, func(_x): return true))
	check("five options fail the data test", e1.contains("5 opções"))
	var four := five.duplicate(true)
	four.lines[0].choices.resize(4)
	check("four options pass", D.validate(four, spk, font, func(_x): return true).is_empty())
	var bad := {"lines": [{"id": "q", "speaker": "narrador", "text": "?", "choices": [
		{"id": "a", "text": "Uma opção comprida demais para uma linha", "cancel": true}, {"id": "a", "text": "Ok \u2014 sim", "next": "zz", "cancel": true, "do": ["voar:x"]}]},
		{"id": "r", "speaker": "narrador", "text": "?", "choices": []}]}
	var e2 := " ".join(D.validate(bad, spk, font, func(_x): return true))
	var want := ["letras", "repetido", "travessão", "'zz'", "voar:x", "mais de uma opção de cancel", "escolhas vazias"]
	check("choice validator catches long text, repeated id, dash, bad next, bad verb, two cancels, empty (missed: %s)" % [want.filter(func(k): return not e2.contains(k))], want.all(func(k): return e2.contains(k)))
	var shop_lines := ["comprar", "compra_pocao", "compra_eter", "compra_pena", "compra_sem_moedas", "compra_bolsa_cheia", "vender", "venda_ok", "venda_nada", "despedida"]
	check("every Dora line the shop asks for exists", shop_lines.all(func(id): return D.line_text("loja_dora", id, {}, []) != "" and D.line_text("loja_dora", id, {"sineiro_morto": true}, []) != ""))
	check("Dora's goodbye changes after the fight", D.line_text("loja_dora", "despedida", {}, []) != D.line_text("loja_dora", "despedida", {"sineiro_morto": true}, []))
	check("every chest line the map asks for exists", EC.CHESTS.keys().all(func(c): return D.line_text("valmor_baus", c.split(":")[1], {}, []) != "" and D.line_text("valmor_baus", c.split(":")[1] + "_vazio", {}, []) != ""))

## Moradores de Valmor (Sprint 6): cada cena ligada existe, tem o falante certo e segue antes, repetição, depois e
## repetição pelas flags falou_<id>_*; a Irene só cura depois do Sineiro; o Tobias fecha a fatia; ninguém fica na
## parede, em cima de outro ponto ou debaixo da luz de um poste; as flags novas entram no save.
func _npc_tests() -> void:
	var spk := D.speakers()
	var heroes := ["aldo", "lyra", "teo", "andilla"]
	for scene in ["abertura", "igreja_velha", "valmor_exame", "valmor_volta", "fim_fatia", "valmor_baus", "loja_dora_menu"]:
		check("map scene %s exists" % scene, not D.load_scene(scene).get("lines", []).is_empty())
	for id in VR.NPCS:
		var n: Dictionary = VR.NPCS[id]
		var who := {}
		for ln in D.load_scene(n.scene).get("lines", []):
			if ln.has("speaker"):
				who[ln.speaker] = true
		check("%s: scene %s exists, speaker in speakers.json and in the scene" % [id, n.scene], spk.has(id) and who.has(id) and ResourceLoader.exists("res://assets/heroes/%s/rot_south.png" % n.base))
	for id in ["hugo", "berta", "ana", "irene", "nino", "bertoldo", "clara"]:
		var scene: String = VR.NPCS[id].scene
		var f := {}
		var r1 := D.dry_run(scene, f, heroes)
		var first: String = r1.lines[0].id if not r1.lines.is_empty() else ""
		check("%s: first talk before sets falou_%s_antes" % [id, id], first != "" and f.get("falou_%s_antes" % id, false) and not f.has("falou_%s_depois" % id))
		var r2 := D.dry_run(scene, f, heroes)
		check("%s: second talk before is the short repeat" % id, not r2.lines.is_empty() and r2.lines[0].id != first and r2.lines.size() == 1 and r2.lines[0].speaker == id)
		f["sineiro_morto"] = true
		var r3 := D.dry_run(scene, f, heroes)
		check("%s: first talk after sets falou_%s_depois" % [id, id], not r3.lines.is_empty() and f.get("falou_%s_depois" % id, false))
		var r4 := D.dry_run(scene, f, heroes)
		if id == "berta":
			check("berta: second talk after is the king clue", f.get("falou_berta_rei", false) and r4.lines[-1].id == "r02")
			r4 = D.dry_run(scene, f, heroes)
		check("%s: later talks after are the short repeat" % id, r4.lines.size() == 1 and r4.lines[0].speaker == id and r4.lines[0].id != r3.lines[0].id)
		if id == "irene":
			check("irene heals only after the Sineiro", not "heal" in r1.events and not "heal" in r2.events and "heal" in r3.events and "heal" in r4.events)
	var fd := {}
	D.dry_run("loja_dora", fd, heroes)
	D.dry_run("loja_dora", fd, heroes)
	fd["sineiro_morto"] = true
	D.dry_run("loja_dora", fd, heroes)
	check("dora: greeting sets falou_dora_antes and falou_dora_depois", fd.get("falou_dora_antes", false) and fd.get("falou_dora_depois", false))
	var ft := {}
	var t1 := D.dry_run("capela_tobias", ft, heroes)
	check("tobias before the fight: one narration, the slice does not end", t1.lines.size() == 1 and t1.lines[0].speaker == "narrador" and not VR.ending_ready(ft))
	var t1b := D.dry_run("capela_tobias", ft, heroes)
	check("tobias before the fight: the second visit is another short narration", t1b.lines.size() == 1 and t1b.lines[0].speaker == "narrador" and t1b.lines[0].id != t1.lines[0].id and not VR.ending_ready(ft))
	check("the ! sits on the church door before the fight", VR.mark_at(ft) == VR.CHURCH)
	ft["sineiro_morto"] = true
	check("after the fight the ! moves to Tobias", VR.mark_at(ft) == VR.NPCS.tobias.at)
	var t2 := D.dry_run("capela_tobias", ft, heroes)
	check("tobias after the fight: the closing talk sets tobias_visto and the end card is ready", t2.lines.size() == 9 and ft.get("tobias_visto", false) and VR.ending_ready(ft) and VR.mark_at(ft) == Vector2.ZERO)
	ft["fatia_concluida"] = true
	check("after the end card, Tobias is only the short line", not VR.ending_ready(ft) and D.dry_run("capela_tobias", ft, heroes).lines.size() == 1)
	check("the end card is not ready before Tobias (all residents heard)", not VR.ending_ready({"sineiro_morto": true, "falou_hugo_depois": true, "exame_depois_aldo": true}))
	# lugares
	var spots := VR.spots({}, [])
	var lamps := (D.load_json("res://scripts/valmor_lights.json") as Array).filter(func(l): return not l.has("flicker"))
	var reach := VR.RANGE / VR.ZOOM
	var solids := []
	for c in VR.CHEST_AT:
		solids.append(VR.solid_rect(VR.CHEST_AT[c]))
	for id in VR.NPCS:
		solids.append(VR.solid_rect(VR.NPCS[id].at, true, VR.NPCS[id].has("lying")))
	for sp in spots:
		var stand: Vector2 = sp.at + Vector2(0, 8 if sp.kind == "npc" else 5)    # o líder fala de baixo
		var free := not VR.wall(stand) and solids.all(func(r): return not r.has_point(VR.to_world(stand)))
		check("%s: on the ground, reachable from below and within reach" % sp.id, not VR.wall(sp.at) and free and VR.nearest(spots, stand).get("id", "") == sp.id)
		var clash := spots.filter(func(o): return o.id != sp.id and o.at.distance_to(sp.at) < 2.0 * reach)
		check("%s: no other spot overlaps its reach %s" % [sp.id, clash.map(func(o): return o.id)], clash.is_empty())
	for id in VR.NPCS:
		var lit := lamps.filter(func(l): return Vector2(l.x, l.y).distance_to(VR.NPCS[id].at) < float(l.radius) / VR.ZOOM)
		check("%s stands outside the lamp lights" % id, lit.is_empty())
	var start := VR.to_world(VR.START)
	check("party start and church door are free of solids", solids.all(func(r): return not r.has_point(start) and not r.has_point(VR.to_world(VR.CHURCH))))
	var road := [Vector2(345, 262), Vector2(345, 238), Vector2(298, 238), Vector2(345, 238), Vector2(362, 200), Vector2(380, 152)]
	var cut := []
	for i in road.size() - 1:
		for k in 41:
			var p: Vector2 = road[i].lerp(road[i + 1], k / 40.0)
			if solids.any(func(r): return r.has_point(VR.to_world(p))):
				cut.append(p.round())
	check("no resident or chest stands on the road to the church and to the north (%s)" % [cut], cut.is_empty())
	check("after the fight the church door no longer answers", VR.spots({"sineiro_morto": true}, []).all(func(s): return s.id != "igreja"))
	check("residents turn to face the leader", VR.face_toward(Vector2.ZERO, Vector2(10, 2)) == "east" and VR.face_toward(Vector2.ZERO, Vector2(-1, -9)) == "north" and VR.face_toward(Vector2.ZERO, Vector2(0, 3)) == "south")
	check("spawn: a walkable saved spot is kept", VR.spawn(start + Vector2(6, 0)) == start + Vector2(6, 0) and VR.spawn(VR.to_world(VR.CHURCH)) == VR.to_world(VR.CHURCH))
	check("spawn: inside a wall, off the map, huge, zero or not finite goes to the start",
		[Vector2(400, 400), Vector2(9000, 9000), Vector2(1e30, -1e30), Vector2.ZERO, Vector2(INF, 0), Vector2(NAN, NAN), VR.to_world(VR.NPCS.hugo.at)].all(func(p): return VR.spawn(p) == start))
	check("spawn: the start itself is walkable", not VR.blocked(start) and not VR.blocked(VR.to_world(VR.CHURCH)))
	var g := SV.new_game()
	g.flags = {"falou_hugo_antes": true, "falou_berta_rei": true, "tobias_visto": true}
	check("resident flags go into the save", SV.parse(SV.pack(g, SV.default_options())).game.flags == g.flags)
