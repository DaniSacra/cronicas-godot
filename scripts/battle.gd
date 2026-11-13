extends Node2D
## Batalha lateral contra o Sineiro (chefe do Prólogo). Regras em BattleRules; aqui só cena, animação e menus.
## --auto: os heróis jogam sozinhos, em velocidade alta, para autoteste e balanceamento.

const R := preload("res://scripts/battle_rules.gd")
const CROP := Rect2(100, 56, 486, 273)             # a arte útil dentro da imagem gerada
const ZOOM := 640.0 / 486.0
const ORDER := ["aldo", "lyra", "teo", "andilla"]
# Visão de baixo para cima, como em Sea of Stars: o grupo na parte de baixo, o chefe no alto à direita, o piso visto de cima.
const HOME := {"aldo": Vector2(340, 224), "andilla": Vector2(304, 260), "teo": Vector2(268, 234), "lyra": Vector2(234, 266)}
const BOSS_POS := Vector2(452, 200)
const FOE_SPOT := Vector2(-42, 30)           # onde o herói para diante do chefe, ao atacar
const BAR_H := 78
const BELL_RAW := 20.0
const DRAIN_RAW := 24.0
const CINE_BAR := 30.0
const DIM := Color(0.07, 0.08, 0.15)
const NORMAL_TINT := Color(0.82, 0.86, 1.0)
const HERO_SCALE := 0.74                   # Sea of Stars usa personagens bem pequenos
const BOSS_SCALE := 1.0
const HAND := Vector2(22, -32)             # mão de quem conjura
const BOSS_HIT := BOSS_POS + Vector2(-8, -46)      # onde o golpe acerta o chefe
const BOSS_FEET := BOSS_POS + Vector2(-8, -18)     # base dos efeitos de chão (gelo, luz)
const DESC := {"attack": "Ataque básico. Enche a energia.", "magic": "Magias do herói.", "tech": "Técnicas de combate.", "defend": "Reduz o dano e recupera energia.",
	"golpe": "Golpe pesado. Segure A para reforçar.", "golpeBaixo": "Some nas sombras e ataca por trás.", "fogo": "Bola de fogo contra um inimigo.",
	"gelo": "Lascas de gelo do chão.", "cura": "Restaura PV de um único aliado.", "luz": "Raio sagrado. Segure A para reforçar."}
const CHARGE_TIME := 1.0
const CHARGE_BONUS := 0.3                  # dano extra com a carga cheia
const SPECIAL := ["luz", "golpe", "golpeBaixo"]     # só as habilidades muito especiais escurecem a tela
const SKILL_COLOR := {"golpe": Color("#ffc060"), "golpeBaixo": Color("#c890ff"), "fogo": Color("#ff9040"),
	"gelo": Color("#90d8ff"), "cura": Color("#80ffb0"), "luz": Color("#fff0a0")}

signal choice_made(choice: Dictionary)

var actors := {}                   # id -> dicionário do herói em batalha
var boss := {}
var cam: Camera2D
var log_label: Label
var menu_box: VBoxContainer
var cards := {}
var combo := 0
var gem_label: Label
var gem_style: StyleBoxFlat
var forecast: Node2D
var turn_ring: Node2D
var turn_light: PointLight2D
var top_panel: PanelContainer
var menu_anchor := Vector2(380, 160)
var pools: Array = []
var result_panel: PanelContainer
var turn := 0
var rounds := 0
var auto := false
var shot_path := ""
var shot_frame := 60
var frames_seen := 0
var glows: Array = []
var t := 0.0
var mod: CanvasModulate
var bar_panel: Control
var menu_panel: PanelContainer
var top_bar: ColorRect
var bot_bar: ColorRect
var banner: Label
var demo := ""
var demo_t0 := -1.0
var shot_times: Array = []
var shot_idx := 0

func _ready() -> void:
	y_sort_enabled = true
	auto = "--auto" in OS.get_cmdline_user_args()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="): shot_path = a.substr(7)
		if a.begins_with("--shotframe="): shot_frame = int(a.substr(12))
		if a.begins_with("--demo="): demo = a.substr(7)
		if a.begins_with("--shots="):
			for x in a.substr(8).split(","): shot_times.append(float(x))
	if auto:
		Engine.time_scale = 12.0
	elif "--fast" in OS.get_cmdline_user_args():
		Engine.time_scale = 6.0
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.06))
	mod = CanvasModulate.new()
	mod.color = NORMAL_TINT
	add_child(mod)
	_build_stage()
	_build_ui()
	cam = Camera2D.new()
	cam.position = Vector2(320, 180)
	add_child(cam)
	_run()

# ---------- cenário ----------

func _build_stage() -> void:
	var bg := Sprite2D.new()
	bg.texture = load("res://assets/battle/arena2_bg.png")
	bg.centered = false
	bg.region_enabled = true
	bg.region_rect = CROP
	bg.scale = Vector2(ZOOM, ZOOM)
	bg.z_index = -100
	add_child(bg)
	# luzes: velas, lanternas, o veio verde da parede e o brilho do próprio Sineiro
	glows.append({"n": Fx.make_light(self, Vector2(257, 30), Color("#40ffb0"), 1.1, 150), "base": 1.1, "f": 0.1})
	for c in [Vector2(230, 65), Vector2(385, 55), Vector2(511, 84), Vector2(531, 292), Vector2(7, 222)]:
		glows.append({"n": Fx.make_light(self, c, Color("#ffb060"), 0.9, 70), "base": 0.9, "f": 0.22})
	for c in [Vector2(270, 311), Vector2(424, 306)]:
		glows.append({"n": Fx.make_light(self, c, Color("#ff9a40"), 1.3, 100), "base": 1.3, "f": 0.18})
	glows.append({"n": Fx.make_light(self, BOSS_POS + Vector2(-16, -64), Color("#9fd8ff"), 0.55, 120), "base": 0.55, "f": 0.15})

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Fx.sineiro_frames()
	sprite.centered = false
	sprite.offset = Vector2(-64, -120)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	sprite.play("stance")
	var root := Node2D.new()
	root.position = BOSS_POS
	var sh := Sprite2D.new()
	sh.texture = Fx.shadow_texture()
	sh.scale = Vector2(1.3, 0.35)
	root.scale = Vector2(BOSS_SCALE, BOSS_SCALE)
	sh.z_index = -1
	root.add_child(sh)
	root.add_child(sprite)
	forecast = Node2D.new()
	forecast.position = Vector2(-10, -128)
	forecast.z_index = 60
	root.add_child(forecast)
	add_child(root)
	boss = {"root": root, "sprite": sprite, "hp": R.SINEIRO.hp, "hpmax": R.SINEIRO.hp, "home": BOSS_POS}

	for id in ORDER:
		var d: Dictionary = Game.party[id]
		var hr := Node2D.new()
		hr.position = HOME[id]
		var shd := Sprite2D.new()
		shd.texture = Fx.shadow_texture()
		shd.scale = Vector2(0.55, 0.22) * HERO_SCALE / 0.74 * 0.8
		shd.z_index = -1
		hr.add_child(shd)
		var sp := AnimatedSprite2D.new()
		sp.sprite_frames = Fx.hero_frames(id)
		sp.centered = false
		sp.scale = Vector2(HERO_SCALE, HERO_SCALE)
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # a escala não é inteira: filtro suave evita pixels desiguais
		sp.offset = Vector2(-28, -66)
		hr.add_child(sp)
		_play({"id": id, "sprite": sp}, "stance")
		sp.frame = randi() % 4
		add_child(hr)
		var hpmax := R.stat(id, d.lv, "hp")
		actors[id] = {"id": id, "root": hr, "sprite": sp, "lv": d.lv, "hp": mini(d.hp, hpmax), "hpmax": hpmax,
			"mp": d.mp, "mpmax": R.stat(id, d.lv, "mp"), "en": R.ENERGY.start if R.HEROES[id].energy else 0,
			"defending": false, "home": HOME[id], "def": R.stat(id, d.lv, "def"), "res": R.stat(id, d.lv, "res"),
			"atk": R.stat(id, d.lv, "atk"), "mag": R.stat(id, d.lv, "mag")}
	turn_ring = Node2D.new()
	turn_ring.z_index = -1
	turn_ring.hide()
	var ring_line := Line2D.new()
	var rpts := PackedVector2Array()
	for i in 41:
		rpts.append(Vector2(cos(TAU * i / 40.0) * 22.0, sin(TAU * i / 40.0) * 9.0))
	ring_line.points = rpts
	ring_line.width = 1.6
	ring_line.default_color = Color(1, 1, 1, 0.95)
	ring_line.material = Vfx.add_mat()
	turn_ring.add_child(ring_line)
	turn_light = Fx.make_light(turn_ring, Vector2(0, -6), Color.WHITE, 1.0, 62)
	add_child(turn_ring)

# ---------- interface ----------

func _flat(color: Color, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(2)
	return s

func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 6)
	b.add_theme_stylebox_override("background", _flat(Color(0.1, 0.1, 0.16)))
	b.add_theme_stylebox_override("fill", _flat(color))
	return b

func _build_cine() -> void:
	var low := CanvasLayer.new()
	low.layer = 4
	add_child(low)
	top_bar = ColorRect.new()
	top_bar.color = Color.BLACK
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 0
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low.add_child(top_bar)
	bot_bar = ColorRect.new()
	bot_bar.color = Color.BLACK
	bot_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bot_bar.offset_top = 0
	bot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	low.add_child(bot_bar)
	var hi := CanvasLayer.new()
	hi.layer = 6
	add_child(hi)
	banner = Label.new()
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = 42
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	banner.add_theme_constant_override("outline_size", 7)
	banner.modulate.a = 0.0
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hi.add_child(banner)

func _build_ui() -> void:
	_build_cine()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	log_label = Label.new()
	log_label.custom_minimum_size = Vector2(380, 0)
	log_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	log_label.add_theme_font_size_override("font_size", 12)
	top_panel = PanelContainer.new()
	top_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	top_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top_panel.offset_top = 8
	top_panel.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.05, 0.12, 0.85), Color(0.55, 0.65, 0.95, 0.7), 1))
	top_panel.add_child(log_label)
	top_panel.hide()
	root.add_child(top_panel)

	# HUD à moda de Sea of Stars: cartas pequenas com retrato no canto, menu flutuante do outro lado
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hud)
	bar_panel = hud
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.offset_left = 6
	stack.offset_bottom = -6
	stack.add_theme_constant_override("separation", 3)
	hud.add_child(stack)
	for id in ORDER:
		var hero_col := Color(R.HEROES[id].color)
		var panel := PanelContainer.new()
		var st := _flat(Color(0.04, 0.05, 0.12, 0.82), Color(hero_col, 0.55), 1)
		st.set_content_margin_all(3)
		panel.add_theme_stylebox_override("panel", st)
		stack.add_child(panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		panel.add_child(row)
		var face := TextureRect.new()
		face.texture = Fx.face_texture(id)
		face.custom_minimum_size = Vector2(30, 30)
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		row.add_child(face)
		var v := VBoxContainer.new()
		v.custom_minimum_size = Vector2(120, 0)
		v.add_theme_constant_override("separation", 1)
		row.add_child(v)
		var name_l := Label.new()
		name_l.add_theme_font_size_override("font_size", 12)
		name_l.add_theme_color_override("font_color", hero_col)
		v.add_child(name_l)
		var nums := HBoxContainer.new()
		v.add_child(nums)
		var hp_l := Label.new()
		hp_l.add_theme_font_size_override("font_size", 12)
		hp_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nums.add_child(hp_l)
		var rs_l := Label.new()
		rs_l.add_theme_font_size_override("font_size", 12)
		nums.add_child(rs_l)
		var hp_b := _bar(Color("#e0a050"))
		hp_b.custom_minimum_size = Vector2(0, 4)
		v.add_child(hp_b)
		var rs_b := _bar(Color("#f0c850") if R.HEROES[id].energy else Color("#b060e0"))
		rs_b.custom_minimum_size = Vector2(0, 4)
		v.add_child(rs_b)
		cards[id] = {"panel": panel, "style": st, "name": name_l, "hp_l": hp_l, "hp_b": hp_b, "rs_l": rs_l, "rs_b": rs_b}
	var gem := Control.new()
	gem.custom_minimum_size = Vector2(0, 60)
	stack.add_child(gem)
	stack.move_child(gem, 0)
	var gem_box := Panel.new()
	gem_box.size = Vector2(28, 28)
	gem_box.position = Vector2(20, 6)
	gem_box.pivot_offset = Vector2(14, 14)
	gem_box.rotation = PI / 4.0
	gem_style = _flat(Color(0.05, 0.06, 0.14, 0.9), Color(0.7, 0.55, 0.9), 2)
	gem_box.add_theme_stylebox_override("panel", gem_style)
	gem.add_child(gem_box)
	gem_label = Label.new()
	gem_label.position = Vector2(14, 0)
	gem_label.size = Vector2(40, 40)
	gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gem_label.add_theme_font_size_override("font_size", 12)
	gem.add_child(gem_label)
	var gem_title := Label.new()
	gem_title.text = "COMBO"
	gem_title.position = Vector2(6, 42)
	gem_title.add_theme_font_size_override("font_size", 12)
	gem.add_child(gem_title)
	_update_gem()
	menu_panel = PanelContainer.new()
	menu_panel.add_theme_stylebox_override("panel", _flat(Color(0.04, 0.05, 0.12, 0.88), Color(0.55, 0.65, 0.95, 0.8), 1))
	menu_panel.hide()
	hud.add_child(menu_panel)
	menu_box = VBoxContainer.new()
	menu_box.custom_minimum_size = Vector2(112, 0)
	menu_box.add_theme_constant_override("separation", 2)
	menu_panel.add_child(menu_box)
	_update_cards()

func _update_gem() -> void:
	gem_label.text = str(combo)
	var ready: bool = combo >= int(R.COMBOS.corte.cost)
	gem_style.border_color = Color("#ffd060") if ready else Color(0.7, 0.55, 0.9)
	gem_style.bg_color = Color(0.05, 0.06, 0.14, 0.9).lerp(Color("#7a4cc0"), float(combo) / R.COMBO_MAX)

func _add_combo(n := 1) -> void:
	combo = R.combo_gain(combo, n)
	_update_gem()

## Os próximos golpes do chefe aparecem acima dele (G golpe, D dobre, B badalada).
func _update_forecast() -> void:
	for ch in forecast.get_children():
		ch.queue_free()
	var frac: float = float(boss.hp) / float(boss.hpmax)
	var moves := R.boss_forecast(turn, frac)
	var look := {"hit": ["G", Color("#d85a5a")], "drain": ["D", Color("#a060d8")], "bell": ["B", Color("#e8c050")]}
	for i in moves.size():
		var spec: Array = look[moves[i]]
		var box := ColorRect.new()
		var sz := 18.0 if i == 0 else 13.0
		box.size = Vector2(sz, sz)
		box.position = Vector2(-27.0 + i * 20.0, -sz / 2.0)
		box.color = Color(spec[1], 1.0 if i == 0 else 0.7)
		var l := Label.new()
		l.text = spec[0]
		l.size = box.size
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 10 if i == 0 else 8)
		l.add_theme_color_override("font_color", Color(0.05, 0.03, 0.08))
		box.add_child(l)
		forecast.add_child(box)

func _mark_active(id: String) -> void:
	for k in ORDER:
		var st: StyleBoxFlat = cards[k].style
		var on: bool = k == id
		st.set_border_width_all(2 if on else 1)
		st.border_color = Color(R.HEROES[k].color, 1.0 if on else 0.55)

func _update_cards() -> void:
	for id in ORDER:
		var a: Dictionary = actors[id]
		var c: Dictionary = cards[id]
		c.name.text = R.HEROES[id].name
		c.hp_l.text = "PV %d/%d" % [a.hp, a.hpmax]
		c.hp_b.max_value = a.hpmax
		c.hp_b.value = a.hp
		var energy: bool = R.HEROES[id].energy
		c.rs_l.text = ("EN %d" % a.en) if energy else ("PM %d/%d" % [a.mp, a.mpmax])
		c.rs_b.max_value = R.ENERGY.max if energy else maxi(1, a.mpmax)
		c.rs_b.value = a.en if energy else a.mp
		c.panel.modulate = Color(1, 1, 1, 1.0 if a.hp > 0 else 0.45)

func _clear_menu() -> void:
	for ch in menu_box.get_children():
		ch.queue_free()
	menu_panel.hide()

func _button(text: String, cb: Callable, disabled := false, desc := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 22)
	b.add_theme_font_size_override("font_size", 12)
	b.disabled = disabled
	b.pressed.connect(cb)
	if desc != "":
		b.focus_entered.connect(func(): log_label.text = desc)
	menu_box.add_child(b)
	menu_panel.position = Vector2(clampf(menu_anchor.x, 150.0, 640.0 - 122.0), clampf(menu_anchor.y, 36.0, 360.0 - 110.0))
	menu_panel.show()
	return b

func _main_menu(h: Dictionary) -> void:
	_clear_menu()
	var first := _button("Atacar", func(): choice_made.emit({"type": "attack"}), false, DESC.attack)
	var word := "Técnica" if R.HEROES[h.id].energy else "Magia"
	_button(word, func(): _skill_menu(h), false, DESC.tech if R.HEROES[h.id].energy else DESC.magic)
	_button("Combo  %d" % combo, func(): _combo_menu(h), combo < int(R.COMBOS.corte.cost), "Golpes em dupla. Gastam pontos de combo.")
	_button("Defender", func(): choice_made.emit({"type": "defend"}), false, DESC.defend)
	first.grab_focus.call_deferred()

func _combo_menu(h: Dictionary) -> void:
	_clear_menu()
	var first: Button = null
	for cid in R.COMBOS:
		var cb: Dictionary = R.COMBOS[cid]
		var ok := R.combo_ready(cid, combo, _alive())
		var b := _button("%s  %d PC" % [cb.name, cb.cost], func(): choice_made.emit({"type": "combo", "id": cid}), not ok, cb.desc)
		if first == null and not b.disabled:
			first = b
	var back := _button("Voltar", func(): _main_menu(h))
	(first if first != null else back).grab_focus.call_deferred()

func _skill_menu(h: Dictionary) -> void:
	_clear_menu()
	var first: Button = null
	for sid in R.HEROES[h.id].skills:
		var s: Dictionary = R.SKILLS[sid]
		var unit := "PM" if s.cost_kind == "mp" else "EN"
		var ok := R.can_pay(s, h.mp, h.en)
		var b := _button("%s  %d %s" % [s.name, s.cost, unit], func(): _after_skill_pick(h, sid), not ok, DESC.get(sid, ""))
		if first == null and not b.disabled:
			first = b
	var back := _button("Voltar", func(): _main_menu(h))
	(first if first != null else back).grab_focus.call_deferred()

func _after_skill_pick(h: Dictionary, sid: String) -> void:
	if R.SKILLS[sid].target == "ally":
		_clear_menu()
		var first: Button = null
		for id in ORDER:
			var a: Dictionary = actors[id]
			if a.hp <= 0:
				continue
			var b := _button("%s  %d/%d" % [R.HEROES[id].name, a.hp, a.hpmax], func(): choice_made.emit({"type": "skill", "id": sid, "target": id}))
			if first == null:
				first = b
		_button("Voltar", func(): _skill_menu(h))
		first.grab_focus.call_deferred()
	else:
		choice_made.emit({"type": "skill", "id": sid})

# ---------- laço da batalha ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _say(text: String, sec := 1.0) -> void:
	log_label.text = text
	await _wait(sec)

func _alive() -> Array:
	return ORDER.filter(func(id): return actors[id].hp > 0)

func _demo() -> void:
	await _wait(0.6)
	var hid := "aldo"
	var choice := {"type": "attack"}
	if demo == "defend":
		hid = "lyra"
		choice = {"type": "defend"}
	elif demo in R.COMBOS:
		hid = "aldo"
		combo = 8
		choice = {"type": "combo", "id": demo}
		for id in ["aldo", "lyra", "teo"]:
			actors[id].hp = maxi(1, actors[id].hp - 30)
	elif demo != "attack":
		for id in ORDER:
			if demo in R.HEROES[id].skills:
				hid = id
		choice = {"type": "skill", "id": demo, "target": "aldo"}
		actors.aldo.hp = maxi(1, actors.aldo.hp - 40)
	demo_t0 = t
	await _execute(actors[hid], choice)
	await _wait(0.6)
	get_tree().quit()

func _run() -> void:
	_update_forecast()
	if demo != "":
		await _demo()
		return
	await _wait(0.5)
	await _say("O Sineiro ergue o sino de bronze. Em algum lugar acima, a terra das covas estremece.", 2.0)
	await _say("\"O último toque foi há cinquenta anos. Ninguém mais desce.\"", 2.0)
	while true:
		rounds += 1
		for id in ORDER:
			if actors[id].hp > 0 and boss.hp > 0:
				await _hero_turn(actors[id])
		if boss.hp <= 0:
			break
		await _boss_turn()
		if _alive().is_empty():
			break
	await _finish()

func _hero_turn(h: Dictionary) -> void:
	h.defending = false
	if h.sprite.animation == "defend":
		_play(h, "stance")
	_mark_active(h.id)
	turn_ring.position = h.root.position + Vector2(0, 3)
	turn_light.color = Color(R.HEROES[h.id].color).lerp(Color.WHITE, 0.3)
	turn_ring.show()
	menu_anchor = h.root.position + Vector2(38, -62)
	var choice: Dictionary
	if auto:
		choice = _auto_choice(h)
	else:
		log_label.text = "Vez de %s." % R.HEROES[h.id].name
		_main_menu(h)
		choice = await choice_made
	turn_ring.hide()
	_clear_menu()
	await _execute(h, choice)

func _auto_choice(h: Dictionary) -> Dictionary:
	var weak := _alive().filter(func(id): return actors[id].hp < actors[id].hpmax * 0.6)
	if weak.size() >= 2 and R.combo_ready("escudo", combo, _alive()):
		return {"type": "combo", "id": "escudo"}
	if R.combo_ready("corte", combo, _alive()):
		return {"type": "combo", "id": "corte"}
	var hurt := _alive().filter(func(id): return actors[id].hp < actors[id].hpmax * 0.45)
	for sid in R.HEROES[h.id].skills:
		var s: Dictionary = R.SKILLS[sid]
		if not R.can_pay(s, h.mp, h.en):
			continue
		if s.kind == "heal":
			if not hurt.is_empty():
				return {"type": "skill", "id": sid, "target": hurt[0]}
			continue
		return {"type": "skill", "id": sid}
	return {"type": "attack"}

func _gain(h: Dictionary, n: int) -> void:
	if R.HEROES[h.id].energy:
		h.en = mini(R.ENERGY.max, h.en + n)

func _play(h: Dictionary, anim: String, flip := false) -> void:
	var sp: AnimatedSprite2D = h.sprite
	if sp.sprite_frames.get_frame_count(anim) == 0:
		anim = "idle"
	sp.flip_h = flip
	sp.offset = Fx.anim_offset(anim, h.get("id", ""))
	sp.play(anim)

## Abre a cena de habilidade: faixas de cinema, fundo escurecido, nome da técnica e câmera no foco.
func _cine_begin(title: String, color: Color, special := false) -> void:
	log_label.text = ""
	banner.text = title
	banner.add_theme_color_override("font_color", color)
	var tw := create_tween().set_parallel(true)
	if special:
		tw.tween_property(mod, "color", DIM, 0.35)
		_light_pools()
	tw.tween_property(banner, "modulate:a", 1.0, 0.25)
	await tw.finished

## Cena escura de habilidade especial: cada herói fica numa poça de luz da própria cor.
func _light_pools() -> void:
	for id in ORDER:
		if actors[id].hp <= 0:
			continue
		var pool := Fx.make_light(self, actors[id].root.position + Vector2(0, 2), Color(R.HEROES[id].color), 0.0, 78)
		create_tween().tween_property(pool, "energy", 2.2, 0.35)
		pools.append(pool)

## Segurar o botão carrega o golpe: devolve de 0 a 1 (no automático, sempre carga cheia).
func _charge(h: Dictionary, col: Color) -> float:
	log_label.text = "Segure A para reforçar!"
	var orb := Sprite2D.new()
	orb.texture = Fx.light_texture()
	orb.material = Vfx.add_mat()
	orb.modulate = col
	orb.scale = Vector2.ONE * 0.04
	orb.position = h.root.position + HAND
	orb.z_index = 77
	add_child(orb)
	var glow := Fx.make_light(self, orb.position, col, 0.5, 80)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(orb, "scale", Vector2.ONE * 0.38, CHARGE_TIME)
	tw.tween_property(glow, "energy", 2.6, CHARGE_TIME)
	var held := 0.0
	var step := 0.05
	for i in int(CHARGE_TIME / step):
		await _wait(step)
		if auto or demo != "" or Input.is_action_pressed("confirm"):
			held += step
	orb.queue_free()
	glow.queue_free()
	log_label.text = ""
	return clampf(held / CHARGE_TIME, 0.0, 1.0)

func _cine_end() -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(mod, "color", NORMAL_TINT, 0.3)
	tw.tween_property(banner, "modulate:a", 0.0, 0.2)
	for pool in pools:
		tw.tween_property(pool, "energy", 0.0, 0.3)
	await tw.finished
	for pool in pools:
		pool.queue_free()
	pools.clear()

func _impact(h: Dictionary) -> void:
	if h.id == "aldo" or h.id == "andilla":
		Vfx.sword_hit(self, BOSS_HIT)
	else:
		Vfx.glow(self, BOSS_HIT, Color(1, 0.95, 0.8, 1), 130.0, 0.25, 1.4)
		Vfx.sparks(self, BOSS_HIT, Color(1, 0.95, 0.8, 1), 14, 130.0, 0.4, Vector2(0, 200), 2.0)

func _trail(h: Dictionary, n: int) -> void:
	for i in n:
		Vfx.afterimage(self, h.sprite, Color("#c890ff"))
		await _wait(0.05)

func _execute(h: Dictionary, c: Dictionary) -> void:
	var name_: String = R.HEROES[h.id].name
	match c.type:
		"defend":
			h.defending = true
			_add_combo()
			_gain(h, R.ENERGY.defend)
			_update_cards()
			log_label.text = "%s se defende." % name_
			_play(h, "defend")
			Vfx.ring(self, h.root.position + Vector2(0, 2), Color(0.5, 0.75, 1.0, 0.9), 10.0, 38.0, 0.5)
			Vfx.glow(self, h.root.position + Vector2(0, -24), Color(0.5, 0.75, 1.0, 0.6), 110.0, 0.5, 1.3)
			await _wait(0.9)
		"attack":
			log_label.text = "%s ataca o Sineiro!" % name_
			await _lunge(h)
			_play(h, "attack")
			await _wait(0.32)
			var dmg := R.phys_dmg(h.atk, R.SINEIRO.def, 1.0, randf_range(0.88, 1.12))
			_gain(h, R.ENERGY.attack)
			_add_combo()
			_impact(h)
			await _hit_boss(dmg, Color.WHITE, Color(1, 1, 1))
			await _wait(0.15)
			await _back(h)
		"combo":
			var cb: Dictionary = R.COMBOS[c.id]
			combo -= int(cb.cost)
			_update_gem()
			if c.id == "corte":
				await _combo_corte(cb)
			else:
				await _combo_escudo(cb)
		"skill":
			var s: Dictionary = R.SKILLS[c.id]
			var col: Color = SKILL_COLOR.get(c.id, Color.WHITE)
			_add_combo()
			if s.cost_kind == "mp":
				h.mp -= s.cost
			else:
				h.en -= s.cost
			_update_cards()
			if s.kind == "heal":
				var tgt: Dictionary = actors[c.target]
				var amount := R.heal_amount(s, h.mag, randf_range(0.9, 1.1))
				await _cine_begin(s.name, col)
				_play(h, "cast")
				Vfx.magic_circle(self, h.root.position + Vector2(0, 4), col, 0.9)
				await _wait(0.5)
				Vfx.heal(self, tgt.root.position + Vector2(0, -14))
				await _wait(0.5)
				tgt.hp = mini(tgt.hpmax, tgt.hp + amount)
				_float_text(tgt.root.position + Vector2(0, -60), "+%d" % amount, Color("#70e090"))
				_update_cards()
				await _wait(0.7)
				_play(h, "stance")
				await _cine_end()
			elif s.kind == "phys":
				var dmg := R.skill_damage(s, h.atk, h.mag, R.SINEIRO.def, R.SINEIRO.res, R.SINEIRO.undead, randf_range(0.88, 1.12))
				await _cine_begin(s.name, col, c.id in SPECIAL)
				if c.id == "golpeBaixo":
					await _shadow_strike(h, dmg, col)
					await _cine_end()
					return
				else:
					dmg = int(dmg * (1.0 + CHARGE_BONUS * await _charge(h, col)))
					await _lunge(h)
					_play(h, "heavy")
					await _wait(0.5)
					Vfx.sword_hit(self, BOSS_HIT, true)
					_shake(4.0)
					await _hit_boss(dmg, col, col)
					await _wait(0.2)
				await _back(h)
				await _cine_end()
			else:
				var dmg := R.skill_damage(s, h.atk, h.mag, R.SINEIRO.def, R.SINEIRO.res, R.SINEIRO.undead, randf_range(0.88, 1.12))
				await _cine_begin(s.name, col, c.id in SPECIAL)
				Vfx.magic_circle(self, h.root.position + Vector2(0, 4), col, 1.0)
				_play(h, "cast")
				await _wait(0.45)
				match c.id:
					"fogo":
						await Vfx.fireball(self, h.root.position + HAND, BOSS_HIT)
						await _hit_boss(dmg, col, col)
					"gelo":
						Vfx.ice(self, BOSS_FEET)
						await _wait(0.3)
						await _hit_boss(dmg, col, col)
						await _wait(0.4)
					_:
						dmg = int(dmg * (1.0 + CHARGE_BONUS * await _charge(h, col)))
						Vfx.holy(self, BOSS_FEET)
						await _wait(0.5)
						await _hit_boss(dmg, col, col)
						if s.kind == "holy":
							log_label.text = "A luz queima os mortos-vivos!"
						await _wait(0.5)
				_play(h, "stance")
				await _cine_end()

## Corte Duplo: Aldo e Andilla correm juntos e cortam o chefe ao mesmo tempo.
func _combo_corte(cb: Dictionary) -> void:
	var a: Dictionary = actors.aldo
	var d: Dictionary = actors.andilla
	var col := Color("#ffb0d0")
	var dmg := R.combo_damage(a.atk, d.atk, R.SINEIRO.def, randf_range(0.9, 1.1))
	await _cine_begin(cb.name, col, true)
	_play(a, "walk")
	_play(d, "dash")
	_trail(d, 5)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(a.root, "position", _target_spot(a) + Vector2(0, -10), 0.3).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(d.root, "position", _target_spot(d) + Vector2(0, 12), 0.27).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	await tw.finished
	_play(a, "heavy")
	_play(d, "slashx")
	await _wait(0.42)
	Vfx.sword_hit(self, BOSS_HIT, true)
	Vfx.cross_slash(self, BOSS_HIT)
	_shake(7.0)
	await _hit_boss(dmg, col, col)
	await _wait(0.2)
	_back(a)
	await _back(d)
	await _cine_end()

## Escudo de Luz: Teo e Lyra conjuram, pilares de luz caem sobre todos, o grupo se cura e levanta a guarda.
func _combo_escudo(cb: Dictionary) -> void:
	var col := Color("#a8e8ff")
	await _cine_begin(cb.name, col, true)
	_play(actors.teo, "cast")
	_play(actors.lyra, "cast")
	Vfx.magic_circle(self, actors.teo.root.position + Vector2(0, 4), col, 1.0)
	Vfx.magic_circle(self, actors.lyra.root.position + Vector2(0, 4), col, 1.0)
	await _wait(0.6)
	var living := _alive()
	for id in living:
		Vfx.pillar(self, actors[id].root.position, col)
		await _wait(0.12)
	await _wait(0.5)
	for id in living:
		var a: Dictionary = actors[id]
		var amount := R.combo_heal(a.hpmax)
		a.hp = mini(a.hpmax, a.hp + amount)
		a.defending = true
		_float_text(a.root.position + Vector2(0, -60), "+%d" % amount, Color("#70e090"))
	_update_cards()
	await _wait(0.9)
	_play(actors.teo, "stance")
	_play(actors.lyra, "stance")
	await _cine_end()

func _target_spot(h: Dictionary) -> Vector2:
	return BOSS_POS + FOE_SPOT + Vector2(0, (ORDER.find(h.id) - 1.5) * 7.0)

func _lunge(h: Dictionary) -> void:
	_play(h, "walk")
	var tw := create_tween()
	tw.tween_property(h.root, "position", _target_spot(h), 0.30).set_trans(Tween.TRANS_QUAD)
	await tw.finished

## Passo das Sombras (Andilla): some em fumaça, desliza como sombra, aparece atrás do chefe, corta e volta do mesmo jeito.
func _shadow_strike(h: Dictionary, dmg: int, col: Color) -> void:
	var behind := BOSS_POS + Vector2(44, -18)
	await _shadow_step(h, behind, true)
	_play(h, "slashx", true)
	await _wait(0.25)
	Vfx.cross_slash(self, BOSS_HIT)
	_shake(4.0)
	await _wait(0.1)
	await _hit_boss(dmg, col, col)
	await _wait(0.1)
	await _shadow_step(h, h.home, false)

func _shadow_step(h: Dictionary, to: Vector2, flip: bool) -> void:
	var from: Vector2 = h.root.position
	Vfx.smoke(self, from + Vector2(0, -22))
	_play(h, "defend")
	await _wait(0.15)
	h.root.visible = false
	await Vfx.shadow_streak(self, from, to, 0.4)
	h.root.position = to
	_play(h, "stance", flip)
	h.root.visible = true
	Vfx.smoke(self, to + Vector2(0, -22))

func _back(h: Dictionary) -> void:
	_play(h, "walk", true)
	var tw := create_tween()
	tw.tween_property(h.root, "position", h.home, 0.26)
	await tw.finished
	_play(h, "stance")

func _hit_boss(dmg: int, color: Color, burst: Color) -> void:
	boss.hp = maxi(0, boss.hp - dmg)
	_burst(BOSS_POS + Vector2(-8, -50), burst)
	_float_text(BOSS_POS + Vector2(-8, -100), str(dmg), color)
	_shake(3.0)
	var sp: AnimatedSprite2D = boss.sprite
	sp.modulate = Color(3, 3, 3)
	create_tween().tween_property(sp, "modulate", Color.WHITE, 0.25)
	sp.position.x = 7.0
	create_tween().tween_property(sp, "position:x", 0.0, 0.25).set_trans(Tween.TRANS_BACK)
	await _wait(0.45)

func _boss_turn() -> void:
	await _wait(0.2)
	var frac: float = float(boss.hp) / float(boss.hpmax)
	if frac < 0.4 and not boss.get("enraged", false):
		boss.enraged = true
		await _say("O Sineiro sacode o sino com fúria! \"Ninguém mais desce!\"", 1.6)
	var move := R.boss_move(turn, frac)
	turn += 1
	_update_forecast()
	var atk := R.boss_atk(R.SINEIRO.atk, frac)
	var alive := _alive()
	if move == "bell":
		_boss_anim("special")
		await _say("O Sineiro toca a Badalada! O som atravessa os ossos.", 0.8)
		_shake(5.0)
		for id in alive:
			var a: Dictionary = actors[id]
			var dmg := R.mag_dmg(BELL_RAW * randf_range(0.9, 1.1) * (1.25 if boss.get("enraged", false) else 1.0), a.res)
			await _hurt_hero(a, dmg, false)
	elif move == "drain":
		var a: Dictionary = actors[alive[randi() % alive.size()]]
		_boss_anim("special")
		await _say("O Sineiro entoa um dobre fúnebre por %s!" % R.HEROES[a.id].name, 0.8)
		var dmg := R.mag_dmg(DRAIN_RAW * randf_range(0.9, 1.1), a.res)
		await _hurt_hero(a, dmg, false)
		boss.hp = mini(boss.hpmax, boss.hp + dmg / 2)
	else:
		var a: Dictionary = actors[alive[randi() % alive.size()]]
		await _say("O Sineiro golpeia %s com o sino!" % R.HEROES[a.id].name, 0.5)
		var tw := create_tween()
		tw.tween_property(boss.root, "position", a.root.position + Vector2(56, -24), 0.34).set_trans(Tween.TRANS_QUAD)
		await tw.finished
		_boss_anim("heavy")
		await _wait(0.3)
		await _hurt_hero(a, R.phys_dmg(atk, a.def, 1.0, randf_range(0.88, 1.12)), true)
		var back := create_tween()
		back.tween_property(boss.root, "position", BOSS_POS, 0.3)
		await back.finished

## Toca uma animação do Sineiro e volta para a pose parada.
func _boss_anim(anim: String) -> void:
	var sp: AnimatedSprite2D = boss.sprite
	sp.play(anim)
	await sp.animation_finished
	sp.play("stance")

func _hurt_hero(a: Dictionary, dmg: int, single: bool) -> void:
	if a.defending:
		dmg = maxi(1, dmg / 2)
	a.hp = maxi(0, a.hp - dmg)
	if a.id == "aldo" and a.hp > 0:
		_gain(a, R.ENERGY.hurt_aldo)
	_float_text(a.root.position + Vector2(0, -60), str(dmg), Color("#ff6060"))
	_shake(2.5)
	var sp: AnimatedSprite2D = a.sprite
	_play(a, "hurt" if a.hp > 0 else "fall", not Fx.new_art(a.id))
	_update_cards()
	await _wait(0.5 if single else 0.3)
	if a.hp > 0:
		_play(a, "stance")

# ---------- efeitos ----------

func _float_text(pos: Vector2, text: String, color: Color) -> void:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.z_index = 90
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", pos.y - 28, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

func _burst(pos: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 26
	p.lifetime = 0.5
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.initial_velocity_min = 50.0
	p.initial_velocity_max = 130.0
	p.gravity = Vector2(0, 160)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 3.0
	p.color = color
	p.z_index = 70
	add_child(p)
	var l := Fx.make_light(self, pos, color, 2.0, 90)
	var tw := create_tween()
	tw.tween_property(l, "energy", 0.0, 0.35)
	tw.tween_callback(l.queue_free)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)

func _shake(power: float) -> void:
	var tw := create_tween()
	for i in 5:
		tw.tween_property(cam, "offset", Vector2(randf_range(-power, power), randf_range(-power, power)), 0.04)
	tw.tween_property(cam, "offset", Vector2.ZERO, 0.04)

# ---------- fim ----------

func _finish() -> void:
	var won: bool = boss.hp <= 0
	if won:
		var sp: AnimatedSprite2D = boss.sprite
		await _say("O Sineiro cambaleia...", 1.0)
		create_tween().tween_property(sp, "modulate:a", 0.0, 1.4)
		await _say("O Sineiro desaba. O sino rola pelas pedras, toca uma última vez e se cala.", 2.2)
		for id in ORDER:
			var d: Dictionary = Game.party[id]
			d.hp = maxi(1, actors[id].hp)
			d.mp = actors[id].mp
		Game.flags["sineiro_morto"] = true
	else:
		await _say("O sino tocou por vocês...", 2.0)
	if auto:
		print("RESULT ", "WIN" if won else "LOSE", " rounds=", rounds, " boss_hp=", boss.hp, " alive=", _alive().size())
		if "--auto-return" in OS.get_cmdline_user_args() and won:
			Engine.time_scale = 1.0
			get_tree().change_scene_to_file("res://scenes/main.tscn")
			return
		get_tree().quit()
		return
	_show_result(won)

func _show_result(won: bool) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(c)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat(Color(0.03, 0.04, 0.10, 0.94), Color(0.5, 0.6, 0.9), 2))
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := Label.new()
	title.text = "VITÓRIA" if won else "DERROTA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	var sub := Label.new()
	sub.text = "O sino de Valmor se calou." if won else "Os mortos ainda ouvem o sino."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	v.add_child(sub)
	var b := Button.new()
	b.text = "Voltar a Valmor" if won else "Tentar de novo"
	b.custom_minimum_size = Vector2(160, 30)
	b.pressed.connect(func():
		if not won:
			Game.heal_all()
		get_tree().change_scene_to_file("res://scenes/main.tscn" if won else "res://scenes/battle.tscn"))
	v.add_child(b)
	b.grab_focus.call_deferred()

func _process(delta: float) -> void:
	t += delta
	for g in glows:
		g.n.energy = g.base * (1.0 + (sin(t * 7.0 + g.base * 10.0) * 0.5 + sin(t * 19.0) * 0.5) * g.f)
	top_panel.visible = log_label.text != ""
	if turn_ring.visible:
		turn_ring.scale = Vector2.ONE * (1.0 + sin(t * 6.0) * 0.06)
	if not shot_times.is_empty():
		if demo_t0 >= 0.0 and shot_idx < shot_times.size() and t - demo_t0 >= shot_times[shot_idx]:
			get_viewport().get_texture().get_image().save_png(shot_path.replace(".png", "_%d.png" % shot_idx))
			shot_idx += 1
	elif shot_path != "":
		frames_seen += 1
		if frames_seen == shot_frame:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
