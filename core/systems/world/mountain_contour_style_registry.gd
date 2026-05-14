class_name MountainContourStyleRegistry
extends RefCounted

const MountainContourStyle = preload("res://core/systems/world/mountain_contour_style.gd")

const DEFAULT_STYLE_PATHS: Array[String] = [
	"res://assets/textures/terrain/mountains/mountain/mountain_contour_style.v1.json",
]

var validation_errors: Array[String] = []

var _styles_by_id: Dictionary = {}

func clear() -> void:
	_styles_by_id.clear()
	validation_errors.clear()

func load_default_styles() -> bool:
	return load_styles(DEFAULT_STYLE_PATHS)

func load_styles(style_paths: Array) -> bool:
	clear()
	if style_paths.is_empty():
		_record_error("MountainContourStyleRegistry: no style paths provided.")
		return false
	for path_variant: Variant in style_paths:
		var path: String = str(path_variant)
		var style: MountainContourStyle = MountainContourStyle.load_from_file(path)
		if style == null:
			validation_errors.append("MountainContourStyleRegistry: failed to load style %s." % [path])
			return false
		if has_style(style.asset_name):
			_record_error("MountainContourStyleRegistry: duplicate style id %s." % [String(style.asset_name)])
			return false
		_styles_by_id[style.asset_name] = style
	return true

func has_style(style_id: StringName) -> bool:
	return _styles_by_id.has(style_id)

func get_style(style_id: StringName) -> MountainContourStyle:
	return _styles_by_id.get(style_id, null) as MountainContourStyle

func require_style(style_id: StringName) -> MountainContourStyle:
	var style: MountainContourStyle = get_style(style_id)
	if style == null:
		push_error("MountainContourStyleRegistry: required style is missing: %s." % [String(style_id)])
	return style

func get_style_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for key_variant: Variant in _styles_by_id.keys():
		result.append(key_variant as StringName)
	result.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return result

func debug_snapshot() -> Dictionary:
	var style_summaries: Array[Dictionary] = []
	for style_id: StringName in get_style_ids():
		var style: MountainContourStyle = get_style(style_id)
		if style != null:
			style_summaries.append(style.debug_snapshot())
	return {
		"ready": not _styles_by_id.is_empty() and validation_errors.is_empty(),
		"style_count": _styles_by_id.size(),
		"style_ids": get_style_ids(),
		"styles": style_summaries,
		"validation_errors": validation_errors.duplicate(),
	}

func _record_error(message: String) -> void:
	validation_errors.append(message)
	push_error(message)
