class_name WorldPerfProbe
extends RefCounted

## Инструментальный профайлер для мировых систем.
## Статические методы — не требует autoload.
## Проверяет контракты из docs/00_governance/PERFORMANCE_CONTRACTS.md.

const _THRESHOLD_MS: float = 2.0

## Контракты на интерактивные операции (максимально допустимое время в мс).
const _CONTRACTS: Dictionary = {
	"ChunkManager.try_harvest_at_world": 2.0,
	"ChunkManager._on_mountain_tile_changed": 0.5,
	"ChunkManager.query_local_underground_zone": 2.0,
	"Chunk.try_mine_at": 2.0,
	"MountainRoofSystem._request_refresh": 4.0,
	"MountainRoofSystem._refresh_local_zone": 2.0,
	"MountainRoofSystem._process_cover_step": 2.0,
	"BuildingSystem.place_building": 2.0,
	"BuildingSystem.remove_building": 2.0,
	"BuildingSystem.destroy_building": 2.0,
}

## Per-frame аккумулятор: операция → время в мс. Сбрасывается каждый кадр WorldPerfMonitor.
static var _frame_operations: Dictionary = {}

## Суммарные hitches за сессию.
static var _hitch_count: int = 0

static func measure(label: String, callable_fn: Callable) -> Variant:
	var started_usec: int = Time.get_ticks_usec()
	var result: Variant = callable_fn.call()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_record(label, elapsed_ms)
	return result

static func begin() -> int:
	return Time.get_ticks_usec()

static func end(label: String, started_usec: int) -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	_record(label, elapsed_ms)

static func record(label: String, elapsed_ms: float) -> void:
	_record(label, elapsed_ms)

static func _record(label: String, elapsed_ms: float) -> void:
	if elapsed_ms >= _THRESHOLD_MS:
		print("[WorldPerf] %s: %.2f ms" % [label, elapsed_ms])
	var contract_key: String = _extract_contract_key(label)
	if _CONTRACTS.has(contract_key):
		var limit: float = _CONTRACTS[contract_key]
		if elapsed_ms > limit:
			push_warning("[WorldPerf] WARNING: %s took %.2f ms (contract: %.1f ms)" % [label, elapsed_ms, limit])
	_frame_operations[label] = _frame_operations.get(label, 0.0) + elapsed_ms

## Извлекает ключ контракта из label (отбрасывает параметры вроде chunk coord).
static func _extract_contract_key(label: String) -> String:
	for key: String in _CONTRACTS:
		if label.begins_with(key):
			return key
	return label

## Возвращает и очищает per-frame данные. Вызывается WorldPerfMonitor раз в кадр.
static func flush_frame() -> Dictionary:
	var result: Dictionary = _frame_operations.duplicate()
	_frame_operations.clear()
	return result
