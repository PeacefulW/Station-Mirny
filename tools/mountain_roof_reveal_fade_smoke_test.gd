extends SceneTree

const WORLD_SCENE_PATH: String = "res://scenes/world/world_runtime_v0.tscn"

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed_scene: PackedScene = load(WORLD_SCENE_PATH) as PackedScene
	_assert(packed_scene != null, "world runtime scene loads for fade controller test")
	if packed_scene == null:
		quit(1)
		return
	var scene: Node = packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var live_streamer: Node = scene.get_node_or_null("WorldStreamer")
	_assert(live_streamer != null, "world runtime exposes WorldStreamer")
	if live_streamer != null:
		var streamer_script: Script = live_streamer.get_script() as Script
		_assert_enter_exit_and_same_component_reverse(streamer_script)
		_assert_same_mountain_component_repair(streamer_script)
		_assert_different_mountain_closes_before_opening(streamer_script)
		_assert_open_waits_for_selector_upload(streamer_script)
		_assert_floor_halo_selects_explicit_component(streamer_script)
		_assert_full_open_swap_waits_for_old_selector_upload(streamer_script)
		_assert_removed_component_keeps_fading_saved_visual_chunks(streamer_script)
		_assert_new_chunk_inherits_current_blend(streamer_script)
		_assert_reload_discards_presentation_progress(streamer_script)
	scene.queue_free()
	await process_frame
	if not _failed:
		print("mountain_roof_reveal_fade_smoke_test: OK")
	quit(1 if _failed else 0)


func _assert_enter_exit_and_same_component_reverse(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	_set_target(streamer, 11, 101)
	_assert(_state(streamer) == &"OPENING", "enter starts OPENING")
	_assert(int(streamer.get("_displayed_cover_component_id")) == 101, "enter publishes displayed component")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.075)
	var half_open: float = float(streamer.get("_mountain_roof_reveal_blend"))
	_assert(is_equal_approx(half_open, 0.875), "150 ms cubic-out midpoint is 0.875")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.075)
	_assert(_state(streamer) == &"OPEN", "enter finishes OPEN after 150 ms")
	_assert(is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), 1.0), "enter finishes at blend 1")

	_set_target(streamer, 0, 0)
	_assert(_state(streamer) == &"CLOSING_DELAY", "exit starts with delay")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.059)
	_assert(is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), 1.0), "59 ms exit delay holds blend")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.091)
	var mid_close: float = float(streamer.get("_mountain_roof_reveal_blend"))
	_assert(mid_close > 0.49 and mid_close < 0.51, "60 ms delay plus half close reaches blend 0.5")
	_assert(int(streamer.get("_displayed_cover_component_id")) == 101, "closing retains displayed selector")

	var before_reverse: float = mid_close
	_set_target(streamer, 11, 101)
	_assert(_state(streamer) == &"OPENING", "same-component reentry reverses closing")
	_assert(is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), before_reverse), "reentry has no blend jump")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.075)
	_assert(_state(streamer) == &"OPEN", "reversed half-open transition uses remaining 75 ms")
	_assert(is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), 1.0), "reentry restores blend 1")
	streamer.free()


func _assert_same_mountain_component_repair(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	_set_target(streamer, 21, 201)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
	_set_target(streamer, 21, 202)
	_assert(int(streamer.get("_displayed_cover_component_id")) == 202, "same-mountain repair swaps displayed selector immediately")
	_assert(_state(streamer) == &"OPEN", "same-mountain repair does not close roof")
	_assert(is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), 1.0), "same-mountain repair preserves blend")
	streamer.free()


func _assert_different_mountain_closes_before_opening(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	_set_target(streamer, 31, 301)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
	_set_target(streamer, 32, 302)
	_assert(_state(streamer) == &"CLOSING_DELAY", "different mountain starts by closing old roof")
	_assert(int(streamer.get("_displayed_cover_component_id")) == 301, "old selector remains during different-mountain close")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
	_assert(int(streamer.get("_displayed_cover_component_id")) == 301, "new selector is not installed mid-close")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.090)
	_assert(int(streamer.get("_displayed_cover_component_id")) == 302, "new selector installs only after old roof is closed")
	_assert(_state(streamer) == &"OPENING", "different mountain opens after close")
	_assert(is_zero_approx(float(streamer.get("_mountain_roof_reveal_blend"))), "new mountain begins from blend 0")
	streamer.free()


func _assert_open_waits_for_selector_upload(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	var cache: RefCounted = streamer.get("_mountain_cavity_cache") as RefCounted
	cache.set("_component_data_by_id", {
		401: {
			"mountain_id": 41,
			"floor_chunks": {Vector2i.ZERO: true},
		},
	})
	var chunk_view_script: Script = load("res://core/systems/world/chunk_view.gd") as Script
	var chunk_view: Node = chunk_view_script.new() as Node
	chunk_view.configure(Vector2i.ZERO)
	streamer.set("_chunk_views", {Vector2i.ZERO: chunk_view})
	streamer.set("_pending_mountain_native_mask_visual_upload_set", {Vector2i.ZERO: true})
	_set_target(streamer, 41, 401)
	_assert(_state(streamer) == &"OPENING_WAIT_SELECTOR", "opening waits for deferred selector upload")
	streamer.call("_advance_mountain_roof_reveal_transition", 1.0)
	_assert(is_zero_approx(float(streamer.get("_mountain_roof_reveal_blend"))), "queue latency never advances reveal blend")
	var pending: Dictionary = streamer.get("_pending_mountain_native_mask_visual_upload_set") as Dictionary
	pending.erase(Vector2i.ZERO)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.016)
	_assert(_state(streamer) == &"OPENING", "opening starts after selector upload settles")
	_assert(is_zero_approx(float(streamer.get("_mountain_roof_reveal_blend"))), "fade clock starts fresh after selector upload")
	chunk_view.free()
	streamer.free()


func _assert_floor_halo_selects_explicit_component(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	var cache: RefCounted = streamer.get("_mountain_cavity_cache") as RefCounted
	var target_tile := Vector2i(2, 3)
	var displayed_tile := Vector2i(11, 12)
	_install_component_fixture(cache, 411, 41, target_tile)
	_install_component_fixture(cache, 412, 41, displayed_tile)
	streamer.set("_active_cover_component_id", 411)
	streamer.set("_displayed_cover_component_id", 412)

	var target_halo: PackedByteArray = streamer.call(
		"_build_cover_floor_visibility_halo",
		Vector2i.ZERO,
		{},
		int(streamer.get("_active_cover_component_id")),
	) as PackedByteArray
	var displayed_halo: PackedByteArray = streamer.call(
		"_build_cover_floor_visibility_halo",
		Vector2i.ZERO,
		{},
		int(streamer.get("_displayed_cover_component_id")),
	) as PackedByteArray
	var halo_side: int = int(sqrt(float(target_halo.size())))
	var halo_radius: int = (halo_side - 16) / 2
	var target_index: int = (target_tile.y + halo_radius) * halo_side \
			+ target_tile.x + halo_radius
	var displayed_index: int = (displayed_tile.y + halo_radius) * halo_side \
			+ displayed_tile.x + halo_radius
	_assert(
		target_halo.size() == displayed_halo.size() and halo_side > 16,
		"target/displayed floor halos keep the same valid geometry",
	)
	_assert(
		int(target_halo[target_index]) == 1 and int(target_halo[displayed_index]) == 0,
		"torch/target floor halo selects only the active gameplay component",
	)
	_assert(
		int(displayed_halo[target_index]) == 0 and int(displayed_halo[displayed_index]) == 1,
		"render floor halo selects only the independently displayed component",
	)
	streamer.free()


func _assert_full_open_swap_waits_for_old_selector_upload(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	var cache: RefCounted = streamer.get("_mountain_cavity_cache") as RefCounted
	var old_chunk := Vector2i.ZERO
	var new_chunk := Vector2i(4, 0)
	_install_component_fixture(cache, 421, 42, Vector2i(1, 1))
	_install_component_fixture(cache, 422, 42, new_chunk * 16 + Vector2i(1, 1))

	var old_view: Node = _make_dual_mask_chunk_view(old_chunk)
	var new_view: Node = _make_dual_mask_chunk_view(new_chunk)
	streamer.set("_chunk_views", {
		old_chunk: old_view,
		new_chunk: new_view,
	})
	_set_target(streamer, 42, 421)
	var pending: Dictionary = streamer.get(
		"_pending_mountain_native_mask_visual_upload_set"
	) as Dictionary
	pending.erase(old_chunk)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.0)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
	_assert(_state(streamer) == &"OPEN", "old component reaches full OPEN before swap")

	_set_target(streamer, 42, 422)
	pending = streamer.get("_pending_mountain_native_mask_visual_upload_set") as Dictionary
	_assert(pending.has(old_chunk), "same-mountain swap queues old selector cleanup")
	_assert(pending.has(new_chunk), "same-mountain swap queues new selector upload")
	pending.erase(new_chunk)
	_assert(
		_state(streamer) == &"OPENING_WAIT_SELECTOR",
		"full-open same-mountain swap waits instead of reporting OPEN",
	)
	streamer.call("_advance_mountain_roof_reveal_transition", 1.0)
	_assert(
		_state(streamer) == &"OPENING_WAIT_SELECTOR",
		"pending old selector cleanup alone keeps full-open swap waiting",
	)
	_assert(
		is_equal_approx(float(streamer.get("_mountain_roof_reveal_blend")), 1.0),
		"selector wait preserves the already-open blend without a roof blink",
	)
	pending.erase(old_chunk)
	streamer.call("_advance_mountain_roof_reveal_transition", 0.016)
	_assert(_state(streamer) == &"OPEN", "swap reports OPEN only after old cleanup lands")

	old_view.free()
	new_view.free()
	streamer.free()


func _assert_removed_component_keeps_fading_saved_visual_chunks(
		streamer_script: Script,
) -> void:
	var streamer: Node = streamer_script.new() as Node
	var cache: RefCounted = streamer.get("_mountain_cavity_cache") as RefCounted
	var old_chunk := Vector2i(6, 2)
	var old_view_script: Script = load("res://core/systems/world/chunk_view.gd") as Script
	var old_view: Node = old_view_script.new() as Node
	old_view.configure(old_chunk)
	old_view.set_mountain_roof_reveal_blend(1.0)
	streamer.set("_chunk_views", {old_chunk: old_view})
	streamer.set("_displayed_cover_mountain_id", 43)
	streamer.set("_displayed_cover_component_id", 431)
	streamer.set("_displayed_cover_visual_chunks", {old_chunk: true})
	streamer.set("_mountain_roof_reveal_blend", 1.0)
	_install_component_fixture(cache, 431, 43, old_chunk * 16 + Vector2i(2, 2))

	cache.set("_component_data_by_id", {})
	cache.set("_component_id_by_tile", {})
	streamer.set("_active_cover_mountain_id", 0)
	streamer.set("_active_cover_component_id", 0)
	streamer.call("_begin_mountain_roof_reveal_close")
	streamer.call("_advance_mountain_roof_reveal_transition", 0.240)
	_assert(_state(streamer) == &"CLOSED", "removed component still completes close transition")
	_assert(
		is_zero_approx(float(old_view.get("_mountain_roof_reveal_blend"))),
		"saved old ChunkView receives blend 0 after its live cache id disappears",
	)
	_assert(
		int(streamer.get("_displayed_cover_component_id")) == 0,
		"removed displayed component clears only after its saved visual chunks close",
	)

	old_view.free()
	streamer.free()


func _assert_new_chunk_inherits_current_blend(streamer_script: Script) -> void:
	var streamer: Node = streamer_script.new() as Node
	streamer.set("_mountain_roof_reveal_blend", 0.63)
	var chunk_view: Node = streamer.call("_ensure_chunk_view", Vector2i(7, 7)) as Node
	_assert(chunk_view != null, "new ChunkView is created for blend inheritance test")
	if chunk_view != null:
		_assert(
			is_equal_approx(float(chunk_view.get("_mountain_roof_reveal_blend")), 0.63),
			"new ChunkView receives current blend even when global setter would early-return",
		)
	streamer.free()


func _assert_reload_discards_presentation_progress(streamer_script: Script) -> void:
	for phase: StringName in [&"OPENING", &"OPEN", &"CLOSING"]:
		var streamer: Node = streamer_script.new() as Node
		_set_target(streamer, 51, 501)
		if phase == &"OPEN":
			streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
		elif phase == &"CLOSING":
			streamer.call("_advance_mountain_roof_reveal_transition", 0.150)
			_set_target(streamer, 0, 0)
			streamer.call("_advance_mountain_roof_reveal_transition", 0.090)
		_assert(_state(streamer) == phase, "reload fixture reaches %s" % phase)
		streamer.set("_active_cover_mountain_id", 0)
		streamer.set("_active_cover_component_id", 0)
		streamer.call("_reset_mountain_roof_reveal_presentation")
		_assert(_state(streamer) == &"CLOSED", "reload resets %s presentation state" % phase)
		_assert(int(streamer.get("_displayed_cover_component_id")) == 0, "reload clears %s displayed selector" % phase)
		_assert(is_zero_approx(float(streamer.get("_mountain_roof_reveal_blend"))), "reload clears %s reveal blend" % phase)
		streamer.free()


func _set_target(streamer: Node, mountain_id: int, component_id: int) -> void:
	streamer.set("_active_cover_mountain_id", mountain_id)
	streamer.set("_active_cover_component_id", component_id)
	streamer.call("_sync_mountain_roof_reveal_target")


func _install_component_fixture(
		cache: RefCounted,
		component_id: int,
		mountain_id: int,
		world_tile: Vector2i,
) -> void:
	var chunk_coord: Vector2i = Vector2i(
		floori(float(world_tile.x) / 16.0),
		floori(float(world_tile.y) / 16.0),
	)
	var components: Dictionary = cache.get("_component_data_by_id") as Dictionary
	components[component_id] = {
		"mountain_id": mountain_id,
		"tiles": {world_tile: true},
		"floor_chunks": {chunk_coord: true},
		"openings": {},
		"shell": {},
		"opening_shell": {},
	}
	cache.set("_component_data_by_id", components)
	var component_by_tile: Dictionary = cache.get("_component_id_by_tile") as Dictionary
	component_by_tile[world_tile] = component_id
	cache.set("_component_id_by_tile", component_by_tile)


func _make_dual_mask_chunk_view(chunk_coord: Vector2i) -> Node:
	var chunk_view_script: Script = load("res://core/systems/world/chunk_view.gd") as Script
	var chunk_view: Node = chunk_view_script.new() as Node
	chunk_view.configure(chunk_coord)
	var remaining := PackedByteArray([0])
	var closed := PackedByteArray([255])
	var dug_halo := PackedByteArray()
	dug_halo.resize(32 * 32)
	dug_halo[16 * 32 + 16] = 1
	var applied: bool = bool(chunk_view.apply_mountain_native_mask_data(
		{
			"remaining_mass_mask": remaining,
			"visual_remaining_mass_mask": remaining,
			"closed_roof_mask": closed,
			"dug_halo": dug_halo,
			"width": 1,
			"height": 1,
			"step_px": 1.0,
		},
		Vector2.ZERO,
	))
	_assert(applied, "dual-mask ChunkView fixture accepts paired construction state")
	return chunk_view


func _state(streamer: Node) -> StringName:
	return streamer.call("_get_mountain_roof_reveal_transition_state_name") as StringName


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
