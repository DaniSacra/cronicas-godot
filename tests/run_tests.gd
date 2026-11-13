extends SceneTree
## Testes de lógica pura. Rodar: godot --headless --path . --script tests/run_tests.gd
const C := preload("res://scripts/controls.gd")
const R := preload("res://scripts/battle_rules.gd")
var fails := 0

func check(name: String, cond: bool) -> void:
	print(("ok   " if cond else "FAIL ") + name)
	if not cond:
		fails += 1

func _init() -> void:
	check("combine picks the stronger vector", C.combine(Vector2(0.2, 0), Vector2(0, -0.9)) == Vector2(0, -0.9))
	check("combine never exceeds length 1", C.combine(Vector2(3, 4), Vector2.ZERO).length() <= 1.0001)
	check("combine of two zeros is zero", C.combine(Vector2.ZERO, Vector2.ZERO) == Vector2.ZERO)
	check("stick inside dead zone is zero", C.stick_vector(Vector2(50, 50), Vector2(52, 51), 46.0) == Vector2.ZERO)
	check("stick at the rim is a unit vector", C.stick_vector(Vector2.ZERO, Vector2(46, 0), 46.0).is_equal_approx(Vector2(1, 0)))
	check("stick beyond the rim is clamped", C.stick_vector(Vector2.ZERO, Vector2(0, 400), 46.0).is_equal_approx(Vector2(0, 1)))
	check("stick half way is half strength", absf(C.stick_vector(Vector2.ZERO, Vector2(-23, 0), 46.0).x + 0.5) < 0.001)
	# regras da batalha (portadas de src/party.js)
	check("hero stat follows base + grow x (lv-1)", R.stat("aldo", 5, "atk") == 25 and R.stat("lyra", 1, "hp") == 30)
	check("defense cuts about a quarter at 25 points", absf(R.cut_pct(25.0) - 25.0) < 0.001)
	check("cut never reaches the maximum", R.cut_pct(100000.0) < 80.0)
	check("phys damage never below 1", R.phys_dmg(1, 9999) == 1)
	check("phys damage example (atk 25 vs def 25)", R.phys_dmg(25, 25) == 19)
	check("piercing ignores defense", R.skill_damage(R.SKILLS.golpeBaixo, 20, 0, 25, 0, false) == 26)
	check("holy doubles against the undead", R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, true) == 2 * R.skill_damage(R.SKILLS.luz, 0, 10, 0, 0, false))
	check("heal amount", R.heal_amount(R.SKILLS.cura, 10) == 40)
	check("boss cycle: hit, drain, hit, bell", [R.boss_move(0, 1.0), R.boss_move(1, 1.0), R.boss_move(2, 1.0), R.boss_move(3, 1.0)] == ["hit", "drain", "hit", "bell"])
	check("enraged boss rings the bell more often", R.boss_move(2, 0.3) == "bell")
	check("enraged boss hits harder", R.boss_atk(24, 0.3) > R.boss_atk(24, 1.0))
	check("cannot pay without enough energy", not R.can_pay(R.SKILLS.golpe, 0, 10) and R.can_pay(R.SKILLS.golpe, 0, 20))
	# combo
	check("combo points are capped", R.combo_gain(7, 3) == R.COMBO_MAX and R.combo_gain(0) == 1)
	check("combo needs enough points", not R.combo_ready("corte", 2, ["aldo", "andilla"]) and R.combo_ready("corte", 3, ["aldo", "andilla"]))
	check("combo needs both members alive", not R.combo_ready("corte", 8, ["aldo"]) and R.combo_ready("escudo", 4, ["teo", "lyra", "aldo"]))
	check("combo damage beats one plain hit", R.combo_damage(25, 20, 25) > R.phys_dmg(25, 25))
	check("shield combo heals 40 percent", R.combo_heal(50) == 20)
	check("boss forecast follows the cycle", R.boss_forecast(0, 1.0) == ["hit", "drain", "hit"])
	quit(1 if fails > 0 else 0)
