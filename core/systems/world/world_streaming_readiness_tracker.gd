class_name WorldStreamingReadinessTracker
extends RefCounted
## Transient timestamps for the existing WorldStreamer lifecycle. This helper
## never decides demand or schedules work; WorldStreamer supplies every state.

const TERMINAL_HISTORY_LIMIT: int = 32

var _generation_epoch: int = -1
var _stage_by_chunk: Dictionary = { }
var _layers_by_chunk: Dictionary = { }
var _terminal_history: Array[Dictionary] = []


func reset(generation_epoch: int) -> void:
	_generation_epoch = generation_epoch
	_stage_by_chunk.clear()
	_layers_by_chunk.clear()
	_terminal_history.clear()


func mark_stage(chunk_coord: Vector2i, stage: StringName) -> void:
	var current: Dictionary = _stage_by_chunk.get(chunk_coord, { }) as Dictionary
	if StringName(String(current.get("stage", ""))) == stage:
		return
	_stage_by_chunk[chunk_coord] = {
		"stage": stage,
		"started_msec": Time.get_ticks_msec(),
	}


func mark_layer(
		chunk_coord: Vector2i,
		layer: StringName,
		state: StringName,
		reason: StringName,
) -> void:
	var chunk_layers: Dictionary = _layers_by_chunk.get(chunk_coord, { }) as Dictionary
	var current: Dictionary = chunk_layers.get(layer, { }) as Dictionary
	if StringName(String(current.get("state", ""))) == state \
			and StringName(String(current.get("reason", ""))) == reason:
		return
	chunk_layers[layer] = {
		"state": state,
		"reason": reason,
		"started_msec": Time.get_ticks_msec(),
	}
	_layers_by_chunk[chunk_coord] = chunk_layers


func observe(
		chunk_coord: Vector2i,
		stage: StringName,
		layers: Dictionary,
		now_msec: int,
) -> Dictionary:
	mark_stage(chunk_coord, stage)
	for layer_variant: Variant in layers.keys():
		var layer: StringName = StringName(String(layer_variant))
		var observation: Dictionary = layers.get(layer_variant, { }) as Dictionary
		var chunk_layers: Dictionary = _layers_by_chunk.get(chunk_coord, { }) as Dictionary
		if not chunk_layers.has(layer):
			var stage_record: Dictionary = _stage_by_chunk.get(chunk_coord, { }) as Dictionary
			chunk_layers[layer] = {
				"state": StringName(String(observation.get("state", "waiting"))),
				"reason": StringName(String(observation.get("reason", ""))),
				# A derived layer first seen by an explicit diagnostic has already
				# waited at least as long as its current lifecycle stage.
				"started_msec": int(stage_record.get("started_msec", now_msec)),
			}
			_layers_by_chunk[chunk_coord] = chunk_layers
		else:
			mark_layer(
				chunk_coord,
				layer,
				StringName(String(observation.get("state", "waiting"))),
				StringName(String(observation.get("reason", ""))),
			)
	var stage_record: Dictionary = _stage_by_chunk.get(chunk_coord, { }) as Dictionary
	var timed_layers: Dictionary = { }
	var stored_layers: Dictionary = _layers_by_chunk.get(chunk_coord, { }) as Dictionary
	for layer_variant: Variant in layers.keys():
		var layer: StringName = StringName(String(layer_variant))
		var stored: Dictionary = stored_layers.get(layer, { }) as Dictionary
		timed_layers[String(layer)] = {
			"state": String(stored.get("state", "waiting")),
			"reason": String(stored.get("reason", "")),
			"elapsed_ms": maxi(
				now_msec - int(stored.get("started_msec", now_msec)),
				0,
			),
		}
	return {
		"stage_elapsed_ms": maxi(
			now_msec - int(stage_record.get("started_msec", now_msec)),
			0,
		),
		"layers": timed_layers,
	}


func mark_terminal(chunk_coord: Vector2i, stage: StringName) -> void:
	mark_stage(chunk_coord, stage)
	var now_msec: int = Time.get_ticks_msec()
	var stage_record: Dictionary = _stage_by_chunk.get(chunk_coord, { }) as Dictionary
	var timed_layers: Dictionary = { }
	var stored_layers: Dictionary = _layers_by_chunk.get(chunk_coord, { }) as Dictionary
	for layer_variant: Variant in stored_layers.keys():
		var stored: Dictionary = stored_layers.get(layer_variant, { }) as Dictionary
		timed_layers[String(layer_variant)] = {
			"state": String(stored.get("state", "evicted")),
			"reason": String(stored.get("reason", "")),
			"elapsed_ms": maxi(
				now_msec - int(stored.get("started_msec", now_msec)),
				0,
			),
		}
	_terminal_history.append({
		"chunk_coord": chunk_coord,
		"demand": "none",
		"lifecycle_stage": String(stage),
		"stage_elapsed_ms": maxi(
			now_msec - int(stage_record.get("started_msec", now_msec)),
			0,
		),
		"ready": stage == &"retained",
		"blocking_layer": "",
		"blocking_reason": "",
		"blocking_elapsed_ms": 0,
		"layers": timed_layers,
	})
	while _terminal_history.size() > TERMINAL_HISTORY_LIMIT:
		_terminal_history.pop_front()
	_stage_by_chunk.erase(chunk_coord)
	_layers_by_chunk.erase(chunk_coord)


func get_terminal_history() -> Array[Dictionary]:
	return _terminal_history.duplicate(true)
