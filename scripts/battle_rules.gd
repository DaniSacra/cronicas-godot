class_name BattleRules
extends RefCounted
## Regras da batalha, em funções puras (sem cena, sem sorteio escondido), portadas de src/party.js do jogo em JS.
## O sorteio entra por parâmetro para os testes serem exatos.

const GUARD_MAX := 80.0
const GUARD_HALF := 55.0

const HEROES := {
	"aldo": {"name": "Aldo", "cls": "Guerreiro", "color": "#e0a040", "energy": true,
		"base": {"hp": 48, "mp": 0, "atk": 13, "def": 22.5, "res": 4, "mag": 3, "agi": 7},
		"grow": {"hp": 10, "mp": 0, "atk": 3, "def": 5, "res": 1, "mag": 0.5, "agi": 1}, "skills": ["golpe"]},
	"lyra": {"name": "Lyra", "cls": "Maga", "color": "#d070e0", "energy": false,
		"base": {"hp": 30, "mp": 20, "atk": 6, "def": 10, "res": 12, "mag": 12, "agi": 10},
		"grow": {"hp": 5, "mp": 4, "atk": 1, "def": 2.5, "res": 3, "mag": 3, "agi": 1.2}, "skills": ["fogo", "gelo"]},
	"teo": {"name": "Teo", "cls": "Clérigo", "color": "#60d0a0", "energy": false,
		"base": {"hp": 36, "mp": 16, "atk": 9, "def": 15, "res": 10, "mag": 9, "agi": 6},
		"grow": {"hp": 7, "mp": 3, "atk": 2, "def": 3.75, "res": 3, "mag": 2, "agi": 1}, "skills": ["cura", "luz"]},
	"andilla": {"name": "Andilla", "cls": "Ladina", "color": "#e05a5a", "energy": true,
		"base": {"hp": 34, "mp": 0, "atk": 11, "def": 12.5, "res": 6, "mag": 4, "agi": 14},
		"grow": {"hp": 6, "mp": 0, "atk": 2.5, "def": 3, "res": 2, "mag": 0.5, "agi": 1.6}, "skills": ["golpeBaixo"]},
}

# cost_kind: "mp" ou "en" (Energia, que só existe em batalha)
const SKILLS := {
	"golpe": {"name": "Golpe Forte", "kind": "phys", "cost_kind": "en", "cost": 20, "power": 1.4, "target": "enemy"},
	"golpeBaixo": {"name": "Passo das Sombras", "kind": "phys", "cost_kind": "en", "cost": 20, "power": 1.3, "pierce": true, "target": "enemy"},
	"fogo": {"name": "Fogo", "kind": "mag", "cost_kind": "mp", "cost": 4, "power": 2.2, "base": 8, "target": "enemy"},
	"gelo": {"name": "Gelo", "kind": "mag", "cost_kind": "mp", "cost": 8, "power": 1.4, "base": 6, "target": "enemy"},
	"cura": {"name": "Cura", "kind": "heal", "cost_kind": "mp", "cost": 3, "power": 2.0, "base": 20, "target": "ally"},
	"luz": {"name": "Luz Sagrada", "kind": "holy", "cost_kind": "mp", "cost": 5, "power": 2.0, "base": 10, "target": "enemy"},
}

const ENERGY := {"max": 100, "start": 10, "attack": 15, "defend": 10, "hurt_aldo": 8}

# O Sineiro (src/data.js)
const SINEIRO := {"name": "O Sineiro", "hp": 900, "atk": 30, "def": 25, "res": 10, "agi": 11, "undead": true}

static func stat(hero_id: String, lv: int, key: String, bonus := 0) -> int:
	var d: Dictionary = HEROES[hero_id]
	return int(floor(d.base[key] + d.grow[key] * (lv - 1))) + bonus

static func cut_pct(points: float) -> float:
	var p := maxf(0.0, points)
	return GUARD_MAX * p / (p + GUARD_HALF)

static func guard_cut(points: float) -> float:
	return 1.0 - cut_pct(points) / 100.0

static func phys_dmg(atk: float, def: float, power := 1.0, v := 1.0) -> int:
	return maxi(1, roundi(atk * power * v * guard_cut(def)))

static func mag_dmg(raw: float, res: float) -> int:
	return maxi(1, roundi(raw * guard_cut(res)))

## Dano de uma habilidade de ataque (phys, mag ou holy). `v` é o sorteio de 0.88 a 1.12.
static func skill_damage(skill: Dictionary, atk: float, mag: float, target_def: float, target_res: float, target_undead: bool, v := 1.0) -> int:
	match skill.kind:
		"phys":
			return phys_dmg(atk, 0.0 if skill.get("pierce", false) else target_def, skill.power, v)
		"mag", "holy":
			var d := mag_dmg((mag * skill.power + skill.base) * v, target_res)
			if skill.kind == "holy" and target_undead:
				d *= 2
			return d
	return 0

static func heal_amount(skill: Dictionary, mag: float, v := 1.0) -> int:
	return maxi(1, roundi((mag * skill.power + skill.base) * v))

## O que o Sineiro faz no turno n (0, 1, 2...): golpe, badalada em todos ou dobre fúnebre que drena um.
static func boss_move(turn: int, hp_frac: float) -> String:
	var cycle := 3 if hp_frac < 0.4 else 4          # furioso, a badalada vem mais seguido
	if turn % cycle == cycle - 1:
		return "bell"
	if turn % 4 == 1:
		return "drain"
	return "hit"

static func boss_atk(base_atk: float, hp_frac: float) -> float:
	return base_atk * (1.25 if hp_frac < 0.4 else 1.0)

static func can_pay(skill: Dictionary, mp: int, en: int) -> bool:
	return (mp if skill.cost_kind == "mp" else en) >= skill.cost

# ---------- combo (pontos do grupo, como em Sea of Stars) ----------

const COMBO_MAX := 8
const COMBOS := {
	"corte": {"name": "Corte Duplo", "cost": 3, "members": ["aldo", "andilla"], "power": 1.2, "desc": "Aldo e Andilla atacam juntos."},
	"escudo": {"name": "Escudo de Luz", "cost": 4, "members": ["teo", "lyra"], "heal": 0.4, "desc": "Cura o grupo e levanta a guarda de todos."},
}

static func combo_gain(points: int, amount := 1) -> int:
	return clampi(points + amount, 0, COMBO_MAX)

static func combo_ready(id: String, points: int, alive: Array) -> bool:
	var c: Dictionary = COMBOS[id]
	return points >= c.cost and c.members.all(func(m): return m in alive)

static func combo_damage(atk_a: float, atk_b: float, target_def: float, v := 1.0) -> int:
	var p: float = COMBOS.corte.power
	return phys_dmg(atk_a, target_def, p, v) + phys_dmg(atk_b, target_def, p, v)

static func combo_heal(hpmax: int) -> int:
	return int(hpmax * float(COMBOS.escudo.heal))

## Próximos golpes do chefe, para mostrar acima dele.
static func boss_forecast(turn: int, hp_frac: float, n := 3) -> Array:
	var out := []
	for i in n:
		out.append(boss_move(turn + i, hp_frac))
	return out
