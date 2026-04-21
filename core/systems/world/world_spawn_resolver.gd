class_name WorldSpawnResolver
extends RefCounted

const MountainGenSettings = preload("res://core/resources/mountain_gen_settings.gd")

const SPAWN_SAFE_PATCH_MIN_TILE: int = 12
const SPAWN_SAFE_PATCH_MAX_TILE: int = 20

static func resolve_preview_spawn_tile(
	_seed: int,
	_world_version: int,
	_settings: MountainGenSettings
) -> Vector2i:
	var safe_patch_center: int = int(
		floor(
			float(SPAWN_SAFE_PATCH_MIN_TILE + SPAWN_SAFE_PATCH_MAX_TILE) * 0.5
		)
	)
	return Vector2i(safe_patch_center, safe_patch_center)
