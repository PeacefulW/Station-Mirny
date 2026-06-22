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
const CANOPY_COUNT_SPAN: Vector2i = Vector2i(58, 106)
const CANOPY_RADIUS_SPAN: Vector2 = Vector2(38.0, 48.0)
const LEAN_SPAN: Vector2 = Vector2(-0.135, 0.135)
const LEAF_SIZE: float = 4.5
const LEAF_ALPHA: float = 0.82

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
const BAKE_LIGHT_DIR: Vector2 = Vector2(-0.7, -0.72)


static func variant_params(index: int) -> Dictionary:
	# Детерминированная per-variant вариация из диапазонов (без randf).
	var n: int = maxi(ATLAS_VARIANT_COUNT - 1, 1)
	var t: float = float(index) / float(n)
	var tints: Array[Color] = canopy_tints()
	return {
		"seed": 4000 + index * 7,
		"gnarl": lerpf(GNARL_SPAN.x, GNARL_SPAN.y, float(index % 5) / 4.0),
		"trunk_len": lerpf(TRUNK_LEN_SPAN.x, TRUNK_LEN_SPAN.y, float(index % 3) / 2.0),
		"trunk_w": lerpf(TRUNK_W_SPAN.x, TRUNK_W_SPAN.y, float(index % 3) / 2.0),
		"canopy_count": int(lerpf(float(CANOPY_COUNT_SPAN.x), float(CANOPY_COUNT_SPAN.y), float(index % 4) / 3.0)),
		"canopy_radius": lerpf(CANOPY_RADIUS_SPAN.x, CANOPY_RADIUS_SPAN.y, float(index % 3) / 2.0),
		"lean": lerpf(LEAN_SPAN.x, LEAN_SPAN.y, t),
		"tint": tints[index % tints.size()],
	}
