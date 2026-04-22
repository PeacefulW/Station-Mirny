class_name WorldSpawnResolver
extends RefCounted

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")

const SPAWN_SAFE_PATCH_MIN_TILE: int = 12
const SPAWN_SAFE_PATCH_MAX_TILE: int = 20

static func resolve_preview_spawn_tile(
	seed_value: int,
	world_version: int,
	settings: MountainGenSettings
) -> Vector2i:
	var safe_patch_rect: Rect2i = resolve_preview_spawn_safe_patch_rect(
		seed_value,
		world_version,
		settings
	)
	return safe_patch_rect.position + Vector2i(
		safe_patch_rect.size.x / 2,
		safe_patch_rect.size.y / 2
	)

static func resolve_preview_spawn_safe_patch_rect(
	_seed: int,
	_world_version: int,
	_settings: MountainGenSettings
) -> Rect2i:
	var safe_patch_size: int = SPAWN_SAFE_PATCH_MAX_TILE - SPAWN_SAFE_PATCH_MIN_TILE + 1
	return Rect2i(
		Vector2i(SPAWN_SAFE_PATCH_MIN_TILE, SPAWN_SAFE_PATCH_MIN_TILE),
		Vector2i(safe_patch_size, safe_patch_size)
	)
