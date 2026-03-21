class_name CliffRegistry
extends RefCounted

## Реестр клиф-типов. По конфигурации 4 кардинальных соседей
## определяет какой тип клифа ставить.

enum CliffType {
	NONE,
	SIDE_N, SIDE_S, SIDE_E, SIDE_W,
	OUTER_NE, OUTER_NW, OUTER_SE, OUTER_SW,
	INNER_NE, INNER_NW, INNER_SE, INNER_SW,
}

## Определить тип клифа по 4 кардинальным соседям (true = ROCK).
static func get_cliff_type(n: bool, e: bool, s: bool, w: bool) -> CliffType:
	# Внутренний тайл — все соседи ROCK → нет клифа
	if n and e and s and w:
		return CliffType.NONE

	# Прямые края (ровно 1 сторона открыта)
	if not s and n and e and w: return CliffType.SIDE_S
	if not n and s and e and w: return CliffType.SIDE_N
	if not e and n and s and w: return CliffType.SIDE_E
	if not w and n and s and e: return CliffType.SIDE_W

	# Внешние углы (2 смежные стороны открыты)
	if not s and not e and n and w: return CliffType.OUTER_SE
	if not s and not w and n and e: return CliffType.OUTER_SW
	if not n and not e and s and w: return CliffType.OUTER_NE
	if not n and not w and s and e: return CliffType.OUTER_NW

	# Fallback — прямой край по первой открытой стороне
	if not s: return CliffType.SIDE_S
	if not n: return CliffType.SIDE_N
	if not e: return CliffType.SIDE_E
	if not w: return CliffType.SIDE_W
	return CliffType.NONE
