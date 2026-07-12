class_name WorldVisualTreeProfile
extends RefCounted
## Авторские параметры процедурного дерева равнины: палитра (приглушённая осень
## под траву), генеративные диапазоны, масштаб-тиры, отклик на ветер и тень.
## Code-profile в стиле WorldVisualWindProfile/WorldVisualLightingProfile —
## единый источник тюнинга для tool-генератора атласа (сейчас) и рантайм-
## презентации (Iteration 2). Никаких magic numbers в коде генератора/презентации.
## Контракт: docs/02_system_specs/world/plains_trees_presentation.md

# --- Палитра кроны (дусто-тановая осень, низкая насыщенность под сухую траву) ---
static func palette_autumn() -> Array[Color]:
	return [
		Color8(120, 74, 34), Color8(150, 94, 42), Color8(178, 120, 58),
		Color8(198, 150, 82), Color8(214, 176, 108), Color8(96, 60, 30),
	]

## Тёплый коричневый ствол (не чёрный — иначе «вставлен», а не «родной»).
static func bark_color() -> Color:
	return Color8(86, 62, 40)


static func bark_palette() -> Dictionary:
	return {
		"shadow": Color8(45, 30, 20),
		"dark": Color8(64, 42, 27),
		"mid": Color8(86, 62, 40),
		"warm": Color8(120, 82, 48),
		"highlight": Color8(156, 112, 66),
		"moss": Color8(72, 83, 48),
	}

## Разброс оттенка кроны между деревьями (жёлто-золотой <-> рыже-оранжевый).
static func canopy_tints() -> Array[Color]:
	return [
		Color(1.0, 1.0, 0.95), Color(1.04, 1.02, 0.82), Color(1.06, 0.94, 0.78),
		Color(1.02, 0.98, 0.90), Color(1.07, 0.88, 0.70),
	]

# --- Генеративные диапазоны (per-variant вариация считается из них) ---
const TRUNK_LEN_SPAN: Vector2 = Vector2(62.0, 94.0)
const TRUNK_W_SPAN: Vector2 = Vector2(19.0, 25.0)
const GNARL_SPAN: Vector2 = Vector2(0.32, 0.85)
const CANOPY_COUNT_SPAN: Vector2i = Vector2i(90, 150)
const CANOPY_RADIUS_SPAN: Vector2 = Vector2(38.0, 48.0)
const LEAN_SPAN: Vector2 = Vector2(-0.135, 0.135)
const LEAF_SIZE: float = 3.6
const LEAF_ALPHA: float = 0.72

# --- Масштаб-тиры размещения (рантайм Iteration 2; зафиксированы как данные) ---
const TREE_WORLD_HEIGHT_PX: float = 205.0
const SCALE_TIER_SMALL: Vector2 = Vector2(0.58, 0.80)
const SCALE_TIER_NORMAL: Vector2 = Vector2(0.80, 1.18)
const SCALE_TIER_HERO: Vector2 = Vector2(1.35, 1.72)
const TIER_SMALL_CHANCE: float = 0.20
const TIER_HERO_CHANCE: float = 0.10

# --- Отклик на общий ветер (доли высоты; см. tree_wind.gdshader) ---
const WIND_SWAY_FRACTION: float = 0.11
const WIND_LEAN_FRACTION: float = 0.06
const WIND_GUST_FIELD_SCALE_PX: float = 460.0
const WIND_GUST_FIELD_ANISOTROPY: float = 2.4

# --- Тень-силуэт (привязка к солнцу — в рантайме; здесь базовые доли) ---
const SHADOW_BASE_FORESHORTEN: float = 0.5
const SHADOW_OPACITY: float = 0.30

# --- Сетка атласа (tool-экспорт). Кадры КВАДРАТНЫЕ: рантайм-батч рендерит
# квадрат size×size, поэтому неквадратный кадр исказил бы дерево. ---
const ATLAS_FRAME: Vector2i = Vector2i(384, 384)
const ATLAS_COLUMNS: int = 4
const ATLAS_ROWS: int = 4
const ATLAS_VARIANT_COUNT: int = 16
const ATLAS_MARGIN_PX: int = 12
## Свет запекаемого шейдинга кроны/коры (фиксированный ключ сверху-слева;
## направление БРОСАЕМОЙ тени привязывается к солнцу отдельно, в рантайме).
const BAKE_LIGHT_DIR: Vector2 = Vector2(-0.70710678, -0.70710678)


static func variant_params(index: int) -> Dictionary:
	# 16 вариантов = 4 РАЗНЫХ архетипа × 4 под-вариации, чтобы лес не повторялся.
	var tints: Array[Color] = canopy_tints()
	var archetype: int = (index / 4) % 4
	var sub: float = float(index % 4) / 3.0
	var p: Dictionary = {}
	match archetype:
		0: # тонкое высокое
			p = {
				"gnarl": lerpf(0.20, 0.34, sub), "trunk_len": lerpf(96.0, 118.0, sub),
				"trunk_w": lerpf(26.0, 32.0, sub), "canopy_count": int(lerpf(110.0, 145.0, sub)),
				"canopy_radius": lerpf(36.0, 45.0, sub), "split_angle": 0.44, "len_ratio": 0.68,
				"lean": lerpf(-0.025, 0.025, sub),
			}
		1: # широкое раскидистое
			p = {
				"gnarl": lerpf(0.30, 0.46, sub), "trunk_len": lerpf(78.0, 96.0, sub),
				"trunk_w": lerpf(32.0, 40.0, sub), "canopy_count": int(lerpf(145.0, 185.0, sub)),
				"canopy_radius": lerpf(50.0, 62.0, sub), "split_angle": 0.58, "len_ratio": 0.72,
				"lean": lerpf(-0.035, 0.035, sub),
			}
		2: # витое
			p = {
				"gnarl": lerpf(0.34, 0.54, sub), "trunk_len": lerpf(82.0, 100.0, sub),
				"trunk_w": lerpf(29.0, 37.0, sub), "canopy_count": int(lerpf(120.0, 155.0, sub)),
				"canopy_radius": lerpf(43.0, 54.0, sub), "split_angle": 0.54, "len_ratio": 0.70,
				"lean": lerpf(-0.045, 0.045, sub),
			}
		_: # наклонённое ветром (наклон уходит в крону, ствол стоит)
			p = {
				"gnarl": lerpf(0.28, 0.44, sub), "trunk_len": lerpf(88.0, 108.0, sub),
				"trunk_w": lerpf(28.0, 36.0, sub), "canopy_count": int(lerpf(120.0, 160.0, sub)),
				"canopy_radius": lerpf(42.0, 52.0, sub), "split_angle": 0.50, "len_ratio": 0.70,
				"lean": (0.035 + sub * 0.025) * (1.0 if index % 2 == 0 else -1.0),
			}
	p["seed"] = 4000 + index * 13
	p["tint"] = tints[index % tints.size()]
	return p
