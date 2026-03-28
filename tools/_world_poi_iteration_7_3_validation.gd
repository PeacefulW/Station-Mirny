extends SceneTree

const REGISTRY_DIR_PATH: String = "res://data/world/features"
const TEST_FEATURE_PATH: String = "res://data/world/features/test_feature.tres"
const PUBLIC_API_PATH: String = "res://docs/00_governance/PUBLIC_API.md"
const RESOLVER_SCRIPT_PATH: String = "res://core/systems/world/world_poi_resolver.gd"
const COMPUTE_CONTEXT_SCRIPT_PATH: String = "res://core/systems/world/world_compute_context.gd"
const RESOLVER_FILE_PATH: String = "res://core/systems/world/world_poi_resolver.gd"
const VALIDATION_TEMP_ROOT: String = "user://world_poi_iteration_7_3_validation"
const SAFE_ENTRYPOINTS_HEADING: String = "Безопасные точки входа"

var _has_failed: bool = false

func _initialize() -> void:
	print("[WorldPoiIteration73Validation] START")
	_run_validation()

func _run_validation() -> void:
	var registry: Node = get_root().get_node_or_null("WorldFeatureRegistry")
	_assert(registry != null, "WorldFeatureRegistry autoload must exist")
	if _has_failed:
		return
	var resolver_script: Variant = load(RESOLVER_SCRIPT_PATH)
	var compute_context_script: Variant = load(COMPUTE_CONTEXT_SCRIPT_PATH)
	_assert(resolver_script != null, "WorldPoiResolver script must load")
	_assert(compute_context_script != null, "WorldComputeContext script must load")
	if _has_failed:
		return
	var ctx: Variant = compute_context_script.new().call(
		"configure",
		null,
		123456,
		Vector2i.ZERO,
		null,
		null,
		null,
		null,
		null,
		null,
		{},
		{},
		[]
	)
	var hook_decisions: Array = [{"hook_id": &"base:test_feature"}]

	_validate_single_anchor_slot(registry, resolver_script, ctx, hook_decisions)
	_validate_anchor_and_owner_chunk(registry, resolver_script, ctx, hook_decisions)
	_validate_cross_chunk_anchor_ownership(registry, resolver_script, ctx, hook_decisions)
	_validate_constraint_rejection(registry, resolver_script, ctx, hook_decisions)
	_validate_arbitration_order(registry, resolver_script, ctx, hook_decisions)
	_validate_sorted_output(registry, resolver_script, ctx, hook_decisions)
	_validate_no_deferred_queue_path()
	_validate_public_api_boundary()
	_restore_baseline_registry(registry)
	if _has_failed:
		return
	print("[WorldPoiIteration73Validation] OK")
	quit(0)

func _validate_single_anchor_slot(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "single_anchor_slot", {
		"poi_high.tres": _build_poi_text(&"base:poi_high", 100, Vector2i.ZERO, [Vector2i.ZERO]),
		"poi_low.tres": _build_poi_text(&"base:poi_low", 10, Vector2i.ZERO, [Vector2i.ZERO]),
	})
	if _has_failed:
		return
	var placements: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	_assert(placements.size() == 1, "each canonical anchor resolves to at most one final POI placement in the single baseline exclusive slot")

func _validate_anchor_and_owner_chunk(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "anchor_owner", {
		"anchored_poi.tres": _build_poi_text(&"base:anchored_poi", 50, Vector2i(2, -1), [Vector2i.ZERO, Vector2i(1, 0)]),
	})
	if _has_failed:
		return
	var candidate_origin: Vector2i = Vector2i(10, 10)
	var placements: Array = resolver_script.call("resolve_for_origin", candidate_origin, hook_decisions, ctx) as Array
	_assert(placements.size() == 1, "expected one anchored placement for anchor ownership validation")
	if _has_failed:
		return
	var placement: Dictionary = placements[0] as Dictionary
	_assert(placement.get("anchor_tile") == candidate_origin + Vector2i(2, -1), "each returned PoiPlacementDecision.anchor_tile must equal candidate_origin + poi.anchor_offset")
	var owner_chunk: Vector2i = _tile_to_chunk(ctx, placement.get("anchor_tile", Vector2i.ZERO) as Vector2i)
	_assert(placement.get("owner_chunk") == owner_chunk, "each returned PoiPlacementDecision.owner_chunk must be the canonical chunk containing anchor_tile")

func _validate_cross_chunk_anchor_ownership(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "cross_chunk_anchor", {
		"cross_chunk_poi.tres": _build_poi_text(&"base:cross_chunk_poi", 50, Vector2i(1, 0), [Vector2i.ZERO, Vector2i(1, 0)]),
	})
	if _has_failed:
		return
	var candidate_origin: Vector2i = Vector2i(63, 5)
	var placements_a: Array = resolver_script.call("resolve_for_origin", candidate_origin, hook_decisions, ctx) as Array
	var placements_b: Array = resolver_script.call("resolve_for_origin", candidate_origin, hook_decisions, ctx) as Array
	_assert(placements_a == placements_b, "a multi_chunk_poi is selected once by canonical anchor ownership, independent of chunk load order")
	if _has_failed:
		return
	_assert(placements_a.size() == 1, "cross-chunk validation expects exactly one placement")
	if _has_failed:
		return
	var placement: Dictionary = placements_a[0] as Dictionary
	_assert(placement.get("owner_chunk") == Vector2i(1, 0), "cross-chunk POI ownership must follow the canonical anchor tile")

func _validate_constraint_rejection(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "constraint_rejection", {
		"invalid_poi.tres": _build_poi_text(&"base:invalid_poi", 50, Vector2i.ZERO, [Vector2i.ZERO], [999]),
	})
	if _has_failed:
		return
	var placements_a: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	var placements_b: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	_assert(placements_a.is_empty() and placements_b.is_empty(), "pois_with_unmet_constraints are rejected deterministically")

func _validate_arbitration_order(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "priority_arbitration", {
		"priority_low.tres": _build_poi_text(&"base:priority_low", 1, Vector2i.ZERO, [Vector2i.ZERO]),
		"priority_high.tres": _build_poi_text(&"base:priority_high", 100, Vector2i.ZERO, [Vector2i.ZERO]),
	})
	if _has_failed:
		return
	var priority_placements: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	_assert(priority_placements.size() == 1, "priority arbitration expects one winning placement")
	if _has_failed:
		return
	_assert((priority_placements[0] as Dictionary).get("id") == &"base:priority_high", "priority must win before hash arbitration")
	if _has_failed:
		return

	_reload_registry_case(registry, "hash_arbitration", {
		"hash_a.tres": _build_poi_text(&"base:hash_a", 50, Vector2i.ZERO, [Vector2i.ZERO]),
		"hash_b.tres": _build_poi_text(&"base:hash_b", 50, Vector2i.ZERO, [Vector2i.ZERO]),
	})
	if _has_failed:
		return
	var hash_placements: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	_assert(hash_placements.size() == 1, "hash arbitration expects one winning placement")
	if _has_failed:
		return
	var anchor_tile: Vector2i = (hash_placements[0] as Dictionary).get("anchor_tile", Vector2i.ZERO) as Vector2i
	var expected_hash_winner: StringName = &"base:hash_a"
	var hash_a: int = _hash_for_anchor(123456, anchor_tile, &"base:hash_a")
	var hash_b: int = _hash_for_anchor(123456, anchor_tile, &"base:hash_b")
	if hash_b > hash_a:
		expected_hash_winner = &"base:hash_b"
	elif hash_b == hash_a:
		expected_hash_winner = &"base:hash_a"
	_assert((hash_placements[0] as Dictionary).get("id") == expected_hash_winner, "competing valid POIs at the same canonical anchor must use hash(seed, anchor_tile, poi_id) after priority")
	if _has_failed:
		return

	var left: Dictionary = {"id": &"base:a_choice", "priority": 10, "tie_break_hash": 77}
	var right: Dictionary = {"id": &"base:z_choice", "priority": 10, "tie_break_hash": 77}
	_assert(bool(resolver_script.call("_is_candidate_better", left, right)), "competing valid POIs at the same canonical anchor must fall back to lexicographic poi_id after equal priority and hash")

func _validate_sorted_output(registry: Node, resolver_script: Variant, ctx: Variant, hook_decisions: Array) -> void:
	_reload_registry_case(registry, "sorted_output", {
		"a_far_anchor.tres": _build_poi_text(&"base:far_anchor", 50, Vector2i(0, 2), [Vector2i.ZERO]),
		"z_near_anchor.tres": _build_poi_text(&"base:near_anchor", 50, Vector2i(0, 0), [Vector2i.ZERO]),
	})
	if _has_failed:
		return
	var placements: Array = resolver_script.call("resolve_for_origin", Vector2i(10, 10), hook_decisions, ctx) as Array
	_assert(placements.size() == 2, "sorted-output validation expects two distinct anchors")
	if _has_failed:
		return
	var first_anchor: Vector2i = (placements[0] as Dictionary).get("anchor_tile", Vector2i.ZERO) as Vector2i
	var second_anchor: Vector2i = (placements[1] as Dictionary).get("anchor_tile", Vector2i.ZERO) as Vector2i
	_assert(first_anchor.y < second_anchor.y or (first_anchor.y == second_anchor.y and first_anchor.x <= second_anchor.x), "returned placement decisions are sorted deterministically before payload export")

func _validate_no_deferred_queue_path() -> void:
	var resolver_text: String = _read_text(RESOLVER_FILE_PATH)
	for forbidden_token: String in ["deferred", "queue", "second_pass", "second-pass"]:
		_assert(resolver_text.find(forbidden_token) == -1, "no deferred placement queue or second-pass arbitration path is introduced for unresolved footprints")
		if _has_failed:
			return

func _validate_public_api_boundary() -> void:
	var lines: PackedStringArray = _read_text(PUBLIC_API_PATH).split("\n")
	var in_quick_reference: bool = false
	var safe_entry_heading_level: int = -1
	for index: int in range(lines.size()):
		var line: String = lines[index]
		var heading_level: int = _get_heading_level(line)
		if heading_level > 0:
			if in_quick_reference and heading_level <= 2:
				in_quick_reference = false
			if safe_entry_heading_level != -1 and heading_level <= safe_entry_heading_level:
				safe_entry_heading_level = -1
			var heading_text: String = line.substr(heading_level).strip_edges()
			if heading_level == 2 and heading_text == "Quick Reference":
				in_quick_reference = true
			elif heading_text == SAFE_ENTRYPOINTS_HEADING:
				safe_entry_heading_level = heading_level
			continue
		if not in_quick_reference and safe_entry_heading_level == -1:
			continue
		_assert(line.find("WorldPoiResolver") == -1, "PUBLIC_API.md must not add WorldPoiResolver as a public safe entrypoint")
		if _has_failed:
			return

func _reload_registry_case(registry: Node, case_name: String, poi_files: Dictionary) -> void:
	var case_dir: String = "%s/%s" % [VALIDATION_TEMP_ROOT, case_name]
	_prepare_empty_user_directory(case_dir)
	_write_text("%s/test_feature.tres" % case_dir, _read_text(TEST_FEATURE_PATH))
	for file_name: String in poi_files.keys():
		_write_text("%s/%s" % [case_dir, file_name], str(poi_files[file_name]))
	var ready: bool = bool(registry.call("_reload_from_directory_for_validation", case_dir, &"base"))
	_assert(ready and bool(registry.call("is_ready")), "validation fixture %s must load successfully" % case_name)

func _restore_baseline_registry(registry: Node) -> void:
	var restored: bool = bool(registry.call("_reload_from_directory_for_validation", REGISTRY_DIR_PATH, &"base"))
	_assert(restored and bool(registry.call("is_ready")), "baseline registry must be restored after Iteration 7.3 validation")

func _build_poi_text(poi_id: StringName, priority: int, anchor_offset: Vector2i, footprint_tiles: Array, allowed_terrain_types: Array = [0]) -> String:
	return "[gd_resource type=\"Resource\" script_class=\"PoiDefinition\" load_steps=2 format=3]\n\n" \
		+ "[ext_resource type=\"Script\" path=\"res://data/world/features/poi_definition.gd\" id=\"1\"]\n\n" \
		+ "[resource]\n" \
		+ "script = ExtResource(\"1\")\n" \
		+ "id = &\"%s\"\n" % str(poi_id) \
		+ "display_name = \"%s\"\n" % str(poi_id) \
		+ "required_feature_hook_ids = Array[StringName]([&\"base:test_feature\"])\n" \
		+ "required_structure_tags = Array[StringName]([&\"surface\"])\n" \
		+ "allowed_terrain_types = %s\n" % var_to_str(allowed_terrain_types) \
		+ "footprint_tiles = %s\n" % var_to_str(footprint_tiles) \
		+ "anchor_offset = %s\n" % var_to_str(anchor_offset) \
		+ "priority = %d\n" % priority \
		+ "debug_marker_kind = &\"test_poi\"\n"

func _tile_to_chunk(ctx: Variant, tile_pos: Vector2i) -> Vector2i:
	var canonical_tile: Vector2i = ctx.call("canonicalize_tile", tile_pos) as Vector2i
	return ctx.call(
		"canonicalize_chunk_coord",
		Vector2i(
			floori(float(canonical_tile.x) / 64.0),
			floori(float(canonical_tile.y) / 64.0)
		)
	) as Vector2i

func _hash_for_anchor(world_seed: int, anchor_tile: Vector2i, poi_id: StringName) -> int:
	return abs(hash("%d|%d|%d|%s" % [world_seed, anchor_tile.x, anchor_tile.y, str(poi_id)]))

func _prepare_empty_user_directory(path: String) -> void:
	var absolute_path: String = ProjectSettings.globalize_path(path)
	if DirAccess.dir_exists_absolute(absolute_path):
		_delete_directory_recursive(absolute_path)
	var make_err: Error = DirAccess.make_dir_recursive_absolute(absolute_path)
	if make_err != OK:
		_fail("Failed to create validation directory: %s" % path)

func _delete_directory_recursive(absolute_path: String) -> void:
	var dir: DirAccess = DirAccess.open(absolute_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = absolute_path.path_join(entry)
			if dir.current_is_dir():
				_delete_directory_recursive(child_path)
			else:
				var remove_file_err: Error = DirAccess.remove_absolute(child_path)
				if remove_file_err != OK:
					_fail("Failed to remove validation file: %s" % child_path)
					return
		entry = dir.get_next()
	dir.list_dir_end()
	var remove_dir_err: Error = DirAccess.remove_absolute(absolute_path)
	if remove_dir_err != OK:
		_fail("Failed to remove validation directory: %s" % absolute_path)

func _write_text(path: String, content: String) -> void:
	var base_dir_abs: String = ProjectSettings.globalize_path(path.get_base_dir())
	var make_err: Error = DirAccess.make_dir_recursive_absolute(base_dir_abs)
	if make_err != OK:
		_fail("Failed to prepare directory for validation file: %s" % path)
		return
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("Failed to open validation file for write: %s" % path)
		return
	file.store_string(content)

func _read_text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail("Failed to read file: %s" % path)
		return ""
	return file.get_as_text()

func _get_heading_level(line: String) -> int:
	var level: int = 0
	while level < line.length() and line[level] == "#":
		level += 1
	if level == 0:
		return 0
	if level < line.length() and line[level] == " ":
		return level
	return 0

func _assert(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _fail(message: String) -> void:
	if _has_failed:
		return
	_has_failed = true
	push_error(message)
	print("[WorldPoiIteration73Validation] FAILED: %s" % message)
	quit(1)
