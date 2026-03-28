extends SceneTree

const REGISTRY_SCRIPT_PATH: String = "res://core/autoloads/world_feature_registry.gd"
const PUBLIC_API_PATH: String = "res://docs/00_governance/PUBLIC_API.md"
const TEST_FEATURE_PATH: String = "res://data/world/features/test_feature.tres"
const TEST_POI_PATH: String = "res://data/world/features/test_poi.tres"
const FEATURES_ROOT_PREFIX: String = "res://data/world/features/"
const VALIDATION_TEMP_ROOT: String = "user://world_feature_registry_validation"
const ALLOWED_FEATURE_LOAD_FILE: String = "res://core/autoloads/world_feature_registry.gd"
const CODE_SCAN_ROOT: String = "res://"
const CODE_SCAN_EXTENSIONS: Array[String] = ["gd", "tscn", "cs", "gdshader"]
const RESOLVER_NAMES: Array[String] = ["WorldFeatureHookResolver", "WorldPoiResolver"]
const SAFE_ENTRYPOINTS_HEADING: String = "Безопасные точки входа"

var _has_failed: bool = false

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	var registry: Node = get_root().get_node_or_null("WorldFeatureRegistry")
	var world_generator: Node = get_root().get_node_or_null("WorldGenerator")
	_assert_global_registry_ready(registry, world_generator)
	if _has_failed:
		return
	_validate_strict_readiness_cases()
	if _has_failed:
		return
	_validate_world_generator_fail_fast(registry, world_generator)
	if _has_failed:
		return
	_validate_no_direct_feature_loads()
	if _has_failed:
		return
	_validate_public_api_boundary()
	if _has_failed:
		return
	print("[WorldFeatureRegistryValidation] OK")
	quit(0)

func _assert_global_registry_ready(registry: Node, world_generator: Node) -> void:
	if registry == null:
		_fail("WorldFeatureRegistry autoload must exist")
		return
	if world_generator == null:
		_fail("WorldGenerator autoload must exist")
		return
	if not bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must be ready at boot")
		return
	if registry.call("get_feature_by_id", &"base:test_feature") == null:
		_fail("base:test_feature must load through the registry")
		return
	if registry.call("get_poi_by_id", &"base:test_poi") == null:
		_fail("base:test_poi must load through the registry")
		return
	if (registry.call("get_all_feature_hooks") as Array).size() < 1:
		_fail("registry must expose at least one feature hook")
		return
	if (registry.call("get_all_pois") as Array).size() < 1:
		_fail("registry must expose at least one poi")
		return
	var poi: Resource = registry.call("get_poi_by_id", &"base:test_poi") as Resource
	if poi == null or not bool(poi.call("has_explicit_anchor_offset")):
		_fail("base:test_poi must have explicit anchor_offset")
		return
	if poi == null or not bool(poi.call("has_explicit_priority")):
		_fail("base:test_poi must have explicit priority")
		return
	world_generator.call("initialize_world", 123456)
	if not bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must stay ready through world initialization")
		return

func _validate_strict_readiness_cases() -> void:
	_assert_registry_case_fails("invalid_definition_resource", true, true, {
		"broken_definition.tres": "not a godot resource",
	})
	_assert_registry_case_fails("duplicate_feature_id", true, true, {
		"duplicate_feature.tres": _read_text(TEST_FEATURE_PATH),
	})
	_assert_registry_case_fails("duplicate_poi_id", true, true, {
		"duplicate_poi.tres": _read_text(TEST_POI_PATH),
	})
	_assert_registry_case_fails("missing_anchor_offset", true, false, {
		"missing_anchor_poi.tres": _missing_anchor_offset_poi_text(),
	})
	_assert_registry_case_fails("missing_priority", true, false, {
		"missing_priority_poi.tres": _missing_priority_poi_text(),
	})
	_assert_registry_case_fails("unsupported_definition_resource", true, true, {
		"unsupported_definition.tres": _unsupported_definition_text(),
	})

func _validate_world_generator_fail_fast(registry: Node, world_generator: Node) -> void:
	var case_dir: String = "%s/world_generator_not_ready" % VALIDATION_TEMP_ROOT
	_prepare_empty_user_directory(case_dir)
	_write_text("%s/test_feature.tres" % case_dir, _read_text(TEST_FEATURE_PATH))
	_write_text("%s/missing_priority_poi.tres" % case_dir, _missing_priority_poi_text())
	var forced_ready: bool = bool(registry.call("_reload_from_directory_for_validation", case_dir, &"base"))
	if forced_ready or bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must stay not-ready during WorldGenerator fail-fast validation")
		return
	world_generator.call("initialize_world", 424242)
	if bool(world_generator.get("_is_initialized")):
		_fail("WorldGenerator.initialize_world() must fail-fast when WorldFeatureRegistry is not ready")
		return
	if world_generator.get("_chunk_content_builder") != null:
		_fail("WorldGenerator.initialize_world() must clear chunk builder when registry is not ready")
		return
	if world_generator.call("build_chunk_content", Vector2i.ZERO) != null:
		_fail("WorldGenerator must not build chunk content after not-ready registry initialization attempt")
		return
	var restored_ready: bool = bool(registry.call("_reload_from_directory_for_validation", "res://data/world/features", &"base"))
	if not restored_ready or not bool(registry.call("is_ready")):
		_fail("WorldFeatureRegistry must restore baseline definitions after fail-fast validation")
		return
	world_generator.call("initialize_world", 123456)
	if not bool(world_generator.get("_is_initialized")):
		_fail("WorldGenerator must recover after baseline registry restore")
		return

func _assert_registry_case_fails(case_name: String, include_test_feature: bool, include_test_poi: bool, extra_files: Dictionary) -> void:
	var case_dir: String = "%s/%s" % [VALIDATION_TEMP_ROOT, case_name]
	_prepare_empty_user_directory(case_dir)
	if include_test_feature:
		_write_text("%s/test_feature.tres" % case_dir, _read_text(TEST_FEATURE_PATH))
	if include_test_poi:
		_write_text("%s/test_poi.tres" % case_dir, _read_text(TEST_POI_PATH))
	for file_name: String in extra_files.keys():
		_write_text("%s/%s" % [case_dir, file_name], str(extra_files[file_name]))
	var registry_script: Script = load(REGISTRY_SCRIPT_PATH) as Script
	if registry_script == null:
		_fail("Failed to load WorldFeatureRegistry script for validation")
		return
	var temp_registry: Node = registry_script.new()
	var ready: bool = bool(temp_registry.call("_reload_from_directory_for_validation", case_dir, &"base"))
	if ready or bool(temp_registry.call("is_ready")):
		temp_registry.free()
		_fail("strict readiness failed for case %s: registry reported ready" % case_name)
		return
	var loaded_feature_count: int = (temp_registry.call("get_all_feature_hooks") as Array).size()
	var loaded_poi_count: int = (temp_registry.call("get_all_pois") as Array).size()
	if loaded_feature_count != 0 or loaded_poi_count != 0:
		temp_registry.free()
		_fail("strict readiness failed for case %s: partial registry snapshot survived failure" % case_name)
		return
	temp_registry.free()

func _validate_no_direct_feature_loads() -> void:
	var pattern: RegEx = RegEx.new()
	var compile_error: Error = pattern.compile("(?:\\bload\\b|\\bpreload\\b|\\bResourceLoader\\.load\\b)\\s*\\(\\s*[\"']%s" % FEATURES_ROOT_PREFIX)
	if compile_error != OK:
		_fail("Failed to compile direct-load validation regex")
		return
	_scan_code_tree_for_feature_loads(CODE_SCAN_ROOT, pattern)
	_check_file_for_direct_feature_loads("res://project.godot", pattern)

func _scan_code_tree_for_feature_loads(root_path: String, pattern: RegEx) -> void:
	var dir: DirAccess = DirAccess.open(root_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var child_path: String = root_path.path_join(entry)
			if dir.current_is_dir():
				_scan_code_tree_for_feature_loads(child_path, pattern)
			elif _is_scannable_code_file(entry):
				_check_file_for_direct_feature_loads(child_path, pattern)
			if _has_failed:
				return
		entry = dir.get_next()
	dir.list_dir_end()

func _check_file_for_direct_feature_loads(file_path: String, pattern: RegEx) -> void:
	if file_path == ALLOWED_FEATURE_LOAD_FILE:
		return
	var text: String = _read_text(file_path)
	if pattern.search(text) != null:
		_fail("direct feature definition load/preload is forbidden outside WorldFeatureRegistry: %s" % file_path)
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
		for resolver_name: String in RESOLVER_NAMES:
			if line.find(resolver_name) != -1:
				var context: String = "Quick Reference" if in_quick_reference else SAFE_ENTRYPOINTS_HEADING
				_fail("PUBLIC_API.md exposes %s inside %s at line %d" % [resolver_name, context, index + 1])
				return

func _get_heading_level(line: String) -> int:
	var level: int = 0
	while level < line.length() and line[level] == "#":
		level += 1
	if level == 0:
		return 0
	if level < line.length() and line[level] == " ":
		return level
	return 0

func _is_scannable_code_file(file_name: String) -> bool:
	var extension: String = file_name.get_extension().to_lower()
	return CODE_SCAN_EXTENSIONS.has(extension)

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

func _missing_anchor_offset_poi_text() -> String:
	return "[gd_resource type=\"Resource\" script_class=\"PoiDefinition\" load_steps=2 format=3]\n\n" \
		+ "[ext_resource type=\"Script\" path=\"res://data/world/features/poi_definition.gd\" id=\"1\"]\n\n" \
		+ "[resource]\n" \
		+ "script = ExtResource(\"1\")\n" \
		+ "id = &\"base:test_poi\"\n" \
		+ "display_name = \"Invalid Missing Anchor\"\n" \
		+ "required_feature_hook_ids = Array[StringName]([&\"base:test_feature\"])\n" \
		+ "priority = 100\n"

func _missing_priority_poi_text() -> String:
	return "[gd_resource type=\"Resource\" script_class=\"PoiDefinition\" load_steps=2 format=3]\n\n" \
		+ "[ext_resource type=\"Script\" path=\"res://data/world/features/poi_definition.gd\" id=\"1\"]\n\n" \
		+ "[resource]\n" \
		+ "script = ExtResource(\"1\")\n" \
		+ "id = &\"base:test_poi\"\n" \
		+ "display_name = \"Invalid Missing Priority\"\n" \
		+ "required_feature_hook_ids = Array[StringName]([&\"base:test_feature\"])\n" \
		+ "anchor_offset = Vector2i(0, 0)\n"

func _unsupported_definition_text() -> String:
	return "[gd_resource type=\"Resource\" script_class=\"BiomeData\" load_steps=2 format=3]\n\n" \
		+ "[ext_resource type=\"Script\" path=\"res://data/biomes/biome_data.gd\" id=\"1\"]\n\n" \
		+ "[resource]\n" \
		+ "script = ExtResource(\"1\")\n" \
		+ "id = &\"base:unsupported_biome\"\n" \
		+ "display_name = \"Unsupported\"\n"

func _fail(message: String) -> void:
	if _has_failed:
		return
	_has_failed = true
	push_error(message)
	print("[WorldFeatureRegistryValidation] FAILED: %s" % message)
	quit(1)
