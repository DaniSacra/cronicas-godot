class_name Fx
extends RefCounted
## Ferramentas visuais compartilhadas pelas cenas: luz, sombra e os quadros dos heróis.

## Orçamento do celular: as luzes 2D e as partículas são o que mais pesa no GL Compatibility.
const MAX_LIGHTS_TOUCH := 6          # luzes fixas do cenário acesas no toque (as primeiras da lista, por prioridade)
const PARTICLES_TOUCH := 0.5         # fração das partículas no toque

static var _light: Texture2D
static var _shadow: Texture2D
static var _frames: Dictionary = {}
static var _rim: Shader

static func _radial(alpha0: float, size: int) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, alpha0))
	g.set_color(1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = size
	tex.height = size
	return tex

static func light_texture() -> Texture2D:
	if _light == null:
		_light = _radial(1.0, 256)
	return _light

static func shadow_texture() -> Texture2D:
	if _shadow == null:
		var t := _radial(0.55, 64)
		t.gradient.set_color(0, Color(0, 0, 0, 0.55))
		t.gradient.set_color(1, Color(0, 0, 0, 0))
		_shadow = t
	return _shadow

## A luz fixa de índice `i` fica acesa? No toque só as MAX_LIGHTS_TOUCH primeiras.
static func light_on(i: int, touch: bool) -> bool:
	return not touch or i < MAX_LIGHTS_TOUCH

## Quantidade de partículas de um efeito: a metade no toque, nunca menos de 1.
static func particles(n: int, touch: bool) -> int:
	return maxi(1, roundi(n * PARTICLES_TOUCH)) if touch else n

static func make_light(parent: Node, pos: Vector2, color: Color, energy: float, radius: float) -> PointLight2D:
	var l := PointLight2D.new()
	l.texture = light_texture()
	l.texture_scale = radius / 128.0
	l.color = color
	l.energy = energy
	l.position = pos
	parent.add_child(l)
	return l

## Material de contorno colorido (luz fria em cima, quente embaixo) para dar volume aos sprites.
static func rim_material(cool := Color(0.45, 0.7, 1.0), warm := Color(1.0, 0.55, 0.25), strength := 0.6) -> ShaderMaterial:
	if _rim == null:
		_rim = load("res://scripts/rim.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _rim
	m.set_shader_parameter("rim_cool", cool)
	m.set_shader_parameter("rim_warm", warm)
	m.set_shader_parameter("strength", strength)
	return m

## Heróis no desenho novo (assets/heroes2): quadros de 64x64 virados para a direita, o pé fica num ponto fixo.
const NEW_FEET := {"aldo": Vector2(-38, -62), "lyra": Vector2(-37, -60), "andilla": Vector2(-35, -63), "teo": Vector2(-36, -62)}
const NEW_ANIMS := [["stance", 8.0, true], ["walk", 14.0, true], ["attack", 14.0, false], ["heavy", 11.0, false], ["cast", 10.0, false],
	["slashx", 14.0, false], ["defend", 10.0, false], ["hurt", 14.0, false], ["fall", 9.0, false]]

static func new_art(hero: String) -> bool:
	return hero != "" and ResourceLoader.exists("res://assets/heroes2/%s/stance/frame_000.png" % hero)

static func _new_frames(hero: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for spec in NEW_ANIMS:
		var name: String = spec[0]
		sf.add_animation(name)
		sf.set_animation_speed(name, spec[1])
		sf.set_animation_loop(name, spec[2])
		var i := 0
		while true:
			var p := "res://assets/heroes2/%s/%s/frame_%03d.png" % [hero, name, i]
			if not ResourceLoader.exists(p):
				break
			sf.add_frame(name, load(p))
			i += 1
	# idle e dash usam os mesmos quadros do stance e do walk
	for pair in [["idle", "stance"], ["dash", "walk"]]:
		sf.add_animation(pair[0])
		sf.set_animation_speed(pair[0], sf.get_animation_speed(pair[1]))
		sf.set_animation_loop(pair[0], true)
		for k in sf.get_frame_count(pair[1]):
			sf.add_frame(pair[0], sf.get_frame_texture(pair[1], k))
	return sf

## Centro do rosto em cada quadro de 64x64 do desenho novo.
const FACE_CENTER := {"aldo": Vector2(38, 12), "lyra": Vector2(41, 16), "teo": Vector2(38, 16), "andilla": Vector2(41, 17)}

## Rosto recortado em 1:1 do quadro parado: 22x22 na carta de status; 32x32 é o retrato provisório do diálogo
## (mostrado em 2x, 64x64, decisão C9), preso dentro do quadro de 64x64.
static func face_texture(hero: String, size := 22) -> Texture2D:
	var atlas := AtlasTexture.new()
	if new_art(hero):
		atlas.atlas = load("res://assets/heroes2/%s/stance/frame_000.png" % hero)
		var tl: Vector2 = (FACE_CENTER[hero] - Vector2(size, size) / 2.0).clamp(Vector2.ZERO, Vector2(64 - size, 64 - size))
		atlas.region = Rect2(tl.floor(), Vector2(size, size))
	else:
		atlas.atlas = load("res://assets/heroes/%s/rot_south.png" % hero)
		atlas.region = Rect2(12, 3, 32, 30)
	return atlas

## Os quadros de ataque feitos no modo v3 têm 88x88 (o idle tem 56x72): o pé fica em outro ponto do quadro.
const BIG_ANIMS := ["attack", "heavy", "slashx"]
const STANCE_OFFSET := {"aldo": Vector2(-45, -84), "lyra": Vector2(-43, -77), "teo": Vector2(-43, -77), "andilla": Vector2(-41, -77)}
const IDLE_OFFSET := Vector2(-28, -66)
const BIG_OFFSET := Vector2(-42, -77)

static func anim_offset(anim: String, hero := "") -> Vector2:
	if new_art(hero):
		return NEW_FEET[hero]
	if anim == "stance" and STANCE_OFFSET.has(hero):
		return STANCE_OFFSET[hero]
	return BIG_OFFSET if anim in BIG_ANIMS else IDLE_OFFSET

## Quadros de um herói: idle e walk (olhando para leste), hurt e fall (arquivos olham para oeste: use flip_h),
## e as quatro rotações paradas.
## `legacy`: a exploração ainda usa o desenho antigo (o novo só tem poses de lado, sem as 4 direções).
static func hero_frames(hero: String, legacy := false) -> SpriteFrames:
	var key := hero + ("_old" if legacy else "")
	if _frames.has(key):
		return _frames[key]
	if new_art(hero) and not legacy:
		_frames[key] = _new_frames(hero)
		return _frames[key]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for spec in [["idle", "idle_east", 5.0, true], ["walk", "walk_east", 11.0, true], ["hurt", "hurt_west", 12.0, false], ["fall", "fall_west", 9.0, false],
			["cast", "cast_east", 9.0, false], ["defend", "defend_east", 8.0, false], ["dash", "dash_east", 12.0, true],
			["attack", "attack_east", 15.0, false], ["heavy", "heavy_east", 11.0, false], ["slashx", "slashx_east", 15.0, false],
			["stance", "combat_east", 7.0, true]]:
		sf.add_animation(spec[0])
		sf.set_animation_speed(spec[0], spec[2])
		sf.set_animation_loop(spec[0], spec[3])
		var i := 0
		while true:
			var p := "res://assets/heroes/%s/%s/frame_%03d.png" % [hero, spec[1], i]
			if not ResourceLoader.exists(p):
				break
			sf.add_frame(spec[0], load(p))
			i += 1
	for d in ["south", "north", "east", "west"]:
		sf.add_animation("face_" + d)
		sf.add_frame("face_" + d, load("res://assets/heroes/%s/rot_%s.png" % [hero, d]))
	_frames[key] = sf
	return sf

## O Sineiro no desenho novo (assets/sineiro2): parado em loop, golpe de sino e badalada.
static func sineiro_frames() -> SpriteFrames:
	if _frames.has("sineiro"):
		return _frames["sineiro"]
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	for spec in [["stance", 8.0, true], ["heavy", 11.0, false], ["special", 10.0, false]]:
		sf.add_animation(spec[0])
		sf.set_animation_speed(spec[0], spec[1])
		sf.set_animation_loop(spec[0], spec[2])
		var i := 0
		while ResourceLoader.exists("res://assets/sineiro2/%s/frame_%03d.png" % [spec[0], i]):
			sf.add_frame(spec[0], load("res://assets/sineiro2/%s/frame_%03d.png" % [spec[0], i]))
			i += 1
	_frames["sineiro"] = sf
	return sf
