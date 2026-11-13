extends CanvasLayer
## Joystick virtual à esquerda e botões à direita. Só aparece em modo de toque (ver Controls).
## Os botões apertam as mesmas ações do teclado, então o resto do jogo não sabe de onde veio o comando.

const RADIUS := 46.0
const BTN_R := 22.0
const ALPHA := 0.55

var canvas: Control
var stick_finger := -1
var stick_off := Vector2.ZERO
var held := {}                        # dedo -> ação
var center := Vector2.ZERO
var buttons: Array = []               # {action, label, pos}

func _ready() -> void:
	layer = 20
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.draw.connect(_draw_hud)
	add_child(canvas)
	Controls.touch_mode_changed.connect(func(_on): _release_all())
	_layout()

func _layout() -> void:
	var s := get_viewport().get_visible_rect().size
	center = Vector2(72, s.y - 72)
	buttons = [
		{"action": "confirm", "label": "A", "pos": Vector2(s.x - 48, s.y - 78)},
		{"action": "cancel", "label": "B", "pos": Vector2(s.x - 98, s.y - 44)},
		{"action": "menu", "label": "=", "pos": Vector2(s.x - 28, 28)},
	]

func _process(_d: float) -> void:
	visible = Controls.is_touch
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
	if finger == stick_finger or (stick_finger == -1 and not is_drag and pos.x < get_viewport().get_visible_rect().size.x * 0.45):
		stick_finger = finger
		var v := Controls.stick_vector(center, pos, RADIUS)
		Controls.touch_vec = v
		stick_off = (pos - center).limit_length(RADIUS)
		return
	if not held.has(finger) and not is_drag:
		for b in buttons:
			if pos.distance_to(b.pos) <= BTN_R * 1.5:
				held[finger] = b.action
				Input.action_press(b.action)
				return

func _draw_hud() -> void:
	var white := Color(1, 1, 1, ALPHA)
	canvas.draw_circle(center, RADIUS, Color(1, 1, 1, 0.10))
	canvas.draw_arc(center, RADIUS, 0, TAU, 40, white, 1.5)
	canvas.draw_circle(center + stick_off, 17.0, Color(1, 1, 1, 0.30 if stick_finger != -1 else 0.18))
	canvas.draw_arc(center + stick_off, 17.0, 0, TAU, 28, white, 1.5)
	var font := ThemeDB.fallback_font
	for b in buttons:
		var on: bool = held.values().has(b.action)
		canvas.draw_circle(b.pos, BTN_R, Color(1, 1, 1, 0.30 if on else 0.12))
		canvas.draw_arc(b.pos, BTN_R, 0, TAU, 28, white, 1.5)
		canvas.draw_string(font, b.pos + Vector2(-5, 5), b.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, white)
