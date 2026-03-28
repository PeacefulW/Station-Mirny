class_name WorldFeatureRegistrySingleton
extends Node

const FeatureHookDataScript = preload("res://data/world/features/feature_hook_data.gd")
const PoiDefinitionScript = preload("res://data/world/features/poi_definition.gd")
const BASE_NAMESPACE: StringName = &"base"
const BASE_DEFINITIONS_DIR: String = "res://data/world/features"

var _features_by_id: Dictionary = {}
var _feature_ordered: Array[Resource] = []
var _pois_by_id: Dictionary = {}
var _poi_ordered: Array[Resource] = []
var _is_ready: bool = false
var _last_load_error: String = ""

func _ready() -> void:
	_load_base_definitions()

func is_ready() -> bool:
	return _is_ready

func get_feature_by_id(id: StringName) -> Resource:
	var result: Resource = _features_by_id.get(id, null) as Resource
	if result:
		return result
	return _features_by_id.get(_make_namespaced_id(id, BASE_NAMESPACE), null) as Resource

func get_all_feature_hooks() -> Array[Resource]:
	var result: Array[Resource] = []
	for feature: Resource in _feature_ordered:
		result.append(feature)
	return result

func get_poi_by_id(id: StringName) -> Resource:
	var result: Resource = _pois_by_id.get(id, null) as Resource
	if result:
		return result
	return _pois_by_id.get(_make_namespaced_id(id, BASE_NAMESPACE), null) as Resource

func get_all_pois() -> Array[Resource]:
	var result: Array[Resource] = []
	for poi: Resource in _poi_ordered:
		result.append(poi)
	return result

func _load_base_definitions() -> void:
	_reload_from_directory_for_validation(BASE_DEFINITIONS_DIR, BASE_NAMESPACE)

func _reload_from_directory_for_validation(dir_path: String, definition_namespace: StringName = BASE_NAMESPACE) -> bool:
	_reset_load_state()
	if not _load_definitions_from_directory(dir_path, definition_namespace):
		return false
	if _feature_ordered.is_empty():
		return _fail_load("WorldFeatureRegistry requires at least one valid feature hook definition")
	if _poi_ordered.is_empty():
		return _fail_load("WorldFeatureRegistry requires at least one valid POI definition")
	_is_ready = true
	_last_load_error = ""
	return true

func _load_definitions_from_directory(dir_path: String, definition_namespace: StringName) -> bool:
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		return _fail_load("WorldFeatureRegistry failed to open definitions directory: %s" % dir_path)
	var resource_paths: Array[String] = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and (entry.ends_with(".tres") or entry.ends_with(".res")):
			resource_paths.append("%s/%s" % [dir_path, entry])
		entry = dir.get_next()
	dir.list_dir_end()
	resource_paths.sort()
	for path: String in resource_paths:
		var resource: Resource = load(path)
		if resource == null:
			return _fail_load("WorldFeatureRegistry failed to load definition resource: %s" % path)
		if resource is FeatureHookDataScript:
			if not _register_feature(resource as FeatureHookDataScript, definition_namespace):
				return false
		elif resource is PoiDefinitionScript:
			if not _register_poi(resource as PoiDefinitionScript, definition_namespace):
				return false
		else:
			return _fail_load("WorldFeatureRegistry rejected unsupported definition resource at %s" % path)
	return true

func _register_feature(feature: Resource, definition_namespace: StringName) -> bool:
	var typed_feature: FeatureHookDataScript = feature as FeatureHookDataScript
	if typed_feature == null:
		return _fail_load("WorldFeatureRegistry received invalid feature definition resource")
	var runtime_feature: FeatureHookDataScript = typed_feature.duplicate(true) as FeatureHookDataScript
	if runtime_feature == null:
		return _fail_load("WorldFeatureRegistry failed to duplicate FeatureHookData: %s" % typed_feature)
	runtime_feature.id = _make_namespaced_id(runtime_feature.id, definition_namespace)
	if str(runtime_feature.id).is_empty():
		return _fail_load("WorldFeatureRegistry rejected feature hook with empty id")
	if _features_by_id.has(runtime_feature.id):
		return _fail_load("WorldFeatureRegistry found duplicate feature hook id: %s" % str(runtime_feature.id))
	_features_by_id[runtime_feature.id] = runtime_feature
	_feature_ordered.append(runtime_feature)
	return true

func _register_poi(poi: Resource, definition_namespace: StringName) -> bool:
	var typed_poi: PoiDefinitionScript = poi as PoiDefinitionScript
	if typed_poi == null:
		return _fail_load("WorldFeatureRegistry received invalid POI definition resource")
	var runtime_poi: PoiDefinitionScript = typed_poi.duplicate(true) as PoiDefinitionScript
	if runtime_poi == null:
		return _fail_load("WorldFeatureRegistry failed to duplicate PoiDefinition: %s" % typed_poi)
	runtime_poi.id = _make_namespaced_id(runtime_poi.id, definition_namespace)
	if str(runtime_poi.id).is_empty():
		return _fail_load("WorldFeatureRegistry rejected POI with empty id")
	if not runtime_poi.has_explicit_anchor_offset():
		return _fail_load("WorldFeatureRegistry rejected POI without explicit anchor_offset: %s" % str(runtime_poi.id))
	if not runtime_poi.has_explicit_priority():
		return _fail_load("WorldFeatureRegistry rejected POI without explicit priority: %s" % str(runtime_poi.id))
	if _pois_by_id.has(runtime_poi.id):
		return _fail_load("WorldFeatureRegistry found duplicate POI id: %s" % str(runtime_poi.id))
	_pois_by_id[runtime_poi.id] = runtime_poi
	_poi_ordered.append(runtime_poi)
	return true

func _make_namespaced_id(short_id: StringName, definition_namespace: StringName) -> StringName:
	var id_str: String = str(short_id)
	if id_str.is_empty():
		return &""
	if id_str.contains(":"):
		return short_id
	return StringName("%s:%s" % [str(definition_namespace), id_str])

func _reset_load_state() -> void:
	_is_ready = false
	_last_load_error = ""
	_features_by_id.clear()
	_feature_ordered.clear()
	_pois_by_id.clear()
	_poi_ordered.clear()

func _fail_load(message: String) -> bool:
	_last_load_error = message
	push_error(message)
	_is_ready = false
	_features_by_id.clear()
	_feature_ordered.clear()
	_pois_by_id.clear()
	_poi_ordered.clear()
	return false
