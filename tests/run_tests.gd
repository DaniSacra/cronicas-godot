extends SceneTree
## Testes de lógica pura. Rodar: godot --headless --path . --script tests/run_tests.gd
const C := preload("res://scripts/controls.gd")
const R := preload("res://scripts/battle_rules.gd")
const U := preload("res://scripts/ui.gd")
const F := preload("res://scripts/fx.gd")
const D := preload("res://scripts/dialogue_rules.gd")
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
	check("holy doubles against the undead", R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, true) == 2 * R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, false))
	check("heal amount", R.heal_amount(R.SKILLS.cura, 10) == 40)
	check("boss cycle: hit, drain, hit, bell", [R.boss_move(0, false), R.boss_move(1, false), R.boss_move(2, false), R.boss_move(3, false)] == ["hit", "drain", "hit", "bell"])
	check("enraged boss rings the bell more often", R.boss_move(2, true) == "bell")
	check("enraged boss hits harder", R.boss_atk(24, true) > R.boss_atk(24, false))
	check("cannot pay without enough energy", not R.can_pay(R.SKILLS.golpe, 0, 10) and R.can_pay(R.SKILLS.golpe, 0, 20))
	# combo
	check("combo points are capped", R.combo_gain(7, 3) == R.COMBO_MAX and R.combo_gain(0) == 1)
	check("combo needs enough points", not R.combo_ready("corte", 2, ["aldo", "andilla"]) and R.combo_ready("corte", 3, ["aldo", "andilla"]))
	check("combo needs both members alive", not R.combo_ready("corte", 8, ["aldo"]) and R.combo_ready("escudo", 4, ["teo", "lyra", "aldo"]))
	check("combo damage beats one plain hit", R.combo_damage(25, 20, 25) > R.phys_dmg(25, 25))
	check("shield combo heals 40 percent", R.combo_heal(50) == 20)
	check("boss forecast follows the cycle", R.boss_forecast(R.boss_state()) == ["hit", "drain", "hit"])
	_forecast_tests()
	_scene_rules_tests()
	_ui_tests()
	_font_tests()
	_touch_tests()
	_dialogue_tests()
	_dialogue_data_tests()
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
	check("bell example: 20 raw vs res 21 is 16, enraged 19", R.bell_damage(21, false) == 16 and R.bell_damage(21, true) == 19)
	check("drain example: 24 raw vs res 7", R.drain_damage(7) == R.mag_dmg(24, 7))
	check("boss hit uses its atk and fury", R.boss_hit_damage(37, false) == R.phys_dmg(30, 37) and R.boss_hit_damage(37, true) == R.phys_dmg(37.5, 37))
	check("defending halves damage, never below 1", R.taken(21, true) == 10 and R.taken(1, true) == 1 and R.taken(21, false) == 21)
	check("energy: attack +15, defend +10, capped at 100", R.energy_after("aldo", 10, "attack") == 25 and R.energy_after("andilla", 95, "defend") == 100)
	check("energy: only Aldo gains when hurt, mages have none", R.energy_after("aldo", 10, "hurt") == 18 and R.energy_after("andilla", 10, "hurt") == 10 and R.energy_after("lyra", 0, "attack") == 0)
	check("full charge adds 30 percent, none adds nothing", R.charged(70, 1.0) == 91 and R.charged(70, 0.0) == 70)
	var p := {}
	for id in R.ORDER:
		p[id] = {"hp": R.stat(id, 4, "hp"), "hpmax": R.stat(id, 4, "hp"), "mp": R.stat(id, 4, "mp"), "en": 10}
	check("auto: Lyra opens with her first spell, Aldo without energy attacks", R.auto_choice("lyra", p, 0) == {"type": "skill", "id": "fogo"} and R.auto_choice("aldo", p, 0) == {"type": "attack"})
	p.aldo.hp = 10
	check("auto: Teo heals the hurt hero", R.auto_choice("teo", p, 0) == {"type": "skill", "id": "cura", "target": "aldo"})
	p.lyra.hp = 10
	check("auto: shield with two hurt and enough points", R.auto_choice("andilla", p, R.COMBOS.escudo.cost).id == "escudo")
	p.andilla.hp = 0
	check("auto: no Double Cut with Andilla down", R.auto_choice("aldo", p, 8).get("id", "") != "corte")

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
	var font := load("res://assets/ui/PixelifySans.ttf") as FontFile
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
	check("pause menu: desktop has all three items", U.pause_items(false, false) == ["Continuar", "Tela cheia", "Sair"])
	check("pause menu: no Quit on the web", U.pause_items(true, false) == ["Continuar", "Tela cheia"])
	check("pause menu: phone has only Continue", U.pause_items(false, true) == ["Continuar"])
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
