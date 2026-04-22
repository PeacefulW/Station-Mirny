class_name WorldPreviewRenderMode
extends RefCounted

const TERRAIN: StringName = &"terrain"
const MOUNTAIN_ID: StringName = &"mountain_id"
const MOUNTAIN_CLASSIFICATION: StringName = &"mountain_classification"
const SPAWN_SAFE_PATCH: StringName = &"spawn_safe_patch"

const _ORDERED_MODES: Array[StringName] = [
	TERRAIN,
	MOUNTAIN_ID,
	MOUNTAIN_CLASSIFICATION,
	SPAWN_SAFE_PATCH,
]

const _LABEL_KEYS: Dictionary = {
	TERRAIN: &"UI_WORLDGEN_PREVIEW_MODE_TERRAIN",
	MOUNTAIN_ID: &"UI_WORLDGEN_PREVIEW_MODE_MOUNTAIN_ID",
	MOUNTAIN_CLASSIFICATION: &"UI_WORLDGEN_PREVIEW_MODE_MOUNTAIN_CLASSIFICATION",
	SPAWN_SAFE_PATCH: &"UI_WORLDGEN_PREVIEW_MODE_SPAWN_SAFE_PATCH",
}

static func all_modes() -> Array[StringName]:
	return _ORDERED_MODES.duplicate()

static func coerce(mode: StringName) -> StringName:
	return mode if _LABEL_KEYS.has(mode) else TERRAIN

static func get_label_key(mode: StringName) -> StringName:
	var normalized_mode: StringName = coerce(mode)
	return _LABEL_KEYS.get(normalized_mode, &"UI_WORLDGEN_PREVIEW_MODE_TERRAIN") as StringName

