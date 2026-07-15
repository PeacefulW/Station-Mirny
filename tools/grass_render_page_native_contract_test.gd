extends SceneTree

const STRIPE_COUNT: int = 64
const INSTANCE_STRIDE: int = 12
const CHUNK_SIZE_PX: float = 1024.0

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_core: Object = ClassDB.instantiate("WorldCore")
	_expect(world_core != null, "WorldCore is available")
	if world_core == null:
		_finish()
		return
	_expect(
		world_core.has_method("build_grass_render_page_buffer"),
		"WorldCore exposes the native render-page merge",
	)
	if not world_core.has_method("build_grass_render_page_buffer"):
		_finish()
		return

	var contributors: Array = [
		_make_contributor(3, 103, 30.0),
		_make_contributor(0, 100, 0.0),
		_make_contributor(2, 102, 20.0),
	]
	var source_snapshots: Array[PackedFloat32Array] = []
	for contributor_variant: Variant in contributors:
		var contributor: Dictionary = contributor_variant as Dictionary
		var buckets: Array = contributor.get("bucket_buffers", []) as Array
		source_snapshots.append((buckets[5] as PackedFloat32Array).duplicate())

	var result: Dictionary = world_core.call(
		"build_grass_render_page_buffer",
		contributors,
		4,
		CHUNK_SIZE_PX,
	) as Dictionary
	_expect(not result.has("error"), "valid contributors merge without error")
	_expect(int(result.get("contributor_mask", -1)) == 0b1101, "sparse contributor mask is exact")
	_expect(
		result.get("contributor_revisions", PackedInt64Array()) as PackedInt64Array \
				== PackedInt64Array([100, -1, 102, 103]),
		"revision vector is slot-addressed and marks the missing slot",
	)
	_expect(int(result.get("instance_count", -1)) == 3, "albedo instance count is exact")
	_expect(int(result.get("directional_shadow_count", -1)) == 3, "directional count is exact")
	_expect(int(result.get("shadow_count", -1)) == 3, "contact count is exact")
	_expect(int(result.get("spore_count", -1)) == 3, "spore count is exact")
	_expect(int(result.get("non_empty_bucket_count", -1)) == 1, "non-empty stripe count is O(1) metadata")
	_expect(int(result.get("buffer_float_count", -1)) == 144, "all four output streams contribute to float metadata")
	_expect(int(result.get("payload_bytes", -1)) == 576, "payload byte metadata is exact")

	var merged_buckets: Array = result.get("bucket_buffers", []) as Array
	_expect(merged_buckets.size() == STRIPE_COUNT, "native page keeps exactly 64 world-row stripes")
	if merged_buckets.size() == STRIPE_COUNT:
		var merged: PackedFloat32Array = merged_buckets[5] as PackedFloat32Array
		_expect(merged.size() == 3 * INSTANCE_STRIDE, "three sparse slots share one stripe buffer")
		_assert_stream_rebased_only_x(merged, [0, 2, 3], [0.0, 20.0, 30.0], "albedo")
	for field_name: StringName in [
		&"directional_shadow_buffer",
		&"shadow_buffer",
		&"spore_buffer",
	]:
		var merged_flat: PackedFloat32Array = result.get(field_name, PackedFloat32Array()) \
				as PackedFloat32Array
		_assert_stream_rebased_only_x(
			merged_flat,
			[0, 2, 3],
			[0.0, 20.0, 30.0],
			str(field_name),
		)

	# Native output must not mutate the immutable contributor handles.
	for contributor_index: int in range(contributors.size()):
		var contributor: Dictionary = contributors[contributor_index] as Dictionary
		var buckets: Array = contributor.get("bucket_buffers", []) as Array
		_expect(
			(buckets[5] as PackedFloat32Array) == source_snapshots[contributor_index],
			"contributor %d stays immutable" % contributor_index,
		)

	var repeated: Dictionary = world_core.call(
		"build_grass_render_page_buffer",
		contributors,
		4,
		CHUNK_SIZE_PX,
	) as Dictionary
	_expect(
		(repeated.get("bucket_buffers", []) as Array)[5] \
				== (result.get("bucket_buffers", []) as Array)[5],
		"same contributor snapshot merges deterministically",
	)

	var duplicated_slot: Array = contributors.duplicate(false)
	duplicated_slot.append(_make_contributor(2, 999, 99.0))
	var duplicate_result: Dictionary = world_core.call(
		"build_grass_render_page_buffer",
		duplicated_slot,
		4,
		CHUNK_SIZE_PX,
	) as Dictionary
	_expect(duplicate_result.has("error"), "duplicate contributor slot fails explicitly")
	var bad_width: Dictionary = world_core.call(
		"build_grass_render_page_buffer",
		contributors,
		5,
		CHUNK_SIZE_PX,
	) as Dictionary
	_expect(bad_width.has("error"), "page width outside the fixed contract fails explicitly")
	_finish()


func _make_contributor(slot: int, revision: int, marker: float) -> Dictionary:
	var buckets: Array = []
	buckets.resize(STRIPE_COUNT)
	for stripe: int in range(STRIPE_COUNT):
		buckets[stripe] = PackedFloat32Array()
	var instance: PackedFloat32Array = _make_instance(marker)
	buckets[5] = instance
	return {
		"slot": slot,
		"revision": revision,
		"bucket_buffers": buckets,
		"directional_shadow_buffer": instance.duplicate(),
		"shadow_buffer": instance.duplicate(),
		"spore_buffer": instance.duplicate(),
	}


func _make_instance(marker: float) -> PackedFloat32Array:
	return PackedFloat32Array([
		1.125 + marker,
		2.25 + marker,
		3.5 + marker,
		4.75 + marker,
		5.125 + marker,
		6.25 + marker,
		7.5 + marker,
		8.75 + marker,
		0.125 + marker,
		0.25 + marker,
		0.5 + marker,
		0.75 + marker,
	])


func _assert_stream_rebased_only_x(
		merged: PackedFloat32Array,
		expected_slots: Array,
		expected_markers: Array,
		label: String,
) -> void:
	_expect(
		merged.size() == expected_slots.size() * INSTANCE_STRIDE,
		"%s merged stream has the expected stride" % label,
	)
	if merged.size() != expected_slots.size() * INSTANCE_STRIDE:
		return
	for instance_index: int in range(expected_slots.size()):
		var slot: int = int(expected_slots[instance_index])
		var marker: float = float(expected_markers[instance_index])
		var source: PackedFloat32Array = _make_instance(marker)
		var offset: int = instance_index * INSTANCE_STRIDE
		for component: int in range(INSTANCE_STRIDE):
			var expected: float = source[component]
			if component == 3:
				expected += float(slot) * CHUNK_SIZE_PX
			_expect(
				merged[offset + component] == expected,
				"%s slot %d component %d is preserved%s" % [
					label,
					slot,
					component,
					" except exact X rebase" if component == 3 else "",
				],
			)


func _finish() -> void:
	if _failures.is_empty():
		print("grass_render_page_native_contract_test: PASS")
		quit(0)
		return
	for failure: String in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
