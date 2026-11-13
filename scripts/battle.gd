extends Node2D
## Batalha lateral contra o Sineiro (chefe do Prólogo). Regras em BattleRules; aqui só cena, animação e menus.
## --auto: os heróis jogam sozinhos, em velocidade alta, para autoteste e balanceamento.

const R := preload("res://scripts/battle_rules.gd")
const CROP := Rect2(100, 56, 486, 273)             # a arte útil dentro da imagem gerada
const ZOOM := 640.0 / 486.0                        # exceção provisória à grade 1:1 (C1): a arena atual é ampliada
const STAGE := Vector2(640, 360)                   # zona de ação; a câmera fica no centro dela
const ORDER := R.ORDER
# Visão de baixo para cima, como em Sea of Stars: o grupo em arco embaixo à esquerda, o chefe no alto à direita.
# Heróis e chefe em escala 1,0 (1 pixel de arte = 1 pixel de 640x360), vizinho mais próximo.
const HOME := {"aldo": Vector2(342, 252), "andilla": Vector2(298, 284), "teo": Vector2(240, 238), "lyra": Vector2(196, 280)}
const BOSS_POS := Vector2(470, 184)
const FOE_SPOT := Vector2(-48, 30)           # onde o herói para diante do chefe, ao atacar
const DIM := Color(0.07, 0.08, 0.15)
const NORMAL_TINT := Color(0.82, 0.86, 1.0)
const HAND := Vector2(16, -38)             # mão de quem conjura (escala 1,0)
const CARD_SIZE := Vector2(148, 26)
const TOP_BAR_SIZE := Vector2(440, 24)
const MENU_X := 374                        # coluna do menu: logo à direita do arco do grupo (mundo)
const MENU_DY := -70                       # topo do menu = pés do herói ativo - 70
const MENU_W := 112
const MENU_TOP := 56                       # o menu nunca sobe por cima da barra do topo
const MENU_W_TOUCH := 160                  # no toque: canto de baixo à direita, linhas de 44, letra 24
const BACK_SIZE := 44                      # botão Voltar redondo do toque, à esquerda do menu
const TAP_HERO := Vector2(48, 64)          # alvo de toque de cada herói, centrado em pés + TAP_LIFT
const TAP_LIFT := Vector2(0, -28)
const FORECAST_AT := BOSS_POS + Vector2(-30, -134)
const BOSS_HIT := BOSS_POS + Vector2(-8, -46)      # onde o golpe acerta o chefe
const BOSS_FEET := BOSS_POS + Vector2(-8, -18)     # base dos efeitos de chão (gelo, luz)
# {A} vira o que segurar no aparelho em uso (E no teclado, A no controle, "o dedo na tela" no toque).
const DESC := {"attack": "Ataque básico. Enche a energia.", "magic": "Magias do herói.", "tech": "Técnicas de combate.", "defend": "Reduz o dano e recupera energia.",
	"golpe": "Golpe pesado. Segure {A} para reforçar.", "golpeBaixo": "Some nas sombras e ataca por trás.", "fogo": "Bola de fogo contra um inimigo.",
	"gelo": "Lascas de gelo do chão.", "cura": "Restaura PV de um único aliado.", "luz": "Raio sagrado. Segure {A} para reforçar."}
const CHARGE_TIME := 1.0
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
var top_panel: Panel
var top_icon: TextureRect
var hud_layer: CanvasLayer        # cartas, barra do topo e menu: somem enquanto a caixa de diálogo está aberta
var over: CanvasLayer             # acima do escurecimento: números de dano e previsão, presos ao mundo
var bg: Sprite2D
var menu_hero := {}               # herói dono do menu aberto
var menu_back := Callable()       # o que cancel faz no submenu aberto
var menu_tab: Label
var menu_rebuild := Callable()    # refaz o menu aberto quando o aparelho muda (tamanho de letra e de linha)
var armed := ""                   # linha marcada pelo primeiro toque num submenu
var back_btn: Button
var tap_layer: Node2D             # alvos de toque sobre os heróis, na escolha de aliado
var pools: Array = []
var bstate := R.boss_state()
var stats := {"taken": 0, "fallen": 0, "corte": 0, "escudo": 0, "items": 0, "timed": 0, "blocks": 0}   # para o --auto e o balanceamento
var rounds := 0
var auto := false
var shot_path := ""
var shot_frame := 60
var frames_seen := 0
var glows: Array = []
var t := 0.0
var mod: CanvasModulate
var menu_panel: PanelContainer
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
	over = CanvasLayer.new()
	over.layer = 3
	over.follow_viewport_enabled = true
	add_child(over)
	_build_stage()
	_build_ui()
	cam = Camera2D.new()
	cam.position = STAGE / 2.0
	add_child(cam)
	get_viewport().size_changed.connect(_fit_stage)
	_fit_stage()
	var touch_ui: CanvasLayer = load("res://scripts/touch_controls.gd").new()
	touch_ui.show_stick = false        # na batalha: só o botão de menu; os comandos são tocados no próprio menu
	touch_ui.show_ab = false
	add_child(touch_ui)
	add_child(load("res://scripts/pause_menu.gd").new())
	Controls.device_changed.connect(_on_device)
	_apply_budget()
	_run()

## O toque apareceu ou sumiu: orçamento de luzes e menu aberto com a medida do aparelho novo.
func _on_device(_mode := "") -> void:
	_apply_budget()
	if menu_panel.visible and menu_rebuild.is_valid():
		menu_rebuild.call()

## No toque só as Fx.MAX_LIGHTS_TOUCH primeiras luzes da arte ficam acesas (a lista está em ordem de importância).
func _apply_budget() -> void:
	for i in glows.size():
		glows[i].n.enabled = Fx.light_on(i, Controls.is_touch)

# ---------- cenário ----------

func _build_stage() -> void:
	bg = Sprite2D.new()
	bg.texture = load("res://assets/battle/arena2_bg.png")
	bg.centered = false
	bg.region_enabled = true
	bg.region_rect = CROP
	bg.z_index = -100
	add_child(bg)
	# luzes da arte (velas, lanternas, o veio verde da parede, braseiros): acompanham o fundo quando ele cresce.
	# Em ordem de importância: no toque só as primeiras ficam acesas (_apply_budget).
	glows.append({"n": Fx.make_light(self, BOSS_POS + Vector2(-16, -64), Color("#9fd8ff"), 0.55, 120), "base": 0.55, "f": 0.15})
	glows.append(_art_light(Vector2(257, 30), Color("#40ffb0"), 1.1, 150, 0.1))
	for c in [Vector2(270, 311), Vector2(424, 306)]:
		glows.append(_art_light(c, Color("#ff9a40"), 1.3, 100, 0.18))
	for c in [Vector2(230, 65), Vector2(385, 55), Vector2(511, 84), Vector2(531, 292), Vector2(7, 222)]:
		glows.append(_art_light(c, Color("#ffb060"), 0.9, 70, 0.22))

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = Fx.sineiro_frames()
	sprite.centered = false
	sprite.offset = Vector2(-64, -120)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.play("stance")
	var root := Node2D.new()
	root.position = BOSS_POS
	var sh := Sprite2D.new()
	sh.texture = Fx.shadow_texture()
	sh.scale = Vector2(1.3, 0.35)
	sh.z_index = -1
	root.add_child(sh)
	root.add_child(sprite)
	add_child(root)
	forecast = Node2D.new()
	forecast.position = FORECAST_AT
	over.add_child(forecast)
	boss = {"root": root, "sprite": sprite, "hp": R.SINEIRO.hp, "hpmax": R.SINEIRO.hp, "home": BOSS_POS}

	for id in ORDER:
		var d: Dictionary = Game.party[id]
		var hr := Node2D.new()
		hr.position = HOME[id]
		var shd := Sprite2D.new()
		shd.texture = Fx.shadow_texture()
		shd.scale = Vector2(0.6, 0.24)
		shd.z_index = -1
		hr.add_child(shd)
		var sp := AnimatedSprite2D.new()
		sp.sprite_frames = Fx.hero_frames(id)
		sp.centered = false
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.offset = Vector2(-28, -66)
		hr.add_child(sp)
		_play({"id": id, "sprite": sp}, "stance")
		sp.frame = randi() % 4
		add_child(hr)
		var hpmax := R.max_stat(id, d.lv, "hp", d.bonus)
		actors[id] = {"id": id, "root": hr, "sprite": sp, "lv": d.lv, "hp": mini(d.hp, hpmax), "hpmax": hpmax,
			"mp": d.mp, "mpmax": R.max_stat(id, d.lv, "mp", d.bonus), "en": R.ENERGY.start if R.HEROES[id].energy else 0,
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

func _art_light(pos: Vector2, color: Color, energy: float, radius: float, flicker: float) -> Dictionary:
	return {"n": Fx.make_light(self, pos, color, energy, radius), "base": energy, "f": flicker, "art": pos, "r": radius}

## Tela larga e Steam Deck sem barras pretas: o fundo cresce em volta do centro da zona de ação até cobrir a área
## visível (escala de cobertura). Heróis e chefe não mudam de lugar; as luzes da arte acompanham o fundo.
func _fit_stage() -> void:
	var vis := get_viewport().get_visible_rect().size
	var k := maxf(1.0, maxf(vis.x / STAGE.x, vis.y / STAGE.y))
	var c := STAGE / 2.0
	bg.scale = Vector2.ONE * ZOOM * k
	bg.position = c - c * k
	for g in glows:
		if g.has("art"):
			g.n.position = c + (g.art - c) * k
			g.n.texture_scale = g.r * k / 128.0

# ---------- interface ----------

## Barra fina de 3 px: fundo escuro e preenchimento; devolve o preenchimento (a largura cheia fica em meta "w").
func _bar(parent: Control, pos: Vector2, w: float, color: Color) -> ColorRect:
	var back := ColorRect.new()
	back.color = Color(0.1, 0.1, 0.16)
	back.position = pos
	back.size = Vector2(w, 3)
	parent.add_child(back)
	var fill := ColorRect.new()
	fill.color = color
	fill.size = Vector2(w, 3)
	fill.set_meta("w", w)
	back.add_child(fill)
	return fill

func _set_bar(fill: ColorRect, value: float, max_value: float) -> void:
	fill.size.x = roundf(float(fill.get_meta("w")) * clampf(value / maxf(1.0, max_value), 0.0, 1.0))

func _build_cine() -> void:
	var hi := CanvasLayer.new()
	hi.layer = 6
	add_child(hi)
	banner = UI.label("", 24, Color.WHITE, 3)
	banner.set_anchors_preset(Control.PRESET_TOP_WIDE)
	banner.offset_top = UI.SAFE + TOP_BAR_SIZE.y + 8
	banner.offset_right = -96           # centro um pouco à esquerda: o nome longo não encosta na previsão do chefe
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0
	hi.add_child(banner)

func _build_ui() -> void:
	_build_cine()
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	hud_layer = layer
	var hud := Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	var safe := UI.safe_rect(get_viewport())
	var vis := get_viewport().get_visible_rect().size

	# barra do topo: uma linha, texto à esquerda, quadro de ícone à direita
	top_panel = Panel.new()
	top_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top_panel.offset_left = -TOP_BAR_SIZE.x / 2.0
	top_panel.offset_right = TOP_BAR_SIZE.x / 2.0
	top_panel.offset_top = safe.position.y
	top_panel.offset_bottom = safe.position.y + TOP_BAR_SIZE.y
	top_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_panel.add_theme_stylebox_override("panel", UI.panel_style())
	hud.add_child(top_panel)
	log_label = UI.label()
	log_label.position = Vector2(8, 0)
	log_label.size = Vector2(TOP_BAR_SIZE.x - 8 - TOP_BAR_SIZE.y - 4, TOP_BAR_SIZE.y)
	log_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	log_label.clip_text = true
	log_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	top_panel.add_child(log_label)
	var frame := Panel.new()
	frame.position = Vector2(TOP_BAR_SIZE.x - TOP_BAR_SIZE.y, 0)
	frame.size = Vector2(TOP_BAR_SIZE.y, TOP_BAR_SIZE.y)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.panel_style(UI.PANEL_BORDER, 1, Color(0, 0, 0, 0.25)))
	top_panel.add_child(frame)
	top_icon = TextureRect.new()
	top_icon.position = Vector2(4, 4)
	top_icon.size = Vector2(16, 16)
	frame.add_child(top_icon)
	top_panel.hide()

	# cartas de status: uma linha cada, embaixo à esquerda, e a joia de combo logo acima
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	stack.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stack.offset_left = safe.position.x
	stack.offset_bottom = safe.end.y - vis.y
	stack.add_theme_constant_override("separation", 2)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(stack)
	var gem := Control.new()
	gem.custom_minimum_size = Vector2(CARD_SIZE.x, 36)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(gem)
	var gem_box := Panel.new()
	gem_box.size = Vector2(24, 24)
	gem_box.pivot_offset = Vector2(12, 12)
	gem_box.position = Vector2(28 - 12, 18 - 12)
	gem_box.rotation = PI / 4.0
	gem_style = UI.panel_style(Color(0.7, 0.55, 0.9), 2, Color(0.05, 0.06, 0.14, 0.9))
	gem_box.add_theme_stylebox_override("panel", gem_style)
	gem.add_child(gem_box)
	gem_label = UI.num_label()
	gem_label.position = Vector2(28 - 20, 18 - 10)
	gem_label.size = Vector2(40, 20)
	gem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gem.add_child(gem_label)
	var gem_title := UI.label("COMBO")
	gem_title.position = Vector2(50, 18 - 8)
	gem.add_child(gem_title)
	for id in ORDER:
		var hero_col := Color(R.HEROES[id].color)
		var holder := Control.new()
		holder.custom_minimum_size = CARD_SIZE
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(holder)
		var panel := Panel.new()
		panel.size = CARD_SIZE
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := UI.panel_style(Color(hero_col, 0.55), 1)
		panel.add_theme_stylebox_override("panel", st)
		holder.add_child(panel)
		var face := TextureRect.new()
		face.texture = Fx.face_texture(id)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		face.position = Vector2(2, 2)
		face.size = Vector2(22, 22)
		panel.add_child(face)
		var hp_l := UI.num_label()
		hp_l.position = Vector2(28, 7)
		panel.add_child(hp_l)
		var rs_l := UI.num_label()
		rs_l.position = Vector2(92, 7)
		panel.add_child(rs_l)
		var hp_b := _bar(panel, Vector2(28, 19), 58, Color("#e0a050"))
		var rs_b := _bar(panel, Vector2(92, 19), 50, Color("#60d0ff") if R.HEROES[id].energy else Color("#b060e0"))
		cards[id] = {"panel": panel, "style": st, "hp_l": hp_l, "hp_b": hp_b, "rs_l": rs_l, "rs_b": rs_b}
	_update_gem()

	# menu do herói: painel com tema próprio, em coordenada de tela (ver _place_menu), aba com o nome por cima
	menu_panel = PanelContainer.new()
	menu_panel.theme = UI.menu_theme()
	menu_panel.hide()
	hud.add_child(menu_panel)
	menu_box = VBoxContainer.new()
	menu_box.custom_minimum_size = Vector2(MENU_W, 0)
	menu_box.add_theme_constant_override("separation", 0)
	menu_panel.add_child(menu_box)
	menu_tab = UI.label()
	menu_tab.hide()
	hud.add_child(menu_tab)
	back_btn = Button.new()
	back_btn.custom_minimum_size = Vector2(BACK_SIZE, BACK_SIZE)
	back_btn.size = back_btn.custom_minimum_size
	back_btn.icon = UI.icon("back")
	back_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_btn.focus_mode = Control.FOCUS_NONE
	var round_st := UI.panel_style(Color(1, 1, 1, 0.55), 1, Color(0.04, 0.05, 0.12, 0.7))
	round_st.set_corner_radius_all(BACK_SIZE / 2)
	for st in ["normal", "hover", "pressed", "focus"]:
		back_btn.add_theme_stylebox_override(st, round_st)
	back_btn.pressed.connect(func(): if menu_back.is_valid(): menu_back.call())
	back_btn.hide()
	hud.add_child(back_btn)
	tap_layer = Node2D.new()
	over.add_child(tap_layer)
	_update_cards()

func _update_gem() -> void:
	gem_label.text = str(combo)
	var ready: bool = combo >= int(R.COMBOS.corte.cost)
	gem_style.border_color = Color("#ffd060") if ready else Color(0.7, 0.55, 0.9)
	gem_style.bg_color = Color(0.05, 0.06, 0.14, 0.9).lerp(Color("#7a4cc0"), float(combo) / R.COMBO_MAX)

func _add_combo(n: int) -> void:
	combo = R.combo_gain(combo, n)
	_update_gem()

## Os próximos golpes do chefe aparecem acima dele, em ícones: punho (golpe), gota (dobre), sino (badalada).
## O primeiro é o que ele vai fazer de fato (travado em BattleRules.boss_turn).
func _update_forecast() -> void:
	for ch in forecast.get_children():
		ch.queue_free()
	var moves := R.boss_forecast(bstate)
	for i in moves.size():
		var ic := Sprite2D.new()
		ic.texture = UI.icon(moves[i])
		ic.centered = false
		ic.position = Vector2(i * 20, 0)
		ic.modulate.a = 1.0 if i == 0 else 0.7
		forecast.add_child(ic)

func _mark_active(id: String) -> void:
	for k in ORDER:
		var st: StyleBoxFlat = cards[k].style
		var on: bool = k == id
		st.set_border_width_all(2 if on else 1)
		st.border_color = Color(R.HEROES[k].color, 1.0 if on else 0.55)
		cards[k].panel.position.x = 6 if on else 0

func _update_cards() -> void:
	for id in ORDER:
		var a: Dictionary = actors[id]
		var c: Dictionary = cards[id]
		c.hp_l.text = "PV %d" % a.hp
		_set_bar(c.hp_b, a.hp, a.hpmax)
		c.hp_b.color = Color("#e05050") if a.hp < a.hpmax * 0.3 else Color("#e0a050")
		var energy: bool = R.HEROES[id].energy
		c.rs_l.text = ("EN %d" % a.en) if energy else ("PM %d" % a.mp)
		_set_bar(c.rs_b, a.en if energy else a.mp, R.ENERGY.max if energy else a.mpmax)
		c.panel.modulate = Color(1, 1, 1, 1.0 if a.hp > 0 else 0.45)

func _clear_menu() -> void:
	for ch in menu_box.get_children():
		menu_box.remove_child(ch)
		ch.queue_free()
	menu_panel.hide()
	menu_panel.size = Vector2.ZERO
	menu_tab.hide()
	back_btn.hide()
	menu_back = Callable()
	armed = ""
	for ch in tap_layer.get_children():
		ch.queue_free()

## O menu fica numa coluna fixa à direita do grupo, na altura do herói ativo, convertido do mundo para a tela
## (em tela larga o mundo anda e o menu vai junto) e preso à área segura.
## No toque ele vai para o canto de baixo à direita, perto do polegar, com o Voltar redondo à esquerda.
func _place_menu() -> void:
	if not menu_panel.visible or menu_hero.is_empty():
		return
	var safe := UI.safe_rect(get_viewport())
	if Controls.is_touch:
		menu_panel.position = safe.end - menu_panel.size
		# aba à direita: com nomes longos o painel cresce para a esquerda, e a aba não cobre os pés do grupo
		menu_tab.position = Vector2(menu_panel.get_rect().end.x - menu_tab.get_minimum_size().x - 4, menu_panel.position.y - menu_tab.get_minimum_size().y + 6)
		back_btn.visible = menu_back.is_valid()
		back_btn.position = Vector2(menu_panel.position.x - 4 - BACK_SIZE, safe.end.y - BACK_SIZE)
		return
	var area := Rect2(safe.position.x, maxf(safe.position.y, MENU_TOP), safe.size.x, safe.end.y - maxf(safe.position.y, MENU_TOP))
	var want := get_viewport().get_canvas_transform() * Vector2(MENU_X, menu_hero.home.y + MENU_DY)
	menu_panel.position = UI.clamp_in(want, menu_panel.size, area)
	menu_tab.position = menu_panel.position + Vector2(4, -15)
	back_btn.hide()

## Uma linha do menu. `two_tap`: nos submenus, no toque, o primeiro toque marca a linha e mostra a descrição
## e o segundo na mesma linha confirma. `value`: número à direita (custo).
func _button(text: String, cb: Callable, disabled := false, desc := "", two_tap := false, value := "") -> Button:
	var act := cb
	if two_tap:
		act = func():
			if UI.tap_confirms(armed, text, Controls.is_touch):
				cb.call()
			else:
				armed = text
				var mine: Button = menu_box.get_children().filter(func(x): return x.text == text)[0]
				mine.grab_focus()
	var b := UI.menu_button(text, act, disabled, Controls.is_touch, value)
	var cursor := TextureRect.new()
	cursor.texture = UI.icon("cursor")
	cursor.position = Vector2(4, (b.custom_minimum_size.y - 7) / 2.0)
	cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cursor.hide()
	b.add_child(cursor)
	b.focus_entered.connect(func():
		cursor.show()
		if desc != "":
			log_label.text = desc.replace("{A}", Controls.prompt("hold")))
	b.focus_exited.connect(cursor.hide)
	menu_box.add_child(b)
	menu_panel.show()
	menu_tab.show()
	return b

## Abre um submenu: cancel (Esc, B) volta para `back`.
func _submenu(h: Dictionary, back: Callable) -> void:
	_clear_menu()
	_open_tab(h)
	menu_back = back

func _open_tab(h: Dictionary) -> void:
	menu_hero = h
	menu_box.custom_minimum_size.x = MENU_W_TOUCH if Controls.is_touch else MENU_W
	menu_tab.add_theme_font_size_override("font_size", UI.TEXT_TOUCH if Controls.is_touch else 12)
	menu_tab.add_theme_constant_override("outline_size", 4 if Controls.is_touch else 2)
	menu_tab.text = R.HEROES[h.id].name.to_upper()
	menu_tab.add_theme_color_override("font_color", Color(R.HEROES[h.id].color))

## Linha "Voltar" da lista: no teclado e no controle; no toque quem volta é o botão redondo.
func _back_row(back: Callable) -> Button:
	return null if Controls.is_touch else _button("Voltar", back)

func _main_menu(h: Dictionary) -> void:
	_clear_menu()
	_open_tab(h)
	menu_rebuild = func(): _main_menu(h)
	var first := _button("Atacar", func(): choice_made.emit({"type": "attack"}), false, DESC.attack)
	var word := "Técnica" if R.HEROES[h.id].energy else "Magia"
	_button(word, func(): _skill_menu(h), false, DESC.tech if R.HEROES[h.id].energy else DESC.magic)
	_button("Combo", func(): _combo_menu(h), combo < int(R.COMBOS.corte.cost), "Golpes em dupla. Gastam pontos de combo.", false, str(combo))
	_button("Defender", func(): choice_made.emit({"type": "defend"}), false, DESC.defend)
	first.grab_focus.call_deferred()

func _combo_menu(h: Dictionary) -> void:
	_submenu(h, func(): _main_menu(h))
	menu_rebuild = func(): _combo_menu(h)
	var rows: Array = []
	for cid in R.COMBOS:
		var cb: Dictionary = R.COMBOS[cid]
		var ok := R.combo_ready(cid, combo, _alive())
		rows.append(_button(cb.name, func(): choice_made.emit({"type": "combo", "id": cid}), not ok, cb.desc, true, "%d PC" % cb.cost))
	rows.append(_back_row(func(): _main_menu(h)))
	_focus_first(rows)

## Foco na primeira linha que se pode escolher (ou na última, o Voltar).
func _focus_first(rows: Array) -> void:
	rows = rows.filter(func(b): return b != null)
	var ok := rows.filter(func(b): return not b.disabled)
	if not ok.is_empty():
		ok[0].grab_focus.call_deferred()

func _skill_menu(h: Dictionary) -> void:
	_submenu(h, func(): _main_menu(h))
	menu_rebuild = func(): _skill_menu(h)
	var rows: Array = []
	for sid in R.HEROES[h.id].skills:
		var s: Dictionary = R.SKILLS[sid]
		var unit := "PM" if s.cost_kind == "mp" else "EN"
		var ok := R.can_pay(s, h.mp, h.en)
		rows.append(_button(s.name, func(): _after_skill_pick(h, sid), not ok, DESC.get(sid, ""), true, "%d %s" % [s.cost, unit]))
	rows.append(_back_row(func(): _main_menu(h)))
	_focus_first(rows)

## Escolha do aliado: pela lista ou tocando no próprio herói (alvo de TAP_HERO sobre cada um).
func _after_skill_pick(h: Dictionary, sid: String) -> void:
	if R.SKILLS[sid].target != "ally":
		choice_made.emit({"type": "skill", "id": sid})
		return
	_submenu(h, func(): _skill_menu(h))
	menu_rebuild = func(): _after_skill_pick(h, sid)
	var rows: Array = []
	for id in ORDER:
		var a: Dictionary = actors[id]
		if a.hp <= 0:
			continue
		var pick := func(): choice_made.emit({"type": "skill", "id": sid, "target": id})
		rows.append(_button(R.HEROES[id].name, pick, false, "", false, "%d/%d" % [a.hp, a.hpmax]))
		_hero_target(a, pick)
	rows.append(_back_row(func(): _skill_menu(h)))
	_focus_first(rows)
	log_label.text = "Toque em quem vai receber." if Controls.is_touch else "Quem vai receber?"

## Alvo invisível de 48x64 sobre o herói (camada `over`, presa ao mundo). Tocar ou clicar escolhe.
func _hero_target(a: Dictionary, pick: Callable) -> void:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.position = a.home + TAP_LIFT - TAP_HERO / 2.0
	b.size = TAP_HERO
	var hl := UI.panel_style(Color(R.HEROES[a.id].color), 1, Color(1, 1, 1, 0.08))
	for st in ["normal", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	for st in ["hover", "pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, hl)
	b.pressed.connect(pick)
	tap_layer.add_child(b)

func _unhandled_input(e: InputEvent) -> void:
	if menu_panel.visible and menu_back.is_valid() and e.is_action_pressed("cancel"):
		get_viewport().set_input_as_handled()
		menu_back.call()

# ---------- laço da batalha ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, false).timeout     # para com o jogo pausado

func _say(text: String, sec := 1.0) -> void:
	log_label.text = text
	await _wait(sec)

## Falas da luta pela caixa de diálogo (data/dialogue). O --auto e os --demo não esperam por elas.
## Chefe falando: caixa embaixo; herói falando: caixa em cima, e a barra do topo some.
func _talk(scene: String) -> void:
	if auto or demo != "":
		return
	log_label.text = ""
	for id in ORDER:
		Dialogue.register_actor(id, actors[id].root)
	Dialogue.register_actor("sineiro", boss.root)
	await Dialogue.play(scene)

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
	# nova tentativa depois de uma derrota: só a fala curta da porta; na primeira vez, a abertura do Sineiro
	await _talk("igreja_velha" if Game.tries > 0 else "sineiro_abertura")
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
	var choice: Dictionary
	if auto:
		choice = R.auto_choice(h.id, actors, combo)
	else:
		log_label.text = "Vez de %s." % R.HEROES[h.id].name
		_main_menu(h)
		choice = await choice_made
	turn_ring.hide()
	_clear_menu()
	await _execute(h, choice)

func _gain(h: Dictionary, reason: String) -> void:
	h.en = R.energy_after(h.id, h.en, reason)

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
	log_label.text = "Segure %s para reforçar!" % Controls.prompt("hold")
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
		if auto or demo != "" or Controls.confirm_held():
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
			_add_combo(R.combo_points("defend"))
			_gain(h, "defend")
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
			var dmg := R.attack_damage(h.atk, R.roll("dmg", randf()))
			_gain(h, "attack")
			_add_combo(R.combo_points("attack"))
			_impact(h)
			await _hit_boss(dmg, Color.WHITE)
			await _wait(0.15)
			await _back(h)
		"combo":
			var cb: Dictionary = R.COMBOS[c.id]
			combo -= int(cb.cost)
			stats[c.id] += 1
			_update_gem()
			if c.id == "corte":
				await _combo_corte(cb)
			else:
				await _combo_escudo(cb)
		"skill":
			var s: Dictionary = R.SKILLS[c.id]
			var col: Color = SKILL_COLOR.get(c.id, Color.WHITE)
			_add_combo(R.combo_points("skill"))
			if s.cost_kind == "mp":
				h.mp -= s.cost
			else:
				h.en -= s.cost
			_update_cards()
			if s.kind == "heal":
				var tgt: Dictionary = actors[c.target]
				var amount := R.heal_amount(s, h.mag, R.roll("soft", randf()))
				await _cine_begin(s.name, col)
				_play(h, "cast")
				Vfx.magic_circle(self, h.root.position + Vector2(0, 4), col, 0.9)
				await _wait(0.5)
				Vfx.heal(self, tgt.root.position + Vector2(0, -14))
				await _wait(0.5)
				tgt.hp = mini(tgt.hpmax, tgt.hp + amount)
				_float_text(tgt.root.position + Vector2(0, -64), "+%d" % amount, Color("#70e090"))
				_update_cards()
				await _wait(0.7)
				_play(h, "stance")
				await _cine_end()
			elif s.kind == "phys":
				var dmg := R.skill_damage(s, h.atk, h.mag, R.SINEIRO.def, R.SINEIRO.res, R.SINEIRO.undead, R.roll("dmg", randf()))
				await _cine_begin(s.name, col, c.id in SPECIAL)
				if c.id == "golpeBaixo":
					await _shadow_strike(h, dmg, col)
					await _cine_end()
					return
				else:
					var full := await _charge(h, col)
					dmg = R.charged(dmg, full)
					await _lunge(h)
					_play(h, "heavy")
					await _wait(0.5)
					Vfx.sword_hit(self, BOSS_HIT, true)
					_shake(4.0)
					await _hit_boss(dmg, col, full >= 1.0)
					await _wait(0.2)
				await _back(h)
				await _cine_end()
			else:
				var dmg := R.skill_damage(s, h.atk, h.mag, R.SINEIRO.def, R.SINEIRO.res, R.SINEIRO.undead, R.roll("dmg", randf()))
				await _cine_begin(s.name, col, c.id in SPECIAL)
				Vfx.magic_circle(self, h.root.position + Vector2(0, 4), col, 1.0)
				_play(h, "cast")
				await _wait(0.45)
				match c.id:
					"fogo":
						await Vfx.fireball(self, h.root.position + HAND, BOSS_HIT)
						await _hit_boss(dmg, col)
					"gelo":
						Vfx.ice(self, BOSS_FEET)
						await _wait(0.3)
						await _hit_boss(dmg, col)
						await _wait(0.4)
					_:
						var full := await _charge(h, col)
						dmg = R.charged(dmg, full)
						Vfx.holy(self, BOSS_FEET)
						await _wait(0.5)
						await _hit_boss(dmg, col, full >= 1.0)
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
	var dmg := R.combo_damage(a.atk, d.atk, R.SINEIRO.def, R.roll("soft", randf()))
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
	await _hit_boss(dmg, col)
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
		_float_text(a.root.position + Vector2(0, -64), "+%d" % amount, Color("#70e090"))
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
	await _hit_boss(dmg, col)
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

## Dano no chefe. `big`: golpe com carga cheia, o número sai no dobro do tamanho.
func _hit_boss(dmg: int, burst: Color, big := false) -> void:
	boss.hp = maxi(0, boss.hp - dmg)
	_burst(BOSS_POS + Vector2(-8, -50), burst)
	_float_text(BOSS_POS + Vector2(-8, -96), str(dmg), Color.WHITE, big)
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
	var calm: bool = not bstate.enraged
	var move := R.boss_turn(bstate, frac)          # o golpe anunciado; a fúria só muda os seguintes
	if calm and bstate.enraged:
		await _talk("sineiro_furia")
	_update_forecast()
	top_icon.texture = UI.icon(move)
	var alive := _alive()
	if move == "bell":
		_boss_anim("special")
		await _say("O Sineiro toca a Badalada! O som atravessa os ossos.", 0.8)
		_shake(5.0)
		for id in alive:
			var a: Dictionary = actors[id]
			var dmg := R.bell_damage(a.res, bstate.enraged, R.roll("soft", randf()))
			await _hurt_hero(a, dmg, false)
	elif move == "drain":
		var a: Dictionary = actors[alive[randi() % alive.size()]]
		_boss_anim("special")
		await _say("O Sineiro entoa um dobre fúnebre por %s!" % R.HEROES[a.id].name, 0.8)
		var dmg := R.drain_damage(a.res, R.roll("soft", randf()))
		await _hurt_hero(a, dmg, false)
		boss.hp = mini(boss.hpmax, boss.hp + R.drain_heal(dmg))
	else:
		var a: Dictionary = actors[alive[randi() % alive.size()]]
		await _say("O Sineiro golpeia %s com o sino!" % R.HEROES[a.id].name, 0.5)
		var tw := create_tween()
		tw.tween_property(boss.root, "position", a.root.position + Vector2(56, -24), 0.34).set_trans(Tween.TRANS_QUAD)
		await tw.finished
		_boss_anim("heavy")
		await _wait(0.3)
		await _hurt_hero(a, R.boss_hit_damage(a.def, bstate.enraged, R.roll("dmg", randf())), true)
		var back := create_tween()
		back.tween_property(boss.root, "position", BOSS_POS, 0.3)
		await back.finished
	top_icon.texture = null

## Toca uma animação do Sineiro e volta para a pose parada.
func _boss_anim(anim: String) -> void:
	var sp: AnimatedSprite2D = boss.sprite
	sp.play(anim)
	await sp.animation_finished
	sp.play("stance")

func _hurt_hero(a: Dictionary, dmg: int, single: bool) -> void:
	dmg = R.taken(dmg, a.defending)
	a.hp = maxi(0, a.hp - dmg)
	stats.taken += dmg
	if a.hp <= 0:
		stats.fallen += 1
	else:
		_gain(a, "hurt")
	_float_text(a.root.position + Vector2(0, -64), str(dmg), Color.WHITE)
	_shake(2.5)
	var sp: AnimatedSprite2D = a.sprite
	_play(a, "hurt" if a.hp > 0 else "fall", not Fx.new_art(a.id))
	_update_cards()
	await _wait(0.5 if single else 0.3)
	if a.hp > 0:
		_play(a, "stance")

# ---------- efeitos ----------

## Número que sobe e some, acima do escurecimento (camada `over`). Fonte de números no tamanho nativo; dobrado só se `big`.
func _float_text(pos: Vector2, text: String, color: Color, big := false) -> void:
	var l := UI.num_label(text, 16 if big else 8, color, 3 if big else 2)
	l.position = (pos - l.get_minimum_size() / 2.0).round()
	over.add_child(l)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 16, 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)

func _burst(pos: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.emitting = true
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = Fx.particles(26, Controls.is_touch)
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
		var fall := func(_n := ""): create_tween().tween_property(sp, "modulate:a", 0.0, 1.4)
		Dialogue.event.connect(fall, CONNECT_ONE_SHOT)      # "emit:sineiro_cai" na fala em que ele desaba
		await _talk("sineiro_fim")
		if Dialogue.event.is_connected(fall):
			Dialogue.event.disconnect(fall)
			fall.call()
		for id in ORDER:
			var d: Dictionary = Game.party[id]
			d.hp = maxi(1, actors[id].hp)
			d.mp = actors[id].mp
		Game.flags["sineiro_morto"] = true
	else:
		await _say("O sino tocou por vocês...", 2.0)
	if auto:
		var pool: int = ORDER.reduce(func(acc, id): return acc + actors[id].hpmax, 0)
		var extra := " ".join(stats.keys().map(func(k): return "%s=%d" % [k, stats[k]]))
		print("RESULT ", "WIN" if won else "LOSE", " rounds=", rounds, " boss_hp=", boss.hp, " alive=", _alive().size(),
			" ", extra, " taken_pct=%d" % roundi(100.0 * stats.taken / pool))
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
	panel.theme = UI.menu_theme()
	var pst := UI.panel_style(Color(0.5, 0.6, 0.9), 2, Color(0.03, 0.04, 0.10, 0.94))
	pst.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", pst)
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var title := UI.label("VITÓRIA" if won else "DERROTA", 24, Color.WHITE, 3)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UI.label("O sino de Valmor se calou." if won else "Os mortos ainda ouvem o sino.")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var retry := func():
		Game.tries += 1
		Game.heal_all()
		Game.goto(Game.BATTLE)
	var items := [["Continuar", func(): layer.queue_free(); _tomb()]] if won else \
		[["Tentar de novo", retry], ["Voltar ao título", func(): Game.goto(Game.TITLE)]]
	for it in items:
		var b := UI.menu_button(it[0], it[1], false, Controls.is_touch)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(180, UI.ROW_TOUCH)     # 180x44 em todo aparelho (layout-designer 4.6)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b)
	v.get_child(2).grab_focus.call_deferred()

## Tela parada do túmulo vazio: a arena escurece e o grupo olha o nicho; depois, a volta para a Valmor.
func _tomb() -> void:
	create_tween().tween_property(mod, "color", DIM.lerp(NORMAL_TINT, 0.35), 0.8)
	turn_ring.hide()
	forecast.hide()
	await _wait(0.9)
	await _talk("tumulo_vazio")
	Game.goto(Game.VALMOR)

func _process(delta: float) -> void:
	t += delta
	for g in glows:
		g.n.energy = g.base * (1.0 + (sin(t * 7.0 + g.base * 10.0) * 0.5 + sin(t * 19.0) * 0.5) * g.f)
	top_panel.visible = log_label.text != ""
	hud_layer.visible = not Dialogue.open
	_place_menu()
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
