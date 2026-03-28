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
	_features_by_id.clear()
	_feature_ordered.clear()
	_pois_by_id.clear()
	_poi_ordered.clear()
	_is_ready = _load_definitions_from_directory(BASE_DEFINITIONS_DIR, BASE_NAMESPACE) \
		and not _feature_ordered.is_empty() \
		and not _poi_ordered.is_empty()

func _load_definitions_from_directory(dir_path: String, definition_namespace: StringName) -> bool:
	var dir: DirAccess = DirAccess.open(dir_path)
	if not dir:
		push_error("WorldFeatureRegistry failed to open definitions directory: %s" % dir_path)
		return false
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
			push_error("WorldFeatureRegistry failed to load definition resource: %s" % path)
			continue
		if resource is FeatureHookDataScript:
			_register_feature(resource as FeatureHookDataScript, definition_namespace)
		elif resource is PoiDefinitionScript:
			_register_poi(resource as PoiDefinitionScript, definition_namespace)
		else:
			push_warning("WorldFeatureRegistry ignored unsupported definition resource at %s" % path)
	return true

func _register_feature(feature: Resource, definition_namespace: StringName) -> void:
	var typed_feature: FeatureHookDataScript = feature as FeatureHookDataScript
	if typed_feature == null:
		return
	var runtime_feature: FeatureHookDataScript = typed_feature.duplicate(true) as FeatureHookDataScript
	if runtime_feature == null:
		push_error("WorldFeatureRegistry failed to duplicate FeatureHookData: %s" % typed_feature)
		return
	runtime_feature.id = _make_namespaced_id(runtime_feature.id, definition_namespace)
	if str(runtime_feature.id).is_empty():
		push_error("WorldFeatureRegistry rejected feature hook with empty id")
		return
	if _features_by_id.has(runtime_feature.id):
		push_error("WorldFeatureRegistry found duplicate feature hook id: %s" % str(runtime_feature.id))
		return
	_features_by_id[runtime_feature.id] = runtime_feature
	_feature_ordered.append(runtime_feature)

func _register_poi(poi: Resource, definition_namespace: StringName) -> void:
	var typed_poi: PoiDefinitionScript = poi as PoiDefinitionScript
	if typed_poi == null:
		return
	var runtime_poi: PoiDefinitionScript = typed_poi.duplicate(true) as PoiDefinitionScript
	if runtime_poi == null:
		push_error("WorldFeatureRegistry failed to duplicate PoiDefinition: %s" % typed_poi)
		return
	runtime_poi.id = _make_namespaced_id(runtime_poi.id, definition_namespace)
	if str(runtime_poi.id).is_empty():
		push_error("WorldFeatureRegistry rejected POI with empty id")
		return
	if not runtime_poi.has_explicit_anchor_offset():
		push_error("WorldFeatureRegistry rejected POI without explicit anchor_offset: %s" % str(runtime_poi.id))
		return
	if not runtime_poi.has_explicit_priority():
		push_error("WorldFeatureRegistry rejected POI without explicit priority: %s" % str(runtime_poi.id))
		return
	if _pois_by_id.has(runtime_poi.id):
		push_error("WorldFeatureRegistry found duplicate POI id: %s" % str(runtime_poi.id))
		return
	_pois_by_id[runtime_poi.id] = runtime_poi
	_poi_ordered.append(runtime_poi)

func _make_namespaced_id(short_id: StringName, definition_namespace: StringName) -> StringName:
	var id_str: String = str(short_id)
	if id_str.is_empty():
		return &""
	if id_str.contains(":"):
		return short_id
	return StringName("%s:%s" % [str(definition_namespace), id_str])
