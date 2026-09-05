extends SceneTree
## Native painter merge regression; no scenes, renderer, textures or world boot.

const GPU_STRIDE: int = 16
const STATIC_COUNT: int = 8192
const ACTOR_COUNT: int = 400

var _failures: Array[String] = []


func _init() -> void:
	if not ClassDB.class_exists(&"WorldCore"):
		push_error("world_render_native_merge_contract_test: native WorldCore required")
		quit(1)
		return
	var world_core: Object = ClassDB.instantiate(&"WorldCore")
	_test_dense_merge(world_core)
	_test_empty_and_actor_only_pages(world_core)
	_test_unsorted_static_rejection(world_core)
	for failure: String in _failures:
		push_error("world_render_native_merge_contract_test: %s" % failure)
	if _failures.is_empty():
		print("world_render_native_merge_contract_test: PASS")
	quit(0 if _failures.is_empty() else 1)


func _test_dense_merge(world_core: Object) -> void:
	var static_records: Array[Dictionary] = []
	for index: int in range(STATIC_COUNT):
		static_records.append(_record(
			index * 2 + 2, float(index % 64), (index / 64) % 3,
		))
	static_records.sort_custom(_painter_less)
	var static_page: Dictionary = _page(0, static_records)
	var untouched_page: Dictionary = _page(1, [_record(100000, 1100.0, 20)])
	var snapshot: Dictionary = _snapshot([static_page, untouched_page])
	var before: Dictionary = snapshot.duplicate(true)
	var actors: Array[Dictionary] = []
	for index: int in range(ACTOR_COUNT - 1, -1, -1):
		actors.append(_record(index * 2 + 1, float(index % 66 - 1), (index / 64) % 3))
	var expected: Array[Dictionary] = static_records.duplicate()
	expected.append_array(actors)
	expected.sort_custom(_painter_less)
	var result: Dictionary = world_core.call(
		"compose_world_render_actors", snapshot, actors,
	) as Dictionary
	_expect(bool(result.get("success", false)), "dense composition succeeds")
	_expect(snapshot == before, "composition preserves every static input field")
	if not bool(result.get("success", false)):
		return
	var expected_page_zero: Array[Dictionary] = []
	var expected_page_negative: Array[Dictionary] = []
	for record: Dictionary in expected:
		if float(record["feet_y"]) < 0.0:
			expected_page_negative.append(record)
		else:
			expected_page_zero.append(record)
	var pages: Array = result["pages"] as Array
	_expect(pages.size() == 3, "negative actor page extends dense window")
	_expect(int(result["page_window_min_y"]) == -1, "negative painter Y floors correctly")
	_assert_body(pages[0] as Dictionary, expected_page_negative, "negative page")
	_assert_body(pages[1] as Dictionary, expected_page_zero, "dense static/actor merge")
	var untouched: Dictionary = pages[2] as Dictionary
	_expect(untouched["body_buffer"] == untouched_page["body_buffer"],
		"actor-free page buffer remains identical")
	_expect(int(result["actor_count"]) == ACTOR_COUNT, "actor count is preserved")
	_expect(int(result["buffer_float_count"]) == (STATIC_COUNT + ACTOR_COUNT + 1) * GPU_STRIDE,
		"composed payload accounting matches packed GPU arrays")
	_expect(result["actor_page_slots"] == PackedInt32Array([0, 1]),
		"touched slots follow the expanded absolute window")


func _test_empty_and_actor_only_pages(world_core: Object) -> void:
	var empty: Dictionary = _snapshot([])
	var result: Dictionary = world_core.call(
		"compose_world_render_actors", empty, [],
	) as Dictionary
	_expect(bool(result.get("success", false)), "empty snapshot composition succeeds")
	_expect((result.get("pages", []) as Array).is_empty(), "empty window stays empty")
	var actors: Array[Dictionary] = [_record(9, 2050.0, 20), _record(5, 1.0, 20)]
	result = world_core.call("compose_world_render_actors", empty, actors) as Dictionary
	_expect(bool(result.get("success", false)), "actor-only composition succeeds")
	if not bool(result.get("success", false)):
		return
	var pages: Array = result["pages"] as Array
	_expect(pages.size() == 3, "empty intermediate page remains present")
	_assert_body(pages[0] as Dictionary, [actors[1]], "first actor-only page")
	_assert_body(pages[1] as Dictionary, [], "empty intermediate page")
	_assert_body(pages[2] as Dictionary, [actors[0]], "last actor-only page")


func _test_unsorted_static_rejection(world_core: Object) -> void:
	var records: Array[Dictionary] = [_record(3, 30.0, 20), _record(1, 10.0, 20)]
	var result: Dictionary = world_core.call(
		"compose_world_render_actors", _snapshot([_page(0, records)]), [_record(2, 20.0, 20)],
	) as Dictionary
	_expect(not bool(result.get("success", false)), "unsorted static painter data is rejected")
	_expect(str(result.get("error", "")).contains("not sorted"),
		"unsorted static input reports the broken producer contract")


func _record(stable_id: int, feet_y: float, semantic_layer: int) -> Dictionary:
	return {
		"stable_id": stable_id,
		"feet_y": feet_y,
		"semantic_layer": semantic_layer,
		"body_transform": Transform2D(
			Vector2(8.0, 0.0), Vector2(0.0, 16.0), Vector2(float(stable_id), feet_y),
		),
		"tint": Color(0.25, 0.5, 0.75, 1.0),
		"sprite_id": 4,
		"direction_index": stable_id % 16,
		"frame_index": (stable_id / 16) % 16,
		"shadow_visible": false,
	}


func _painter_less(left: Dictionary, right: Dictionary) -> bool:
	for field: String in ["feet_y", "semantic_layer", "stable_id"]:
		if left[field] != right[field]:
			return left[field] < right[field]
	return false


func _gpu(record: Dictionary) -> PackedFloat32Array:
	var transform: Transform2D = record["body_transform"] as Transform2D
	var tint: Color = record["tint"] as Color
	return PackedFloat32Array([
		transform.x.x, transform.y.x, 0.0, transform.origin.x,
		transform.x.y, transform.y.y, 0.0, transform.origin.y,
		tint.r, tint.g, tint.b, tint.a,
		float(record["sprite_id"]),
		float(int(record["direction_index"]) * 16 + int(record["frame_index"])), 0.0, 0.0,
	])


func _page(page_y: int, records: Array[Dictionary]) -> Dictionary:
	var body := PackedFloat32Array()
	var feet := PackedFloat32Array()
	var layers := PackedInt32Array()
	var ids := PackedInt64Array()
	for record: Dictionary in records:
		body.append_array(_gpu(record))
		feet.append(float(record["feet_y"]))
		layers.append(int(record["semantic_layer"]))
		ids.append(int(record["stable_id"]))
	return {
		"page_y": page_y, "body_buffer": body, "body_feet_y": feet,
		"body_semantic_layers": layers, "body_stable_ids": ids,
		"body_instance_count": records.size(), "instance_count": records.size(),
		"static_instance_count": records.size(), "ground_count": 0,
	}


func _snapshot(pages: Array[Dictionary]) -> Dictionary:
	var instance_count: int = 0
	for page: Dictionary in pages:
		instance_count += int(page["instance_count"])
	return {
		"success": true, "pages": pages, "instance_count": instance_count,
		"buffer_float_count": instance_count * GPU_STRIDE,
	}


func _assert_body(page: Dictionary, expected: Array[Dictionary], label: String) -> void:
	var reference: Dictionary = _page(int(page["page_y"]), expected)
	for field: String in [
		"body_buffer", "body_feet_y", "body_semantic_layers", "body_stable_ids",
		"body_instance_count",
	]:
		_expect(page[field] == reference[field], "%s preserves %s" % [label, field])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
