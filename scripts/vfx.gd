class_name Vfx
extends RefCounted
## Efeitos de batalha feitos em código: brilho aditivo, partículas, anéis, arcos de golpe, círculo mágico.
## Cada habilidade tem o seu: fireball, ice, heal, holy, slash, cross_slash. Quem chama dá `await` e espera o tempo certo.

static var _add: CanvasItemMaterial
static var _beam: Texture2D

static func add_mat() -> CanvasItemMaterial:
	if _add == null:
		_add = CanvasItemMaterial.new()
		_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return _add

static func _wait(host: Node, sec: float) -> void:
	await host.get_tree().create_timer(sec).timeout

static func _beam_texture() -> Texture2D:
	if _beam == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(1, 0)
		t.width = 64
		t.height = 8
		_beam = t
	return _beam

# ---------- peças ----------

## Mancha de luz aditiva que cresce e some.
static func glow(host: Node, pos: Vector2, color: Color, size: float, life: float, grow := 1.6, z := 75) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = Fx.light_texture()
	s.material = add_mat()
	s.modulate = color
	s.position = pos
	s.scale = Vector2.ONE * (size / 256.0)
	s.z_index = z
	host.add_child(s)
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "modulate:a", 0.0, life)
	tw.tween_property(s, "scale", s.scale * grow, life)
	tw.chain().tween_callback(s.queue_free)
	return s

## Luz de verdade (ilumina o cenário) que se apaga.
static func flash_light(host: Node, pos: Vector2, color: Color, energy: float, radius: float, life: float) -> void:
	var l := Fx.make_light(host, pos, color, energy, radius)
	var tw := l.create_tween()
	tw.tween_property(l, "energy", 0.0, life)
	tw.tween_callback(l.queue_free)

static func sparks(host: Node, pos: Vector2, color: Color, amount: int, speed: float, life: float, gravity := Vector2(0, 160),
		size := 2.0, spread := 180.0, dir := Vector2.UP, additive := true) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = pos
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.direction = dir
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = gravity
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([color, Color(color.r, color.g, color.b, 0.0)])
	p.color_ramp = ramp
	if additive:
		p.material = add_mat()
	p.z_index = 76
	host.add_child(p)
	p.emitting = true
	host.get_tree().create_timer(life + 0.4).timeout.connect(p.queue_free)
	return p

## Anel achatado no chão (elipse) que se expande.
static func ring(host: Node, pos: Vector2, color: Color, r0: float, r1: float, life: float, squash := 0.42, width := 2.0, z := 74) -> void:
	var l := Line2D.new()
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * float(i) / 40.0
		pts.append(Vector2(cos(a), sin(a) * squash))
	l.points = pts
	l.width = width / maxf(r0, 1.0)
	l.default_color = color
	l.material = add_mat()
	l.position = pos
	l.scale = Vector2.ONE * r0
	l.z_index = z
	host.add_child(l)
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector2.ONE * r1, life).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, life)
	tw.chain().tween_callback(l.queue_free)

## Círculo mágico no chão sob quem conjura: dois anéis e uma estrela girando.
static func magic_circle(host: Node, pos: Vector2, color: Color, life: float) -> void:
	var flat := Node2D.new()
	flat.position = pos
	flat.scale = Vector2(1.0, 0.4)
	flat.z_index = -2
	flat.modulate.a = 0.0
	host.add_child(flat)
	var spin := Node2D.new()
	flat.add_child(spin)
	for r in [34.0, 28.0]:
		var c := Line2D.new()
		var pts := PackedVector2Array()
		for i in 49:
			pts.append(Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * r)
		c.points = pts
		c.width = 1.6
		c.default_color = color
		c.material = add_mat()
		spin.add_child(c)
	for k in 2:
		var star := Line2D.new()
		var pts2 := PackedVector2Array()
		for i in 4:
			var a := TAU * float(i) / 3.0 + PI / 6.0 * k
			pts2.append(Vector2(cos(a), sin(a)) * 28.0)
		star.points = pts2
		star.width = 1.4
		star.default_color = color
		star.material = add_mat()
		spin.add_child(star)
	for i in 8:
		var tick := Line2D.new()
		var a := TAU * float(i) / 8.0
		tick.points = PackedVector2Array([Vector2(cos(a), sin(a)) * 34.0, Vector2(cos(a), sin(a)) * 40.0])
		tick.width = 2.0
		tick.default_color = color
		tick.material = add_mat()
		spin.add_child(tick)
	var tw := flat.create_tween().set_parallel(true)
	tw.tween_property(spin, "rotation", PI * 1.5, life)
	tw.tween_property(flat, "modulate:a", 1.0, life * 0.25)
	tw.tween_property(flat, "modulate:a", 0.0, life * 0.3).set_delay(life * 0.7)
	tw.chain().tween_callback(flat.queue_free)

static func _crescent(r: float, a0: float, a1: float, thick: float) -> PackedVector2Array:
	var n := 16
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(Vector2(cos(a), sin(a)) * r)
	for i in range(n, -1, -1):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(Vector2(cos(a), sin(a)) * (r - thick * sin(PI * float(i) / n)))
	return pts

## Arco de golpe: a lâmina "desenha" o corte e ele se apaga. a0 e a1 em graus.
static func slash(host: Node, pos: Vector2, a0_deg: float, a1_deg: float, color: Color, r := 48.0, thick := 16.0, sweep := 0.12, fade := 0.22) -> void:
	var root := Node2D.new()
	root.position = pos
	root.z_index = 78
	root.material = add_mat()
	host.add_child(root)
	var outer := Polygon2D.new()
	outer.color = color
	var core := Polygon2D.new()
	core.color = Color(1, 1, 1, 0.95)
	root.add_child(outer)
	root.add_child(core)
	var a0 := deg_to_rad(a0_deg)
	var a1 := deg_to_rad(a1_deg)
	var tw := root.create_tween()
	tw.tween_method(func(p: float):
		var e := lerpf(a0, a1, p)
		outer.polygon = _crescent(r, a0, e, thick)
		core.polygon = _crescent(r - 1.5, a0, e, thick * 0.4), 0.02, 1.0, sweep)
	tw.tween_property(root, "modulate:a", 0.0, fade)
	tw.tween_callback(root.queue_free)

# ---------- habilidades ----------

## Bola de fogo: sai das mãos, desenha um arco, explode com brasas e fumaça.
static func fireball(host: Node, from: Vector2, to: Vector2) -> void:
	var proj := Node2D.new()
	proj.position = from
	proj.z_index = 77
	host.add_child(proj)
	for spec in [[34.0, Color(1.0, 0.45, 0.1, 0.8)], [18.0, Color(1.0, 0.8, 0.3, 1.0)], [8.0, Color(1, 1, 0.9, 1)]]:
		var s := Sprite2D.new()
		s.texture = Fx.light_texture()
		s.material = add_mat()
		s.modulate = spec[1]
		s.scale = Vector2.ONE * (float(spec[0]) / 256.0 * 2.0)
		proj.add_child(s)
	var trail := CPUParticles2D.new()
	trail.amount = 40
	trail.lifetime = 0.45
	trail.local_coords = false
	trail.direction = Vector2(0, 1)
	trail.spread = 40.0
	trail.initial_velocity_min = 5.0
	trail.initial_velocity_max = 30.0
	trail.gravity = Vector2(0, -40)
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 3.5
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(1, 0.85, 0.3, 1), Color(1, 0.35, 0.05, 0.7), Color(0.4, 0.1, 0.05, 0)])
	trail.color_ramp = ramp
	trail.material = add_mat()
	proj.add_child(trail)
	var lamp := Fx.make_light(proj, Vector2.ZERO, Color("#ff9a40"), 1.8, 110)
	var flight := 0.42
	var tw := proj.create_tween()
	tw.tween_method(func(p: float):
		proj.position = from.lerp(to, p) + Vector2(0, -sin(PI * p) * 34.0)
		proj.scale = Vector2.ONE * (0.7 + p * 0.6), 0.0, 1.0, flight).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	await tw.finished
	lamp.queue_free()
	proj.queue_free()
	# explosão
	glow(host, to, Color(1.0, 0.85, 0.5, 1.0), 220.0, 0.35, 1.5)
	glow(host, to, Color(1.0, 0.4, 0.1, 0.9), 320.0, 0.55, 1.4, 74)
	flash_light(host, to, Color("#ff8a30"), 3.0, 190, 0.6)
	ring(host, to + Vector2(0, 22), Color(1.0, 0.6, 0.2, 0.9), 10.0, 70.0, 0.4)
	ring(host, to + Vector2(0, 22), Color(1.0, 0.9, 0.5, 0.8), 6.0, 46.0, 0.3)
	sparks(host, to, Color(1.0, 0.7, 0.2, 1), 46, 190.0, 0.8, Vector2(0, 260), 3.0)
	sparks(host, to, Color(1.0, 0.3, 0.05, 1), 24, 110.0, 1.1, Vector2(0, -30), 4.5)
	sparks(host, to + Vector2(0, -4), Color(0.12, 0.08, 0.08, 0.8), 14, 60.0, 1.0, Vector2(0, -50), 6.0, 180.0, Vector2.UP, false)

## Gelo: lascas de gelo brotam do chão em volta do alvo, brilham e se estilhaçam.
static func ice(host: Node, at: Vector2) -> void:
	flash_light(host, at + Vector2(0, -30), Color("#7fd0ff"), 2.2, 170, 1.1)
	ring(host, at + Vector2(0, 22), Color(0.6, 0.9, 1.0, 0.9), 8.0, 64.0, 0.5)
	var shards: Array = []
	for i in 9:
		var base := Node2D.new()
		var ang := TAU * float(i) / 9.0 + randf_range(-0.2, 0.2)
		base.position = at + Vector2(cos(ang) * randf_range(14, 40), 22 + sin(ang) * randf_range(5, 14))
		base.scale = Vector2(1, 0)
		base.z_index = 76
		host.add_child(base)
		var h := randf_range(34.0, 70.0)
		var w := randf_range(5.0, 8.0)
		var dark := Polygon2D.new()
		dark.polygon = PackedVector2Array([Vector2(-w, 0), Vector2(-w * 0.5, -h * 0.7), Vector2(0, -h), Vector2(w * 0.6, -h * 0.6), Vector2(w, 0)])
		dark.color = Color("#4aa8e8")
		base.add_child(dark)
		var light := Polygon2D.new()
		light.polygon = PackedVector2Array([Vector2(-w * 0.5, 0), Vector2(-w * 0.2, -h * 0.65), Vector2(0, -h * 0.95), Vector2(w * 0.15, -h * 0.5)])
		light.color = Color("#d8f6ff")
		base.add_child(light)
		var tw := base.create_tween()
		tw.tween_interval(float(i) * 0.035)
		tw.tween_property(base, "scale", Vector2(1, 1), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		shards.append(base)
	sparks(host, at + Vector2(0, 10), Color(0.8, 0.95, 1.0, 0.9), 22, 40.0, 1.2, Vector2(0, -22), 2.0, 180.0, Vector2.UP)
	await _wait(host, 0.75)
	glow(host, at + Vector2(0, -20), Color(0.8, 0.95, 1.0, 1.0), 200.0, 0.3, 1.3)
	sparks(host, at + Vector2(0, -20), Color(0.75, 0.93, 1.0, 1), 40, 170.0, 0.7, Vector2(0, 300), 3.0)
	for s in shards:
		if is_instance_valid(s):
			s.queue_free()

## Cura: anéis de luz sobem pelo herói, folhas de luz verdes e douradas flutuam.
static func heal(host: Node, at: Vector2) -> void:
	magic_circle(host, at + Vector2(0, 6), Color(0.5, 1.0, 0.7, 0.9), 1.1)
	flash_light(host, at + Vector2(0, -34), Color("#70ffa8"), 2.0, 120, 1.2)
	glow(host, at + Vector2(0, -30), Color(0.5, 1.0, 0.7, 0.7), 150.0, 1.0, 1.3, 73)
	for i in 3:
		var y := 8.0 - float(i) * 22.0
		ring(host, at + Vector2(0, y), Color(0.7, 1.0, 0.8, 0.9), 22.0, 28.0, 0.5, 0.35, 2.0)
		await _wait(host, 0.16)
	for k in 2:
		var c := Color(0.55, 1.0, 0.7, 1) if k == 0 else Color(1.0, 0.95, 0.55, 1)
		var p := sparks(host, at + Vector2(0, 14), c, 24, 38.0, 1.2, Vector2(0, -36), 2.5, 45.0, Vector2.UP)
		p.explosiveness = 0.2
		p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 16.0

## Luz Sagrada: uma esfera cresce no alto, o raio cai, o chão acende e a luz sobe em fagulhas.
static func holy(host: Node, at: Vector2) -> void:
	var top := at.y - 160.0
	magic_circle(host, at + Vector2(0, 22), Color(1.0, 0.9, 0.5, 0.9), 1.2)
	var orb := glow(host, Vector2(at.x, top + 50), Color(1.0, 0.95, 0.7, 0.9), 70.0, 0.5, 1.8)
	flash_light(host, Vector2(at.x, top + 40), Color("#fff0a0"), 1.6, 120, 0.6)
	await _wait(host, 0.4)
	var beam := Sprite2D.new()
	beam.texture = _beam_texture()
	beam.material = add_mat()
	beam.modulate = Color(1.0, 0.95, 0.65, 1.0)
	beam.centered = false
	beam.offset = Vector2(-32, 0)
	beam.position = Vector2(at.x, top)
	beam.scale = Vector2(0.2, (at.y + 26.0 - top) / 8.0)
	beam.z_index = 77
	host.add_child(beam)
	var core := Sprite2D.new()
	core.texture = _beam_texture()
	core.material = add_mat()
	core.modulate = Color(1, 1, 1, 1)
	core.centered = false
	core.offset = Vector2(-32, 0)
	core.position = beam.position
	core.scale = Vector2(0.08, beam.scale.y)
	core.z_index = 78
	host.add_child(core)
	var tw := beam.create_tween().set_parallel(true)
	tw.tween_property(beam, "scale:x", 1.5, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(core, "scale:x", 0.5, 0.1)
	tw.chain().tween_property(beam, "scale:x", 0.9, 0.5)
	tw.parallel().tween_property(core, "scale:x", 0.3, 0.5)
	tw.chain().tween_property(beam, "modulate:a", 0.0, 0.35)
	tw.parallel().tween_property(core, "modulate:a", 0.0, 0.35)
	tw.chain().tween_callback(beam.queue_free)
	tw.tween_callback(core.queue_free)
	flash_light(host, at + Vector2(0, -40), Color("#fff2b0"), 3.2, 220, 1.0)
	glow(host, at + Vector2(0, 20), Color(1.0, 0.95, 0.6, 1.0), 260.0, 0.5, 1.3)
	ring(host, at + Vector2(0, 22), Color(1.0, 0.95, 0.6, 1.0), 12.0, 80.0, 0.5)
	ring(host, at + Vector2(0, 22), Color(1.0, 1.0, 0.9, 0.9), 6.0, 52.0, 0.35)
	var rise := sparks(host, at + Vector2(0, 20), Color(1.0, 0.95, 0.55, 1), 40, 60.0, 1.2, Vector2(0, -90), 2.6, 25.0, Vector2.UP)
	rise.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	rise.emission_sphere_radius = 26.0
	rise.explosiveness = 0.4
	await _wait(host, 0.2)

## Golpe de espada: arco largo mais fagulhas de aço.
static func sword_hit(host: Node, at: Vector2, heavy := false) -> void:
	if heavy:
		slash(host, at + Vector2(10, 4), -125.0, 55.0, Color(1.0, 0.75, 0.3, 0.95), 58.0, 22.0, 0.14, 0.3)
		glow(host, at, Color(1.0, 0.8, 0.4, 1.0), 200.0, 0.3, 1.4)
		ring(host, at + Vector2(0, 26), Color(1.0, 0.8, 0.4, 0.9), 8.0, 60.0, 0.3)
		sparks(host, at, Color(1.0, 0.85, 0.5, 1), 34, 210.0, 0.5, Vector2(0, 280), 2.6)
	else:
		slash(host, at, -30.0, 120.0, Color(0.75, 0.9, 1.0, 0.9), 44.0, 12.0)
		sparks(host, at, Color(0.9, 0.95, 1.0, 1), 16, 150.0, 0.4, Vector2(0, 220), 2.0)

## Risco reto e afilado (um corte de adaga) que se abre do centro para as pontas e se apaga.
static func streak(host: Node, at: Vector2, angle_deg: float, length: float, color: Color, width := 5.0) -> void:
	var root := Node2D.new()
	root.position = at
	root.rotation = deg_to_rad(angle_deg)
	root.scale = Vector2(0.1, 1.0)
	root.z_index = 78
	root.material = add_mat()
	host.add_child(root)
	for spec in [[width, color], [width * 0.4, Color(1, 1, 1, 0.95)]]:
		var w: float = spec[0]
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([Vector2(-length * 0.5, 0), Vector2(0, -w), Vector2(length * 0.5, 0), Vector2(0, w)])
		poly.color = spec[1]
		root.add_child(poly)
	var tw := root.create_tween()
	tw.tween_property(root, "scale:x", 1.0, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(root, "modulate:a", 0.0, 0.22)
	tw.tween_callback(root.queue_free)

## Dois cortes em X (Golpe Baixo) com um clarão.
static func cross_slash(host: Node, at: Vector2) -> void:
	streak(host, at, 35.0, 92.0, Color(0.9, 0.55, 1.0, 0.95))
	await _wait(host, 0.1)
	streak(host, at, -35.0, 92.0, Color(0.6, 0.9, 1.0, 0.95))
	glow(host, at, Color(0.85, 0.7, 1.0, 1.0), 170.0, 0.3, 1.3)
	sparks(host, at, Color(0.95, 0.85, 1.0, 1), 26, 190.0, 0.5, Vector2(0, 240), 2.2)

## Rastro de imagem residual atrás de quem corre (Andilla).
static func afterimage(host: Node, sprite: AnimatedSprite2D, color: Color, life := 0.3) -> void:
	var g := Sprite2D.new()
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	g.texture = tex
	g.centered = false
	g.offset = sprite.offset
	g.flip_h = sprite.flip_h
	g.global_position = sprite.global_position
	g.modulate = Color(color.r, color.g, color.b, 0.55)
	g.material = add_mat()
	g.z_index = 40
	host.add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, life)
	tw.tween_callback(g.queue_free)

## Pilar de luz que cai sobre um aliado: um fio fino que se abre numa coluna, com brilho na base.
static func pillar(host: Node, at: Vector2, color: Color, hold := 0.7) -> void:
	var top := at.y - 280.0
	var col := Sprite2D.new()
	col.texture = _beam_texture()
	col.material = add_mat()
	col.modulate = Color(color, 0.7)
	col.centered = false
	col.offset = Vector2(-32, 0)
	col.position = Vector2(at.x, top)
	col.scale = Vector2(0.03, (at.y + 6.0 - top) / 8.0)
	col.z_index = 77
	host.add_child(col)
	var tw := col.create_tween()
	tw.tween_property(col, "scale:x", 0.1, 0.25)
	tw.tween_property(col, "scale:x", 0.55, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(col, "modulate:a", 0.0, 0.3)
	tw.tween_callback(col.queue_free)
	glow(host, at + Vector2(0, 2), Color(color, 0.45), 100.0, 0.9, 1.2, 76)
	flash_light(host, at + Vector2(0, -20), color, 1.2, 80, 1.0)
	ring(host, at + Vector2(0, 2), color, 8.0, 34.0, 0.6)
	var rise := sparks(host, at + Vector2(0, 4), color, 18, 40.0, 1.0, Vector2(0, -60), 2.0, 20.0, Vector2.UP)
	rise.explosiveness = 0.3

## Fumaça de sombra: nuvem escura com um brilho roxo (a Andilla some e aparece nela).
static func smoke(host: Node, pos: Vector2) -> void:
	glow(host, pos, Color(0.55, 0.3, 0.9, 0.8), 130.0, 0.4, 1.4)
	ring(host, pos + Vector2(0, 14), Color(0.6, 0.35, 1.0, 0.8), 6.0, 30.0, 0.35)
	sparks(host, pos, Color(0.1, 0.05, 0.16, 0.9), 22, 70.0, 0.7, Vector2(0, -30), 7.0, 180.0, Vector2.UP, false)
	sparks(host, pos, Color(0.7, 0.4, 1.0, 1), 16, 90.0, 0.5, Vector2(0, -20), 2.0)

## Mancha de sombra que desliza pelo chão de um ponto a outro, deixando fagulhas roxas.
static func shadow_streak(host: Node, from: Vector2, to: Vector2, dur: float) -> void:
	var s := Sprite2D.new()
	s.texture = Fx.shadow_texture()
	s.scale = Vector2(1.0, 0.45)
	s.modulate = Color(0.45, 0.2, 0.75, 1.0)
	s.position = from + Vector2(0, 2)
	s.z_index = 5
	host.add_child(s)
	var trail := CPUParticles2D.new()
	trail.amount = 30
	trail.lifetime = 0.5
	trail.local_coords = false
	trail.direction = Vector2(0, -1)
	trail.spread = 60.0
	trail.initial_velocity_min = 4.0
	trail.initial_velocity_max = 24.0
	trail.gravity = Vector2(0, -20)
	trail.scale_amount_min = 1.5
	trail.scale_amount_max = 3.0
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.75, 0.45, 1, 1), Color(0.3, 0.1, 0.5, 0)])
	trail.color_ramp = ramp
	trail.material = add_mat()
	s.add_child(trail)
	var tw := s.create_tween()
	tw.tween_property(s, "position", to + Vector2(0, 2), dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	s.queue_free()
