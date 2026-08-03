extends SceneTree

# Headless contract probe for the shared open-sky authority.
# Run:
#   godot --headless --path . -s tools/environment_exposure_resolver_probe.gd

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

var _failures: Array[String] = []
var _resolver_script: GDScript = null


class BuildingSystemStub extends Node:
	var indoor: bool = false
	var last_grid_position: Vector2i = Vector2i.ZERO


	func world_to_grid(world_position: Vector2) -> Vector2i:
		return Vector2i(floori(world_position.x / 64.0), floori(world_position.y / 64.0))


	func is_cell_indoor(grid_position: Vector2i) -> bool:
		last_grid_position = grid_position
		return indoor


class WorldStreamerStub extends Node:
	var sample: Dictionary = { "ready": true, "mountain_flags": 0 }
	var last_tile: Vector2i = Vector2i.ZERO


	func get_mountain_cover_sample(tile_coord: Vector2i) -> Dictionary:
		last_tile = tile_coord
		return sample.duplicate(true)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# Defer-load because this -s probe is parsed before the EventBus autoload name
	# is registered, while the resolver itself is a regular runtime scene node.
	_resolver_script = load(
		"res://core/systems/world/environment_exposure_resolver.gd",
	) as GDScript
	if _resolver_script == null:
		_check(false, "environment exposure resolver loads after autoload boot")
		_finish()
		return
	var resolver: Variant = _resolver_script.new()
	root.add_child(resolver)
	await process_frame
	var building: BuildingSystemStub = BuildingSystemStub.new()
	var streamer: WorldStreamerStub = WorldStreamerStub.new()
	_configure(resolver, building, streamer, true)

	var sample_position: Vector2 = Vector2(160.0, 96.0)
	resolver.set_active_z_level(0)
	_check(
		resolver.is_open_sky_at(sample_position),
		"ready outdoor surface sample resolves as open sky",
	)
	_check(
		streamer.last_tile == WorldRuntimeConstants.world_to_tile(sample_position),
		"resolver queries mountain cover in canonical world-tile coordinates",
	)

	resolver.set_active_z_level(-1)
	_check(not resolver.is_open_sky_at(sample_position), "subsurface z fails closed")
	resolver.set_active_z_level(1)
	_check(not resolver.is_open_sky_at(sample_position), "non-surface positive z fails closed")
	resolver.set_active_z_level(0)

	building.indoor = true
	_check(
		resolver.is_building_indoor_at(sample_position),
		"building authority marks the sampled cell indoor",
	)
	_check(not resolver.is_open_sky_at(sample_position), "building interior blocks open sky")
	building.indoor = false

	streamer.sample = {
		"ready": true,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_INTERIOR,
	}
	_check(not resolver.is_open_sky_at(sample_position), "mountain interior blocks open sky")
	streamer.sample = {
		"ready": true,
		"mountain_flags": WorldRuntimeConstants.MOUNTAIN_FLAG_WALL,
	}
	_check(
		resolver.is_open_sky_at(sample_position),
		"non-interior mountain flags do not invent overhead cover",
	)

	streamer.sample = { "ready": false, "mountain_flags": 0 }
	_check(not resolver.is_open_sky_at(sample_position), "unready mountain sample fails closed")
	streamer.sample = { }
	_check(not resolver.is_open_sky_at(sample_position), "unknown mountain sample fails closed")

	_configure(resolver, building, null, true)
	_check(not resolver.is_open_sky_at(sample_position), "missing mountain authority fails closed")
	var unsupported_streamer: Node = Node.new()
	_configure(resolver, building, unsupported_streamer, true)
	_check(
		not resolver.is_open_sky_at(sample_position),
		"mountain authority without sampling API fails closed",
	)
	_configure(resolver, building, streamer, false)
	unsupported_streamer.free()
	streamer.sample = { "ready": true, "mountain_flags": 0 }
	_check(not resolver.is_open_sky_at(sample_position), "unresolved services fail closed")

	_configure(resolver, null, streamer, true)
	root.add_child(building)
	building.add_to_group("building_system")
	building.indoor = true
	resolver.call("_on_rooms_recalculated", { })
	_check(
		resolver.is_building_indoor_at(sample_position),
		"room publication resolves a late-added building authority without polling",
	)
	building.indoor = false

	_check_no_forbidden_state_or_side_effects()
	resolver.free()
	building.free()
	streamer.free()

	_finish()


func _configure(
		resolver: Variant,
		building: Node,
		streamer: Node,
		services_resolved: bool,
) -> void:
	resolver.set("_building_system", building)
	resolver.set("_world_streamer", streamer)
	resolver.set("_services_resolved", services_resolved)


func _check_no_forbidden_state_or_side_effects() -> void:
	var path: String = "res://core/systems/world/environment_exposure_resolver.gd"
	_check(FileAccess.file_exists(path), "resolver source is available for static audit")
	var executable_source: String = _without_comments(FileAccess.get_file_as_string(path))
	var forbidden_tokens: Array[String] = [
		"WeatherRuntime",
		"WindRuntime",
		"ground_wetness",
		"cold_load",
		"apply_damage(",
		"take_damage(",
		"queue_free(",
		"set_shader_parameter(",
		"EventBus.weather_changed.emit",
		"EventBus.z_level_changed.emit",
	]
	var found: Array[String] = []
	for token: String in forbidden_tokens:
		if executable_source.contains(token):
			found.append(token)
	_check(
		found.is_empty(),
		"resolver derives context without weather/survival/render mutations %s" % str(found),
	)


func _without_comments(source: String) -> String:
	var executable_source: String = ""
	for source_line: String in source.split("\n"):
		var comment_index: int = source_line.find("#")
		var code_line: String = (
			source_line.left(comment_index) if comment_index >= 0 else source_line
		)
		executable_source += code_line + "\n"
	return executable_source


func _check(passed: bool, description: String) -> void:
	if passed:
		print("environment_exposure_resolver_probe: PASS %s" % description)
		return
	_failures.append(description)
	print("environment_exposure_resolver_probe: FAIL %s" % description)


func _finish() -> void:
	if _failures.is_empty():
		print("environment_exposure_resolver_probe: ALL CHECKS PASSED")
		quit(0)
		return
	for failure: String in _failures:
		print("environment_exposure_resolver_probe: FAILED %s" % failure)
	quit(1)
