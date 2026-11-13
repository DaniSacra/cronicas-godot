extends Node2D
## Título mínimo (layout-designer 4.1): Valmor ao longe com neve, nome do jogo em texto e três botões de 180x44.
## Opções simples: velocidade do texto, volume de música e de efeitos, tela cheia. --skip-intro (e --dev-battle, --walk) vai direto à Valmor.

const BACKDROP := "res://assets/valmor_night.png"
const CROP := Rect2(98, 55, 444, 249)
const BTN := Vector2(180, 44)
const VERSION := "fatia vertical"

var box: VBoxContainer
var bg: Sprite2D
var t := 0.0
var in_options := false
var in_confirm := false
var question: Label
var heading: Array = []             # nome e subtítulo: somem nas opções, que têm mais linhas
var shot_path := ""
var frames := 0

func _ready() -> void:
	if Game.skip_intro():
		Game.reset()
		get_tree().change_scene_to_file.call_deferred(Game.VALMOR)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot_path = a.substr(7)
	RenderingServer.set_default_clear_color(Color(0.02, 0.03, 0.07))
	var mod := CanvasModulate.new()
	mod.color = Color(0.30, 0.36, 0.62)
	add_child(mod)
	bg = Sprite2D.new()
	bg.texture = load(BACKDROP)
	bg.region_enabled = true
	bg.region_rect = CROP
	bg.scale = Vector2(2, 2)
	add_child(bg)
	for p in [Vector2(-40, -10), Vector2(60, 20), Vector2(-120, 40)]:
		Fx.make_light(bg, p, Color("#ffb060"), 1.0, 60)
	var cam := Camera2D.new()
	add_child(cam)
	var snow := CPUParticles2D.new()
	snow.position = Vector2(0, -200)
	snow.amount = Fx.particles(160, Controls.is_touch)
	snow.lifetime = 9.0
	snow.preprocess = 9.0
	snow.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	snow.emission_rect_extents = Vector2(420, 4)
	snow.direction = Vector2(-0.25, 1)
	snow.gravity = Vector2.ZERO
	snow.initial_velocity_min = 20.0
	snow.initial_velocity_max = 38.0
	snow.scale_amount_max = 2.0
	snow.color = Color(0.9, 0.95, 1.0, 0.85)
	add_child(snow)

	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.theme = UI.menu_theme()
	layer.add_child(ui)
	var logo := UI.label("Crônicas de Eterra", 24, Color("#ffe6a8"), 4)
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	logo.grow_horizontal = Control.GROW_DIRECTION_BOTH
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.offset_top = 48
	ui.add_child(logo)
	var sub := UI.label("Os Reis Caídos", UI.TEXT_TOUCH if Controls.is_touch else 12, Color("#cfd8ff"), 2)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_top = 92
	ui.add_child(sub)
	heading = [logo, sub]
	question = UI.label("", UI.TEXT_TOUCH if Controls.is_touch else 12, Color("#ffe6a8"), 2)
	question.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	question.grow_horizontal = Control.GROW_DIRECTION_BOTH
	question.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	question.offset_top = 150
	question.hide()
	ui.add_child(question)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -UI.SAFE - 24
	ui.add_child(box)
	var ver := UI.label(VERSION, 12, Color(1, 1, 1, 0.5))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -UI.SAFE
	ver.offset_bottom = -UI.SAFE
	ui.add_child(ver)
	_main()
	Audio.music("valmor_noite")         # o título é a Valmor ao longe: a valsa e o vento seguem para a cena
	Audio.amb("valmor_vento")

func _rows(items: Array, focus := 0) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for it in items:
		var b := UI.menu_button(it[0], it[1], false, Controls.is_touch)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = BTN
		box.add_child(b)
	# a caixa já no tamanho final (centro embaixo, crescendo para cima): sem isso os botões novos ficavam 2 a 3
	# quadros no lugar errado e um toque rápido caía no vazio
	var m := box.get_combined_minimum_size()
	box.offset_left = -m.x / 2.0
	box.offset_right = m.x / 2.0
	box.offset_top = box.offset_bottom - m.y
	box.get_child(focus).grab_focus.call_deferred()

func _main() -> void:
	in_options = false
	in_confirm = false
	question.hide()
	for h in heading:
		h.show()
	var items := [["Nova jogada", _new_game], ["Opções", _options]]
	if Save.has_game():
		items.push_front(["Continuar", Save.load_game])
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		items.append(["Sair", Audio.quit])
	_rows(items)

## Com jogo salvo, Nova jogada pergunta antes: o save antigo some no primeiro salvamento da jogada nova.
func _new_game() -> void:
	if Save.has_game() and not in_confirm:
		in_confirm = true
		for h in heading:
			h.hide()
		_rows([["Começar de novo", _new_game], ["Voltar", _main]], 1)
		_ask("A jogada salva será substituída.")
		return
	Game.reset()
	Game.started = true
	Game.goto(Game.VALMOR)

## Pergunta acima dos botões (só na confirmação de Nova jogada).
func _ask(text: String) -> void:
	question.text = text
	question.show()

## Opções: velocidade do texto, Música e Efeitos (Game.option_rows, iguais às da pausa); tela cheia só fora do celular.
func _options(focus := 0) -> void:
	in_options = true
	question.hide()
	for h in heading:
		h.hide()
	var items := Game.option_rows(_options)
	if not OS.has_feature("mobile"):
		items.append(["Tela cheia", Controls.toggle_fullscreen])
	items.append(["Voltar", _main])
	_rows(items, focus)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("cancel") and (in_options or in_confirm):
		UI.play("voltar")
		_main()

func _process(delta: float) -> void:
	t += delta
	if bg != null:
		bg.position.x = sin(t * TAU / 40.0) * 8.0      # deslize lento de 8 px
	if shot_path != "":
		frames += 1
		if frames == 40:
			get_viewport().get_texture().get_image().save_png(shot_path)
			get_tree().quit()
