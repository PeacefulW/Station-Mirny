class_name WorldSpawnResolver
extends RefCounted

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")
const FoundationGenSettings = preload("res://core/resources/foundation_gen_settings.gd")
const WorldBoundsSettings = preload("res://core/resources/world_bounds_settings.gd")
const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")

static func resolve_preview_spawn_tile(
	seed_value: int,
	world_version: int,
	settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings = null,
	foundation_settings: FoundationGenSettings = null
) -> Vector2i:
	var safe_patch_rect: Rect2i = resolve_preview_spawn_safe_patch_rect(
		seed_value,
		world_version,
		settings,
		world_bounds,
		foundation_settings
	)
	return safe_patch_rect.position + Vector2i(
		safe_patch_rect.size.x / 2,
		safe_patch_rect.size.y / 2
	)

static func resolve_preview_spawn_safe_patch_rect(
	_seed: int,
	world_version: int,
	_settings: MountainGenSettings,
	world_bounds: WorldBoundsSettings = null,
	foundation_settings: FoundationGenSettings = null
) -> Rect2i:
	if WorldRuntimeConstants.uses_world_foundation(world_version):
		var resolved_bounds: WorldBoundsSettings = world_bounds if world_bounds != null else WorldBoundsSettings.hard_coded_defaults()
		var resolved_foundation: FoundationGenSettings = foundation_settings \
			if foundation_settings != null \
			else FoundationGenSettings.for_bounds(resolved_bounds)
		return resolved_foundation.resolve_spawn_safe_patch_rect(resolved_bounds)
	var safe_patch_size: int = WorldRuntimeConstants.SPAWN_SAFE_PATCH_MAX_TILE \
		- WorldRuntimeConstants.SPAWN_SAFE_PATCH_MIN_TILE + 1
	return Rect2i(
		Vector2i(
			WorldRuntimeConstants.SPAWN_SAFE_PATCH_MIN_TILE,
			WorldRuntimeConstants.SPAWN_SAFE_PATCH_MIN_TILE
		),
		Vector2i(safe_patch_size, safe_patch_size)
	)

static func resolve_spawn_tile_from_native_result(native_result: Dictionary) -> Vector2i:
	var spawn_tile_variant: Variant = native_result.get("spawn_tile", Vector2i.ZERO)
	if spawn_tile_variant is Vector2i:
		return spawn_tile_variant as Vector2i
	push_error("WorldSpawnResolver native spawn result is missing Vector2i spawn_tile.")
	return Vector2i.ZERO

static func resolve_spawn_safe_patch_rect_from_native_result(native_result: Dictionary) -> Rect2i:
	var safe_patch_rect_variant: Variant = native_result.get("spawn_safe_patch_rect", Rect2i())
	if safe_patch_rect_variant is Rect2i:
		return safe_patch_rect_variant as Rect2i
	push_error("WorldSpawnResolver native spawn result is missing Rect2i spawn_safe_patch_rect.")
	return Rect2i()
