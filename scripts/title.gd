extends Node2D
## Título mínimo (layout-designer 4.1): Valmor ao longe com neve, nome do jogo em texto e três botões de 180x44.
## Opções simples: velocidade do texto e tela cheia. --skip-intro (e --dev-battle, --walk) vai direto à Valmor.

const BACKDROP := "res://assets/valmor_night.png"
const CROP := Rect2(98, 55, 444, 249)
const BTN := Vector2(180, 44)
const VERSION := "fatia vertical"

var box: VBoxContainer
var bg: Sprite2D
var t := 0.0
var in_options := false
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
	logo.offset_top = 60
	ui.add_child(logo)
	var sub := UI.label("Os Reis Caídos", UI.TEXT_TOUCH if Controls.is_touch else 12, Color("#cfd8ff"), 2)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.offset_top = 126
	ui.add_child(sub)
	box = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	box.offset_bottom = -UI.SAFE - 40
	ui.add_child(box)
	var ver := UI.label(VERSION, 12, Color(1, 1, 1, 0.5))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	ver.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ver.offset_right = -UI.SAFE
	ver.offset_bottom = -UI.SAFE
	ui.add_child(ver)
	_main()

func _rows(items: Array) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for it in items:
		var b := UI.menu_button(it[0], it[1], false, Controls.is_touch)
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = BTN
		box.add_child(b)
	box.get_child(0).grab_focus.call_deferred()

func _main() -> void:
	in_options = false
	var items := [["Nova jogada", _new_game], ["Opções", _options]]
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		items.append(["Sair", func(): get_tree().quit()])
	_rows(items)

func _new_game() -> void:
	Game.reset()
	Game.goto(Game.VALMOR)

## Opções simples: a velocidade do texto dá a volta nas quatro; tela cheia só fora do celular.
func _options() -> void:
	in_options = true
	var speeds: Array = DialogueRules.SPEEDS.keys()
	var items := [["Texto: " + DialogueRules.SPEED_NAMES[Game.options.text_speed], func():
		Game.options.text_speed = speeds[(speeds.find(Game.options.text_speed) + 1) % speeds.size()]
		_options()]]
	if not OS.has_feature("mobile"):
		items.append(["Tela cheia", Controls.toggle_fullscreen])
	items.append(["Voltar", _main])
	_rows(items)

func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("cancel") and in_options:
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
