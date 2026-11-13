extends Node2D
## Fatia vertical: Valmor à noite. Luz colorida sobre pixel art, grupo que segue o líder, neve e vinheta.
## Controles pelo autoload Controls (andar, confirm; F11 tela cheia fica no próprio Controls).
## Falas pelo autoload Dialogue: abertura ao chegar, exame (confirm longe de tudo), porta da igreja velha, moradores,
## volta depois da vitória e, depois de ver o Tobias, o cartão final. Com o diálogo aberto o grupo não anda e o confirm
## não vale para a cena. Onde fica cada coisa e o que responde ao confirm: ValmorRules.

const HEROES := ["aldo", "lyra", "teo", "andilla"]
const SPEED := 105.0
const TRAIL_GAP := 24            # pontos da trilha (cerca de 1 px cada) entre um herói e o próximo
const NIGHT := Color(0.30, 0.36, 0.62)
const BACKDROP := "res://assets/valmor_night.png"
const V := preload("res://scripts/valmor_rules.gd")
const CROP := V.CROP
const ZOOM := V.ZOOM
const CHEST_SCALE := 2.0
const LIGHTS_FILE := "res://scripts/valmor_lights.json"
const HINT_TIME := 6.0                  # a dica de controles some depois disso ou no primeiro passo

var world: Node2D
var party: Array = []            # {root, sprite, name}
var shot_frame := 0
var trail: Array = []            # caminho do líder: um ponto a cada pixel andado; os outros seguem esse caminho
var facing := "south"
var moving := false
var lights: Array = []           # {node, base, phase}; as do cenário vêm primeiro, por ordem do JSON
var t := 0.0
var shot_path := ""
var cam: Camera2D
var mark: Label
var prompt: Label
var leaving := false
var fade: ColorRect
var frames_seen := 0
var hint: Label
var hint_tw: Tween
var walked := false
var snow: CPUParticles2D
var step_clock := 0.0            # passo na neve: só o líder faz som (a fila inteira vira barulho)
var last_step := -1
var chests := {}                 # id do baú -> Sprite2D
var shop: CanvasLayer
var toast: PanelContainer
var toast_tw: Tween
var busy := false                # na loja da Dora (falas, menu e a loja em si): o grupo não anda
var shop_pick := ""
var npcs := {}                   # id do morador -> Sprite2D (provisório)

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.03, 0.07))
	var mod := CanvasModulate.new()
	mod.color = NIGHT
	add_child(mod)

	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)

	var bg := Sprite2D.new()
	bg.texture = load(BACKDROP)
	bg.centered = false
	bg.region_enabled = true
	bg.region_rect = CROP
	bg.scale = Vector2(ZOOM, ZOOM)
	bg.z_index = -100
	add_child(bg)

	_load_lights()
	_spawn_party(V.spawn(Game.return_pos))     # posição salva que caia em parede ou fora do mapa volta ao começo
	_add_camera()
	_add_snow()
	_add_vignette()
	_add_hotspot()
	_add_hint()
	Controls.device_changed.connect(func(_m): _on_device())
	get_viewport().size_changed.connect(_fit_snow)
	_fit_snow()
	_apply_budget()
	add_child(load("res://scripts/touch_controls.gd").new())
	add_child(load("res://scripts/pause_menu.gd").new())
	shop = load("res://scripts/shop.gd").new()
	add_child(shop)
	Dialogue.event.connect(_on_dialogue_event)
	_add_chests()
	_add_npcs()
	_add_toast()
	for m in party:
		Dialogue.register_actor(m.name, m.root)
	# a valsa e o vento (vindos do título, seguem sem recomeçar); na volta da luta, a valsa só depois de um silêncio
	Audio.music("valmor_noite", AudioRules.XFADE, 1.5 if Game.flags.get("sineiro_morto", false) else 0.0)
	Audio.amb("valmor_vento")

	Game.leader_pos = func(): return party[0].root.position
	if Game.started:
		Save.write.call_deferred()          # autosave ao entrar na Valmor (início, Continuar e volta da luta)

	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--shot=") and not "--dev-battle" in args:
			shot_path = a.substr(7)
		if a.begins_with("--shotframe="):
			shot_frame = int(a.substr(12))
		if a.begins_with("--postshot=") and Game.flags.get("sineiro_morto", false):
			shot_path = a.substr(11)
	if "--dev-battle" in args and not Game.flags.get("sineiro_morto", false):   # atalho de desenvolvimento
		party[0].root.position = _w(V.CHURCH)
		get_tree().create_timer(0.6).timeout.connect(_start_battle)
	elif not Game.flags.get("abertura_vista", false) and not Game.skip_intro():
		_talk("abertura")

func _exit_tree() -> void:
	Game.leader_pos = Callable()        # fora da Valmor o save usa a posição de volta

func _w(img: Vector2) -> Vector2:   # pixel da imagem gerada -> mundo
	return V.to_world(img)

func _blocked(world_pos: Vector2) -> bool:   # baús e moradores são sólidos: o líder para do lado, não em cima
	return V.blocked(world_pos)

# ---------- luzes ----------

func _load_lights() -> void:
	# Posições das tochas e janelas ficam num JSON para ajustar sem mexer no código.
	var data := []
	if FileAccess.file_exists(LIGHTS_FILE):
		data = JSON.parse_string(FileAccess.get_file_as_string(LIGHTS_FILE))
	for d in data:
		var c := Color(d.get("color", "#ffb060"))
		var l := Fx.make_light(self, _w(Vector2(d.x, d.y)), c, d.get("energy", 1.2), d.get("radius", 80))
		lights.append({"node": l, "base": l.energy, "phase": randf() * 100.0, "flicker": d.get("flicker", 0.15), "scene": true})

# ---------- grupo ----------

func _spawn_party(start: Vector2) -> void:
	# a fila nasce atrás do líder (para baixo, de onde o grupo veio), não empilhada no mesmo ponto
	for i in range(TRAIL_GAP * HEROES.size() + 2):
		trail.append(start + Vector2(0, i))
	for i in HEROES.size():
		var h: String = HEROES[i]
		var root := Node2D.new()
		root.position = trail[i * TRAIL_GAP]
		var sh := Sprite2D.new()
		sh.texture = Fx.shadow_texture()
		sh.scale = Vector2(0.55, 0.22)
		sh.z_index = -1
		root.add_child(sh)
		var sp := AnimatedSprite2D.new()
		sp.sprite_frames = Fx.hero_frames(h, true)
		sp.centered = false
		sp.offset = Vector2(-28, -66)
		sp.play("face_south")
		root.add_child(sp)
		party.append({"root": root, "sprite": sp, "name": h})
	# no y-sort, quem entra por último fica por cima no empate: o líder entra por último
	for i in range(party.size() - 1, -1, -1):
		world.add_child(party[i].root)
	# lampião do líder: a luz quente que acompanha o Aldo
	var lamp := Fx.make_light(party[0].root, Vector2(0, -26), Color("#ffc27a"), 1.1, 120)
	lights.append({"node": lamp, "base": 1.1, "phase": 3.0, "flicker": 0.10})

# ---------- neve, vinheta, dica ----------

func _add_camera() -> void:
	cam = Camera2D.new()
	cam.position = party[0].root.position
	cam.limit_left = 0
	cam.limit_top = 0
	cam.limit_right = int(CROP.size.x * ZOOM)
	cam.limit_bottom = int(CROP.size.y * ZOOM)
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 6.0
	add_child(cam)

func _add_hotspot() -> void:
	mark = UI.label("!", 24, Color("#ffe080"), 3)     # na porta até a vitória, depois no Tobias (ValmorRules.mark_at)
	mark.z_index = 70
	world.add_child(mark)
	prompt = UI.label()
	prompt.z_index = 70
	prompt.hide()
	world.add_child(prompt)
	var layer := CanvasLayer.new()
	layer.layer = 30
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(fade)
	add_child(layer)
	create_tween().tween_property(fade, "color:a", 0.0, 0.6)
	if Game.flags.get("sineiro_morto", false) and Game.return_pos != Vector2.ZERO and not Game.flags.get("voltou", false):
		Game.flags["voltou"] = true
		get_tree().create_timer(0.9).timeout.connect(func(): _talk("valmor_volta"))

## O ponto mais perto do líder dentro do alcance (porta, baú ou morador), ou {}.
func _near() -> Dictionary:
	return V.nearest(V.spots(Game.flags, Game.opened), V.to_img(party[0].root.position))

func _interact() -> void:
	var sp := _near()
	match sp.get("kind", ""):
		"door": _talk("igreja_velha")
		"chest": _open_chest(sp.id)
		"npc": _talk_npc(sp.id)
		_: _talk("valmor_exame")

## Morador: vira para o líder e toca a cena dele (ela mesma escolhe antes, depois e repetição pelas flags
## falou_<id>_*). As flags vão para o save na hora. O Tobias, visto depois do Sineiro, fecha a fatia.
func _talk_npc(id: String) -> void:
	if id == "dora":
		_visit_dora()
		return
	_face_npc(id)
	await _talk(V.NPCS[id].scene)
	if id == "tobias" and V.ending_ready(Game.flags):
		leaving = true
		await Dialogue.play("fim_fatia")
		Save.write()
		Game.goto(Game.TITLE, true)

func _face_npc(id: String) -> void:
	var n: Dictionary = V.NPCS[id]
	if not n.has("lying"):
		npcs[id].texture = load("res://assets/heroes/%s/rot_%s.png" % [n.base, V.face_toward(_w(n.at), party[0].root.position)])

## Moradores provisórios: o quadro parado de um herói em silhueta tingida (Fx.stand_in_material), com sombra, sem
## luz nova (o orçamento do celular fica igual). O Tobias fica deitado numa esteira na porta da capela.
func _add_npcs() -> void:
	for id in V.NPCS:
		var n: Dictionary = V.NPCS[id]
		var lying: bool = n.has("lying")
		var root := Node2D.new()
		root.position = _w(n.at)
		var sh := Sprite2D.new()
		sh.texture = Fx.shadow_texture()
		sh.scale = Vector2(1.1, 0.3) if lying else Vector2(0.5, 0.2)
		sh.z_index = -1
		root.add_child(sh)
		if lying:
			var cot := ColorRect.new()           # a esteira
			cot.color = Color("#a08a68")
			cot.size = Vector2(80, 18)
			cot.position = Vector2(-40, -16)
			root.add_child(cot)
		var sp := Sprite2D.new()
		sp.texture = load("res://assets/heroes/%s/rot_south.png" % n.base)
		sp.material = Fx.stand_in_material(Color(n.tint))
		sp.centered = false
		sp.offset = Fx.IDLE_OFFSET
		sp.scale = Vector2.ONE * n.get("scale", 1.0)
		if lying:                            # deitado de lado, a cabeça para a esquerda
			sp.rotation = -PI / 2.0
			sp.position = Vector2(33, -4)
		root.add_child(sp)
		world.add_child(root)
		npcs[id] = sp
		Dialogue.register_actor(id, root)

## A Dora: saudação, o menu Comprar, Vender, Sair (escolhas do diálogo) e a despedida ao sair.
func _visit_dora() -> void:
	busy = true
	hint.modulate.a = 0.0
	await Dialogue.play("loja_dora")
	shop_pick = ""
	await Dialogue.play("loja_dora_menu")       # devolve pelo evento loja_comprar, loja_vender ou loja_sair
	if shop_pick in ["loja_comprar", "loja_vender"]:
		shop.open(shop_pick == "loja_vender", _leave_dora)
	else:
		_leave_dora()

func _leave_dora() -> void:
	await Dialogue.play("loja_dora", "despedida")
	busy = false

func _on_dialogue_event(name: String) -> void:
	if name.begins_with("loja_"):
		shop_pick = name

# ---------- baús e aviso do que foi achado ----------

func _add_chests() -> void:
	for c in V.CHEST_AT:
		var sp := Sprite2D.new()
		sp.texture = UI.icon("chest_open" if c in Game.opened else "chest")
		sp.scale = Vector2(CHEST_SCALE, CHEST_SCALE)
		sp.offset = Vector2(0, -7)
		sp.position = _w(V.CHEST_AT[c])
		world.add_child(sp)
		chests[c] = sp

## Abre uma vez (EconomyRules.open_chest), troca o desenho, mostra o que veio com as moedas e toca a fala do baú
## (data/dialogue/valmor_baus.json: "poco", "quintal" e as de baú vazio).
func _open_chest(id: String) -> void:
	var from: String = id.split(":")[1]
	var st := Game.purse()
	var got := EconomyRules.open_chest(Game.opened, st, id)
	if got.is_empty():
		_talk_from("valmor_baus", from + "_vazio")
		return
	Game.set_purse(st)
	chests[id].texture = UI.icon("chest_open")
	chests[id].modulate = Color.WHITE
	Audio.sfx("cura")                   # provisório: não há som de baú
	_show_toast("Achou moedas:" if got.has("gold") else "Achou: %s." % EconomyRules.loot_text(got), int(got.get("gold", 0)))
	Save.write()
	_talk_from("valmor_baus", from)

func _talk_from(scene: String, from: String) -> void:
	hint.modulate.a = 0.0
	await Dialogue.play(scene, from)

func _add_toast() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 12
	add_child(layer)
	toast = PanelContainer.new()
	var st := UI.panel_style()
	st.set_content_margin_all(6)
	toast.add_theme_stylebox_override("panel", st)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	toast.add_child(row)
	row.add_child(UI.label())
	var plus := UI.num_label("", 8, Color("#ffe080"))      # "+25" na fonte de números, como os outros números
	plus.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(plus)
	row.add_child(UI.coins_row())
	toast.modulate.a = 0.0
	layer.add_child(toast)

func _show_toast(text: String, plus := 0) -> void:
	var row := toast.get_child(0)
	(row.get_child(0) as Label).text = text
	(row.get_child(1) as Label).text = "+%d" % plus
	row.get_child(1).visible = plus > 0
	UI.set_coins(row.get_child(2), Game.gold)
	toast.reset_size()
	var safe := UI.safe_rect(get_viewport())
	toast.position = Vector2(roundf(safe.position.x + (safe.size.x - toast.size.x) / 2.0), safe.position.y + 24)
	if toast_tw != null:
		toast_tw.kill()
	toast.modulate.a = 1.0
	toast_tw = create_tween()
	toast_tw.tween_interval(2.4)
	toast_tw.tween_property(toast, "modulate:a", 0.0, 0.5)

## Uma conversa; enquanto ela dura a dica some. Grava ao fim (as flags da fala). A porta leva à luta.
func _talk(scene: String) -> void:
	hint.modulate.a = 0.0
	var ev := await Dialogue.play(scene)
	if Game.started:
		Save.write()                    # a abertura (e cada fala) fica gravada: uma queda logo depois não a repete
	if not walked:
		_show_hint()
	if "battle:sineiro" in ev:
		_start_battle()

func _start_battle() -> void:
	leaving = true
	Game.return_pos = party[0].root.position
	Audio.sfx("descer_cripta")          # laje arrastando e passos descendo: a música e o vento somem com o fade
	Audio.music_stop(0.5)
	Audio.amb_stop(0.5)
	var tw := create_tween()
	tw.tween_property(fade, "color:a", 1.0, 0.5)
	await tw.finished
	get_tree().change_scene_to_file("res://scenes/battle.tscn")

func _add_snow() -> void:
	var p := CPUParticles2D.new()
	p.position = Vector2(0, -190)
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(340, 4)
	p.direction = Vector2(-0.25, 1)
	p.spread = 12.0
	p.gravity = Vector2(0, 0)
	p.initial_velocity_min = 22.0
	p.initial_velocity_max = 42.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	p.color = Color(0.9, 0.95, 1.0, 0.85)
	p.z_index = 50
	cam.add_child(p)
	snow = p

## Orçamento do celular (Fx.MAX_LIGHTS_TOUCH, menos neve), refeito quando o toque aparece ou some.
## O lampião do líder fica sempre aceso: só as luzes do cenário entram na conta.
func _apply_budget() -> void:
	var touch := Controls.is_touch
	var i := 0
	for L in lights:
		if L.has("scene"):
			L.node.enabled = Fx.light_on(i, touch)
			i += 1
	var n := Fx.particles(260, touch)
	if snow.amount != n:
		snow.amount = n

func _on_device() -> void:
	_apply_budget()
	_refresh_prompts()

## A neve cai sobre toda a largura visível (tela larga, Deck), não só sobre os 640x360 da base.
func _fit_snow() -> void:
	var vis := get_viewport().get_visible_rect().size
	snow.position = Vector2(0, -vis.y / 2.0 - 10)
	snow.emission_rect_extents = Vector2(vis.x / 2.0 + 20, 4)

func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ vec2 uv = UV - 0.5; float v = smoothstep(0.30, 0.80, length(uv * vec2(1.0, 1.15))); COLOR = vec4(0.01, 0.02, 0.07, v * 0.65); }"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	rect.material = mat
	layer.add_child(rect)
	add_child(layer)

func _add_hint() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 11
	hint = UI.label()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.offset_bottom = -UI.SAFE
	layer.add_child(hint)
	add_child(layer)
	_refresh_prompts()

## Dica de controles embaixo, no centro (no toque, entre o joystick e os botões), por HINT_TIME segundos.
## Volta quando o jogador troca de aparelho, com os rótulos novos.
func _show_hint() -> void:
	if Dialogue.open:
		return
	if hint_tw != null:
		hint_tw.kill()
	hint.modulate.a = 1.0
	hint_tw = create_tween()
	hint_tw.tween_interval(HINT_TIME)
	hint_tw.tween_property(hint, "modulate:a", 0.0, 0.6)

func _hide_hint() -> void:
	if hint_tw != null:
		hint_tw.kill()
	hint_tw = create_tween()
	hint_tw.tween_property(hint, "modulate:a", 0.0, 0.4)

## Dicas com o rótulo do aparelho em uso: trocam sozinhas quando o jogador passa do teclado ao controle ou ao toque.
func _refresh_prompts() -> void:
	var c := Controls.prompt("confirm")
	match Controls.mode():
		"touch": hint.text = "Arraste o círculo para andar    %s: falar" % c
		"pad": hint.text = "Analógico: andar    %s: falar" % c
		_: hint.text = "%s: andar    %s: falar    %s: tela cheia" % [Controls.prompt("move"), c, Controls.prompt("fullscreen")]
	_show_hint()

# ---------- laço principal ----------

func _process(delta: float) -> void:
	t += delta
	for L in lights:
		var n := sin(t * 9.0 + L.phase) * 0.5 + sin(t * 23.0 + L.phase * 1.7) * 0.5
		L.node.energy = L.base * (1.0 + n * L.flicker)

	var dir := Controls.move_vector()
	moving = dir.length() > 0.1
	if Dialogue.is_open() or busy:
		dir = Vector2.ZERO
		moving = false
	elif Input.is_action_just_pressed("confirm") and not leaving and Engine.get_process_frames() != Game.ui_closed_frame:
		_interact()
	var mk := V.mark_at(Game.flags)
	mark.visible = mk != Vector2.ZERO and not leaving
	if mark.visible:
		mark.position = _w(mk) + Vector2(-3, -52 + sin(t * 4.0) * 2.0)
	var near := _near() if not Dialogue.is_open() and not leaving and not busy else {}
	prompt.visible = not near.is_empty()
	if prompt.visible:
		prompt.text = "%s: %s" % [Controls.prompt("confirm"), near.verb]
		prompt.position = _w(near.at) + Vector2(-prompt.get_minimum_size().x / 2.0, -72 if near.kind == "door" else -80).round()
	for c in chests:                    # baú fechado brilha de leve (sem luz nova: o orçamento do celular fica igual)
		if not c in Game.opened:
			chests[c].modulate = Color(1.9, 1.75, 1.4) * (1.0 + 0.25 * sin(t * 3.0 + chests[c].position.x))
	if leaving:
		moving = false
		return
	var leader: Node2D = party[0].root
	if not moving:
		step_clock = AudioRules.STEP_GAP * 0.6     # o primeiro passo soa logo que ele começa a andar
	if moving and not walked:
		walked = true
		_hide_hint()
	if moving:
		var step_v := dir * SPEED * delta
		var from := leader.position
		for axis in [Vector2(step_v.x, 0), Vector2(0, step_v.y)]:   # desliza junto às paredes
			if not _blocked(leader.position + axis):
				leader.position += axis
		step_clock += delta
		if step_clock >= AudioRules.STEP_GAP and leader.position != from:   # parado na parede não faz passo
			step_clock = 0.0
			last_step = AudioRules.step_pick(last_step, randf())
			Audio.sfx(AudioRules.STEPS[last_step], 0.0, randf_range(0.95, 1.05))
		if absf(dir.x) > absf(dir.y):
			facing = "east" if dir.x > 0 else "west"
		else:
			facing = "south" if dir.y > 0 else "north"
	cam.position = leader.position - Vector2(0, 30)
	if leader.position.distance_to(trail[0]) >= 1.0:   # só registra o caminho quando o líder anda de verdade
		trail.push_front(leader.position)
		trail.resize(TRAIL_GAP * HEROES.size() + 2)

	for i in party.size():
		var m = party[i]
		var before: Vector2 = m.root.position
		if i > 0:
			m.root.position = m.root.position.move_toward(trail[i * TRAIL_GAP], SPEED * delta * 1.15)   # anda atrás do caminho, sem teleportar
		var step: bool = moving if i == 0 else m.root.position.distance_to(before) > 0.05
		_animate(m, step)

	if "--walk" in OS.get_cmdline_user_args():   # autoteste: o líder anda para a direita e imprime onde cada herói está
		frames_seen += 1
		if frames_seen == 5:
			Input.action_press("move_right")
		if frames_seen == 240:
			print("x: ", party.map(func(m): return snappedf(m.root.position.x, 0.1)))
			get_tree().quit()
	if shot_path != "":
		frames_seen += 1
		if Controls.forced:   # autoteste do toque: dedo no joystick, arrasta para a direita
			if frames_seen == 5:
				print("leader at start: ", leader.position)
				var down := InputEventScreenTouch.new()
				down.index = 0; down.position = Vector2(72, 288) * 2.0; down.pressed = true
				Input.parse_input_event(down)
			if frames_seen == 8:
				var drag := InputEventScreenDrag.new()
				drag.index = 0; drag.position = Vector2(118, 288) * 2.0
				Input.parse_input_event(drag)
			if frames_seen == 39:
				print("touch_vec: ", Controls.touch_vec, "  leader now: ", leader.position)
		if frames_seen == (shot_frame if shot_frame > 0 else (90 if Game.flags.get("sineiro_morto", false) else 40)):
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()

func _animate(m: Dictionary, step: bool) -> void:
	var sp: AnimatedSprite2D = m.sprite
	var f := facing
	if step:
		if f == "east" or f == "west":
			sp.flip_h = f == "west"
			if sp.animation != "walk":
				sp.play("walk")
		else:
			sp.flip_h = false
			sp.play("face_" + f)
			sp.offset.y = -66 - absf(sin(t * 12.0)) * 2.0
			return
	else:
		if f == "east" or f == "west":
			sp.flip_h = f == "west"
			if sp.animation != "idle":
				sp.play("idle")
		else:
			sp.flip_h = false
			sp.play("face_" + f)
	sp.offset.y = -66
