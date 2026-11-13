extends Node
## Camada única de comandos: teclado, controle e toque chamam as mesmas ações.
## O jogo nunca lê tecla direto: pergunta a `Controls`.

signal touch_mode_changed(on: bool)

const KEYS := {
	"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
	"move_up": [KEY_W, KEY_UP], "move_down": [KEY_S, KEY_DOWN],
	"confirm": [KEY_ENTER, KEY_SPACE, KEY_E], "cancel": [KEY_ESCAPE, KEY_BACKSPACE], "menu": [KEY_TAB, KEY_M],
}
const PAD_BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
	"confirm": [JOY_BUTTON_A], "cancel": [JOY_BUTTON_B], "menu": [JOY_BUTTON_Y, JOY_BUTTON_START],
}
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0], "move_down": [JOY_AXIS_LEFT_Y, 1.0],
}

var touch_vec := Vector2.ZERO        # o joystick virtual escreve aqui
var is_touch := false
var forced := false                  # --touch ou ?touch=1: mantém a interface de toque mesmo com teclado

## O vetor de maior força vence (teclado, controle ou joystick virtual), com tamanho no máximo 1.
static func combine(a: Vector2, b: Vector2) -> Vector2:
	var v := a if a.length() >= b.length() else b
	return v.limit_length(1.0)

## Posição do dedo -> vetor do joystick, com zona morta no centro.
static func stick_vector(center: Vector2, pos: Vector2, radius: float, dead := 0.15) -> Vector2:
	var d := (pos - center) / radius
	if d.length() < dead:
		return Vector2.ZERO
	return d.limit_length(1.0)

func _ready() -> void:
	for action in KEYS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		for b in PAD_BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = b
			InputMap.action_add_event(action, jb)
		if PAD_AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = PAD_AXES[action][0]
			jm.axis_value = PAD_AXES[action][1]
			InputMap.action_add_event(action, jm)
	forced = "--touch" in OS.get_cmdline_user_args()
	is_touch = forced or _detect_touch()

func _detect_touch() -> bool:
	if OS.has_feature("web"):
		return bool(JavaScriptBridge.eval("(navigator.maxTouchPoints || 0) > 0 || ('ontouchstart' in window)"))
	return DisplayServer.is_touchscreen_available()

func move_vector() -> Vector2:
	return combine(Input.get_vector("move_left", "move_right", "move_up", "move_down"), touch_vec)

func _input(e: InputEvent) -> void:
	# a interface de toque aparece no primeiro toque e some quando o jogador usa teclado ou controle
	var now := is_touch
	if e is InputEventScreenTouch:
		now = true
	elif (e is InputEventKey or e is InputEventJoypadButton) and not forced:
		now = false
	if now != is_touch:
		is_touch = now
		touch_mode_changed.emit(is_touch)
