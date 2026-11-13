extends Node
## Som do jogo (autoload "Audio"). Nenhuma cena cria AudioStreamPlayer: pede aqui pelo nome (AudioRules.SOUNDS).
## Barramentos em default_bus_layout.tres (Master, Music, Ambience, SFX, UI); volumes em AudioRules.BUS_DB mais as
## opções de Game.options ("music" e "sfx", 0 a 10). Ducking por tween do volume do barramento Music, não por
## compressor: na Web os efeitos de barramento não rodam e o tween funciona igual nos três alvos.
## Sem som (`silent`): --auto, --mute, ou máquina sem placa (driver Dummy, como no headless e no xvfb). Nomes e
## arquivos continuam sendo resolvidos e carregados (erro de nome aparece no log), só não toca. --sound força tocar
## mesmo no Dummy (com --write-movie é como se mede a mixagem do jogo montado). --audio-log (na web, ?audiolog) imprime cada som.
## Navegador: música e ambiente esperam o primeiro toque ou tecla (AudioRules.may_start).

const A := preload("res://scripts/audio_rules.gd")

var loops := {}               # "music" / "amb" -> {"players": [2], "cur": 0, "name": ""}
var voices := {}              # barramento -> [AudioStreamPlayer]
var started := {}             # barramento -> [segundos em que cada voz começou]
var duck_db := 0.0
var duck_tw: Tween
var web := false
var unlocked := false
var pending := {}             # no navegador, antes do primeiro toque: "music"/"amb" -> nome
var log_on := false
var cache := {}
var silent := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS          # menus de pausa também soam
	var args := OS.get_cmdline_user_args()
	web = OS.has_feature("web")
	log_on = "--audio-log" in args or (web and str(JavaScriptBridge.eval("location.search")).contains("audiolog"))
	for bus in A.BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			push_error("Audio: barramento '%s' não existe (default_bus_layout.tres)" % bus)
	var dummy := AudioServer.get_driver_name() == "Dummy"
	silent = "--auto" in args or "--mute" in args or (dummy and not "--sound" in args)
	_log("driver", "%s silent=%s" % [AudioServer.get_driver_name(), silent])
	for kind in ["music", "amb"]:
		var ps := [_player("Music" if kind == "music" else "Ambience"), _player("Music" if kind == "music" else "Ambience")]
		loops[kind] = {"players": ps, "cur": 0, "name": ""}
	for bus in A.MAX_VOICES:
		voices[bus] = []
		started[bus] = []
		for i in A.MAX_VOICES[bus]:
			voices[bus].append(_player(bus))
			started[bus].append(0.0)
	apply_options()
	UI.sound = func(n: String): sfx(n)

func _exit_tree() -> void:
	UI.sound = Callable()          # a variável estática não pode segurar este nó depois que ele sai
	for p in get_children():       # ao sair do jogo com som tocando, o servidor de áudio prenderia as reproduções
		if p is AudioStreamPlayer:
			p.stop()
	cache.clear()

## Sair do jogo: para tudo e espera o mixer soltar as reproduções antes de fechar (senão o Godot avisa de recursos
## presos na saída). Os botões "Sair" chamam isto no lugar de get_tree().quit().
func quit() -> void:
	for p in get_children():
		if p is AudioStreamPlayer:
			p.stop()
	cache.clear()
	await get_tree().create_timer(0.25, true, false, true).timeout
	get_tree().quit()

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

func _stream(name: String) -> AudioStream:
	if cache.has(name):
		return cache[name]
	var path := A.path(name)
	var s: AudioStream = load(path) if path != "" and ResourceLoader.exists(path) else null
	if s == null:
		push_error("Audio: som '%s' não encontrado (%s)" % [name, path])
		return null
	if A.loops(name) and "loop" in s:
		s.loop = true                                     # o Vorbis importa sem laço
	cache[name] = s
	return s

func _log(kind: String, name: String) -> void:
	if log_on:
		print("AUDIO ", kind, " ", name)

# ---------- opções e ducking ----------

## Volumes dos barramentos a partir de Game.options. A camada de save chama isto depois de carregar as opções.
func apply_options() -> void:
	for bus in A.BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var level: int = Game.options.get(A.option_of(bus), A.DEFAULT_LEVEL)
			AudioServer.set_bus_volume_db(idx, A.bus_db(bus, level, duck_db))

## A música desce durante a habilidade especial e volta depois.
func duck(on: bool) -> void:
	if duck_tw != null:
		duck_tw.kill()
	duck_tw = create_tween().set_ignore_time_scale(true)
	duck_tw.tween_method(func(v: float):
		duck_db = v
		apply_options(), duck_db, A.DUCK_DB if on else 0.0, A.DUCK_IN if on else A.DUCK_OUT)
	_log("duck", str(on))

# ---------- música e ambiente (laço, fade cruzado) ----------

## Toca a música `name` em laço. A mesma música que já toca continua sem recomeçar. `delay`: em tempo de jogo.
func music(name: String, fade := A.XFADE, delay := 0.0) -> void:
	_loop("music", name, fade, delay)

func music_stop(fade := A.XFADE) -> void:
	_loop("music", "", fade, 0.0)

func amb(name: String, fade := 1.0) -> void:
	_loop("amb", name, fade, 0.0)

func amb_stop(fade := 1.0) -> void:
	_loop("amb", "", fade, 0.0)

func _loop(kind: String, name: String, fade: float, delay: float) -> void:
	var L: Dictionary = loops[kind]
	if name == L.name:
		return
	L.name = name
	if not A.may_start(web, unlocked):
		pending[kind] = name
		return
	if delay > 0.0:
		await get_tree().create_timer(delay, false).timeout
		if L.name != name:
			return                                        # trocou de ideia enquanto esperava
	var old: AudioStreamPlayer = L.players[L.cur]
	if old.playing:
		_fade(old, A.MUTE_DB, fade, true)
	_log(kind, name if name != "" else "stop")
	if name == "":
		return
	var s := _stream(name)
	if s == null or silent:
		return
	L.cur = 1 - L.cur
	var p: AudioStreamPlayer = L.players[L.cur]
	p.stream = s
	p.volume_db = A.MUTE_DB if fade > 0.0 else 0.0
	p.play()
	if fade > 0.0:
		_fade(p, 0.0, fade, false)

func _fade(p: AudioStreamPlayer, to_db: float, sec: float, stop_after: bool) -> void:
	if p.has_meta("tw"):
		var old: Tween = p.get_meta("tw")
		old.kill()
	if sec <= 0.0:
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(p, "volume_db", to_db, sec)
	if stop_after:
		tw.tween_callback(p.stop)
	p.set_meta("tw", tw)

# ---------- efeitos ----------

## Toca um efeito numa voz livre do barramento dele (ou corta a mais velha). Devolve o player, para `stop`.
## `db`: ajuste em cima do arquivo; `pitch`: 1 = original.
func sfx(name: String, db := 0.0, pitch := 1.0) -> AudioStreamPlayer:
	if web and not unlocked:
		return null
	var s := _stream(name)
	if name != "digitar":
		_log("sfx", name)
	if s == null or silent:
		return null
	var bus := A.bus_of(name)
	if not voices.has(bus):
		bus = "SFX"                                       # jingles: uma voz de efeito no barramento da música
	var busy: Array = voices[bus].map(func(v): return v.playing)
	var i := A.pick_voice(busy, started[bus])
	var p: AudioStreamPlayer = voices[bus][i]
	if p.has_meta("tw"):
		var old: Tween = p.get_meta("tw")
		old.kill()
	p.bus = A.bus_of(name)
	p.stream = s
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()
	started[bus][i] = Time.get_ticks_msec() / 1000.0
	return p

## Efeito com atraso em tempo de jogo (acompanha o --fast e para com a pausa), para casar o pico com a imagem.
func sfx_later(name: String, delay: float, db := 0.0, pitch := 1.0) -> void:
	await get_tree().create_timer(delay, false).timeout
	sfx(name, db, pitch)

## Corta um efeito com fade curto (a carga quando o jogador solta antes).
func stop(p: AudioStreamPlayer, fade := 0.05) -> void:
	if p != null and p.playing:
		_log("cut", p.stream.resource_path.get_file())
		_fade(p, A.MUTE_DB, fade, true)

# ---------- navegador: o som liga no primeiro toque ou tecla ----------

func _input(e: InputEvent) -> void:
	if unlocked or not e.is_pressed():
		return
	if e is InputEventKey or e is InputEventMouseButton or e is InputEventScreenTouch or e is InputEventJoypadButton:
		unlocked = true
		for kind in pending:
			var name: String = pending[kind]
			loops[kind].name = ""
			_loop(kind, name, 1.0, 0.0)
		pending.clear()
