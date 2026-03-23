class_name WorldPerfProbe
extends RefCounted

## Временный инструментальный профайлер для старта мира, гор и копания.

const _THRESHOLD_MS: float = 0.1

static func measure(label: String, callable_fn: Callable) -> Variant:
	var started_usec: int = Time.get_ticks_usec()
	var result: Variant = callable_fn.call()
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if elapsed_ms >= _THRESHOLD_MS:
		print("[WorldPerf] %s: %.2f ms" % [label, elapsed_ms])
	return result

static func begin() -> int:
	return Time.get_ticks_usec()

static func end(label: String, started_usec: int) -> void:
	var elapsed_ms: float = float(Time.get_ticks_usec() - started_usec) / 1000.0
	if elapsed_ms >= _THRESHOLD_MS:
		print("[WorldPerf] %s: %.2f ms" % [label, elapsed_ms])
