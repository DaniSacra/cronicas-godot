extends CanvasLayer
## Joystick virtual à esquerda e botões à direita. Só aparece em modo de toque (ver Controls).
## Os botões apertam as mesmas ações do teclado, então o resto do jogo não sabe de onde veio o comando.
## Na batalha só o botão de menu aparece (`show_stick` e `show_ab` desligados): lá os comandos são tocados no menu
## e o dedo em qualquer lugar da tela segura a carga (Controls.confirm_held).
## Modo diálogo (Dialogue aberto): joystick, A e B somem; tocar em qualquer lugar aperta confirm; um botão voltar
## de 44x44 acima da caixa, alinhado à esquerda dela, aperta cancel.

const RADIUS := 46.0
const BTN_R := 22.0
const REACH := 1.5                    # o toque vale até 1,5x o raio do botão; o botão mais perto vence
const ALPHA := 0.55

var show_stick := true
var show_ab := true
var canvas: Control
var stick_finger := -1
var stick_off := Vector2.ZERO
var held := {}                        # dedo -> ação
var center := Vector2.ZERO
var buttons: Array = []               # {action, label, pos}
var talking := false

func _ready() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS     # o botão de menu também fecha a pausa
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_hud)
	add_child(canvas)
	Controls.touch_mode_changed.connect(func(_on): _release_all())
	_layout()

## A e B com zonas de toque (1,5x o raio) que não se cruzam; menu no canto de cima, dentro da margem segura.
func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	center = Vector2(72, s.y - 72)
	buttons = [{"action": "menu", "label": "", "pos": Vector2(s.x - UI.SAFE - BTN_R, UI.SAFE + BTN_R)}]
	if talking:
		if Dialogue.box.visible:
			var spots := DialogueRules.touch_spots(Dialogue.box_rect(), Dialogue.box_on_top(), buttons[0].pos, BTN_R)
			buttons[0].pos = spots[1]
			buttons.append({"action": "cancel", "label": "back", "pos": spots[0]})
	elif show_ab:
		var ab := UI.ab_spots(s)
		buttons.append({"action": "confirm", "label": "A", "pos": ab[0]})
		buttons.append({"action": "cancel", "label": "B", "pos": ab[1]})

func _process(_d: float) -> void:
	visible = Controls.is_touch
	if talking != Dialogue.is_open():
		_release_all()
		talking = Dialogue.is_open()
	if visible:
		_layout()
		canvas.queue_redraw()

func _release_all() -> void:
	stick_finger = -1
	stick_off = Vector2.ZERO
	Controls.touch_vec = Vector2.ZERO
	for a in held.values():
		Input.action_release(a)
	held.clear()

func _input(e: InputEvent) -> void:
	if not Controls.is_touch:
		return
	var finger := -1
	var pos := Vector2.ZERO
	var down := false
	var is_drag := false
	if e is InputEventScreenTouch:
		finger = e.index; pos = e.position; down = e.pressed
	elif e is InputEventScreenDrag:
		finger = e.index; pos = e.position; down = true; is_drag = true
	elif Controls.forced and e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		finger = 99; pos = e.position; down = e.pressed
	elif Controls.forced and e is InputEventMouseMotion and (e.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		finger = 99; pos = e.position; down = true; is_drag = true
	else:
		return
	_handle(finger, pos, down, is_drag)

func _handle(finger: int, pos: Vector2, down: bool, is_drag: bool) -> void:
	if not down:
		if finger == stick_finger:
			stick_finger = -1
			stick_off = Vector2.ZERO
			Controls.touch_vec = Vector2.ZERO
		if held.has(finger):
			Input.action_release(held[finger])
			held.erase(finger)
		return
	if talking:
		if not held.has(finger) and not is_drag:
			var k := Controls.nearest(buttons.map(func(b): return b.pos), pos, BTN_R)
			held[finger] = buttons[k].action if k != -1 else "confirm"     # fora dos botões: avança a fala
			Input.action_press(held[finger])
		return
	if show_stick and not talking and (finger == stick_finger or (stick_finger == -1 and not is_drag and pos.x < get_viewport().get_visible_rect().size.x * 0.45)):
		stick_finger = finger
		var v := Controls.stick_vector(center, pos, RADIUS)
		Controls.touch_vec = v
		stick_off = (pos - center).limit_length(RADIUS)
		return
	if not held.has(finger) and not is_drag:
		var i := Controls.nearest(buttons.map(func(b): return b.pos), pos, BTN_R * REACH)
		if i != -1:
			held[finger] = buttons[i].action
			Input.action_press(buttons[i].action)

func _draw_hud() -> void:
	var white := Color(1, 1, 1, ALPHA)
	if show_stick and not talking:
		canvas.draw_circle(center, RADIUS, Color(1, 1, 1, 0.10))
		canvas.draw_arc(center, RADIUS, 0, TAU, 40, white, 1.5)
		canvas.draw_circle(center + stick_off, 17.0, Color(1, 1, 1, 0.30 if stick_finger != -1 else 0.18))
		canvas.draw_arc(center + stick_off, 17.0, 0, TAU, 28, white, 1.5)
	var font: Font = ThemeDB.get_default_theme().default_font
	for b in buttons:
		var on: bool = held.values().has(b.action)
		canvas.draw_circle(b.pos, BTN_R, Color(1, 1, 1, 0.30 if on else 0.12))
		canvas.draw_arc(b.pos, BTN_R, 0, TAU, 28, white, 1.5)
		if b.label == "" or b.label == "back":
			canvas.draw_texture(UI.icon(b.action if b.label == "" else "back"), b.pos - Vector2(8, 8), white)
		else:
			var sz := font.get_string_size(b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.TEXT_TOUCH)
			var base: Vector2 = b.pos + Vector2(-sz.x / 2.0, font.get_ascent(UI.TEXT_TOUCH) - sz.y / 2.0)
			canvas.draw_string_outline(font, base.round(), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.TEXT_TOUCH, 4, Color(0.01, 0.01, 0.04, 0.8))
			canvas.draw_string(font, base.round(), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, UI.TEXT_TOUCH, white)
