class_name WorldRenderWorld
extends Node2D
## Global data-oriented renderer for visible world sprites.
##
## Chunk packets/results remain the storage and worker-cache format. This node
## owns the only static-world body and shadow GPU buffers; no chunk, family or
## depth stripe creates a CanvasItem or MultiMesh.

const WorldRuntimeConstants = preload("res://core/systems/world/world_runtime_constants.gd")
const WorldTileSetFactory = preload("res://core/systems/world/world_tile_set_factory.gd")
const WorldVisualLightingProfile = preload(
	"res://core/systems/world/world_visual_lighting_profile.gd"
)
const WorldRenderClassRegistry = preload(
	"res://core/systems/world/world_render_class_registry.gd"
)
const GROUND_SHADER: Shader = preload("res://assets/shaders/world_render_ground.gdshader")
const BODY_SHADER: Shader = preload("res://assets/shaders/world_render_body.gdshader")
const SHADOW_SHADER: Shader = preload("res://assets/shaders/world_render_shadow.gdshader")
const EMISSIVE_SHADER: Shader = preload("res://assets/shaders/world_render_emissive.gdshader")
const OVERHEAD_SHADER: Shader = preload("res://assets/shaders/world_render_overhead.gdshader")

const GPU_INSTANCE_STRIDE_FLOATS: int = 16
const GPU_FLOAT_BYTES: int = 4
const MAX_RENDER_PAGE_SLOTS: int = 17
const GRASS_WIND_NOISE_SIZE: int = 1024
const GRASS_WIND_NOISE_TEXELS_PER_CELL: int = 4

var _world_core: Object = null
var _catalog: WorldLayeredObjectAssetCatalog = null
var _registry: WorldRenderClassRegistry = null
var _ground_layers: Array[MultiMeshInstance2D] = []
var _body_layers: Array[MultiMeshInstance2D] = []
var _shadow_layers: Array[MultiMeshInstance2D] = []
var _emissive_layers: Array[MultiMeshInstance2D] = []
var _overhead_layers: Array[MultiMeshInstance2D] = []
var _staging_ground_layers: Array[MultiMeshInstance2D] = []
var _staging_body_layers: Array[MultiMeshInstance2D] = []
var _staging_shadow_layers: Array[MultiMeshInstance2D] = []
var _staging_emissive_layers: Array[MultiMeshInstance2D] = []
var _staging_overhead_layers: Array[MultiMeshInstance2D] = []
var _object_shadow_layer: MultiMeshInstance2D = null
var _staging_object_shadow_layer: MultiMeshInstance2D = null
var _actor_shadow_layer: MultiMeshInstance2D = null
var _spore_layer: MultiMeshInstance2D = null
var _staging_spore_layer: MultiMeshInstance2D = null
var _ground_multimeshes: Array[MultiMesh] = []
var _body_multimeshes: Array[MultiMesh] = []
var _shadow_multimeshes: Array[MultiMesh] = []
var _emissive_multimeshes: Array[MultiMesh] = []
var _overhead_multimeshes: Array[MultiMesh] = []
var _staging_ground_multimeshes: Array[MultiMesh] = []
var _staging_body_multimeshes: Array[MultiMesh] = []
var _staging_shadow_multimeshes: Array[MultiMesh] = []
var _staging_emissive_multimeshes: Array[MultiMesh] = []
var _staging_overhead_multimeshes: Array[MultiMesh] = []
var _object_shadow_multimesh: MultiMesh = null
var _staging_object_shadow_multimesh: MultiMesh = null
var _actor_shadow_multimesh: MultiMesh = null
var _spore_multimesh: MultiMesh = null
var _staging_spore_multimesh: MultiMesh = null
var _ground_material: ShaderMaterial = null
var _body_material: ShaderMaterial = null
var _shadow_material: ShaderMaterial = null
var _emissive_material: ShaderMaterial = null
var _overhead_material: ShaderMaterial = null
var _spore_material: ShaderMaterial = null
var _grass_atlas: Texture2D = null
var _grass_wind_noise_texture: ImageTexture = null
var _configured: bool = false
var _snapshot_generation: int = 0
var _pending_snapshot_result: Dictionary = { }
var _pending_snapshot_pages: Array = []
var _pending_snapshot_page_cursor: int = 0
var _pending_snapshot_stream_cursor: int = 0
var _pending_snapshot_build_usec: int = 0
var _pending_snapshot_upload_usec: int = 0
var _pending_snapshot_ground_counts: PackedInt32Array = PackedInt32Array()
var _pending_snapshot_body_counts: PackedInt32Array = PackedInt32Array()
var _pending_snapshot_shadow_counts: PackedInt32Array = PackedInt32Array()
var _pending_snapshot_emissive_counts: PackedInt32Array = PackedInt32Array()
var _pending_snapshot_overhead_counts: PackedInt32Array = PackedInt32Array()
var _pending_object_shadow_count: int = 0
var _pending_snapshot_gpu_float_count: int = 0
var _pending_static_snapshot: Dictionary = { }
var _active_static_snapshot: Dictionary = { }
var _visual_proxies: Dictionary = { }
var _active_actor_page_ys: Array[int] = []
var _active_page_window_min_y: int = 0
var _active_static_pass_window_min_y: int = 0
var _last_actor_records_hash: int = 0
var _has_actor_records_hash: bool = false
var _ground_group_enabled: bool = true
var _body_group_enabled: bool = true
var _shadow_group_enabled: bool = true
var _emissive_group_enabled: bool = true
var _overhead_group_enabled: bool = true
var _spore_group_enabled: bool = true
var _last_state: Dictionary = {
	"ready": false,
	"instance_count": 0,
}


func configure(
		catalog: WorldLayeredObjectAssetCatalog,
		grass_atlas: Texture2D,
		grass_shadow_atlas: Texture2D,
		grass_material: ShaderMaterial,
		grass_spore_material: ShaderMaterial,
) -> bool:
	if catalog == null or not catalog.is_ready() \
			or grass_atlas == null or grass_shadow_atlas == null \
			or grass_material == null or grass_spore_material == null:
		push_error("WorldRenderWorld.configure requires prepared catalog and grass sources")
		return false
	if not ClassDB.class_exists(&"WorldCore"):
		push_error("WorldRenderWorld requires the native WorldCore extension")
		return false
	_world_core = ClassDB.instantiate(&"WorldCore")
	if _world_core == null or not _world_core.has_method("build_world_render_snapshot") \
			or not _world_core.has_method("compose_world_render_actors") \
			or not _world_core.has_method("build_periodic_gradient_noise_texture"):
		push_error("WorldRenderWorld native snapshot builder is unavailable")
		return false
	_registry = WorldRenderClassRegistry.new()
	if not _registry.configure():
		push_error("WorldRenderWorld could not load the authored render-class registry")
		return false
	if not _prepare_grass_wind_noise_texture():
		push_error("WorldRenderWorld could not build the bounded grass wind field")
		return false
	_catalog = catalog
	_grass_atlas = grass_atlas
	_spore_material = grass_spore_material
	_prepare_materials(grass_material)
	_prepare_layers()
	process_physics_priority = 2
	set_physics_process(true)
	_configured = true
	_last_state = {
		"ready": true,
		"instance_count": 0,
		"snapshot_generation": 0,
		"render_registry": _registry.get_debug_contract(),
	}
	return true


func is_ready() -> bool:
	return _configured


func register_visual_proxy(proxy: Node) -> bool:
	if not _configured or proxy == null \
			or not proxy.has_method("get_world_render_record") \
			or not proxy.has_method("set_world_render_proxy_active"):
		return false
	_visual_proxies[proxy.get_instance_id()] = weakref(proxy)
	_has_actor_records_hash = false
	_publish_actor_snapshot(true)
	return true


func unregister_visual_proxy(proxy: Node) -> void:
	if proxy == null:
		return
	_visual_proxies.erase(proxy.get_instance_id())
	proxy.call("set_world_render_proxy_active", false)
	_has_actor_records_hash = false
	_publish_actor_snapshot(true)


func _physics_process(_delta: float) -> void:
	_publish_actor_snapshot(false)


func _collect_actor_records() -> Array:
	var records: Array = []
	var expired_ids: Array[int] = []
	for proxy_id_variant: Variant in _visual_proxies.keys():
		var proxy_id: int = int(proxy_id_variant)
		var reference: WeakRef = _visual_proxies.get(proxy_id) as WeakRef
		var proxy: Object = reference.get_ref() if reference != null else null
		if proxy == null or not is_instance_valid(proxy):
			expired_ids.append(proxy_id)
			continue
		var record_variant: Variant = proxy.call("get_world_render_record")
		if record_variant is Dictionary:
			var record: Dictionary = (record_variant as Dictionary).duplicate(false)
			var descriptor_id: int = _registry.get_actor_descriptor_id(
				int(record.get("sprite_id", -1)),
			)
			if descriptor_id < 0:
				push_error("WorldRenderWorld actor record references an unknown sprite descriptor")
				continue
			record["sprite_id"] = descriptor_id
			records.append(record)
	for proxy_id: int in expired_ids:
		_visual_proxies.erase(proxy_id)
	return records


func _publish_actor_snapshot(force: bool) -> void:
	if not _configured or _world_core == null or _active_static_snapshot.is_empty():
		return
	var records: Array = _collect_actor_records()
	var records_hash: int = hash(records)
	if not force and _has_actor_records_hash and records_hash == _last_actor_records_hash:
		return
	var composed: Dictionary = _compose_actor_snapshot(_active_static_snapshot, records)
	if composed.is_empty():
		return
	_apply_actor_composition(composed)
	_last_actor_records_hash = records_hash
	_has_actor_records_hash = true
	_set_visual_proxies_active(true)


func _compose_actor_snapshot(static_snapshot: Dictionary, records: Array) -> Dictionary:
	var composed_variant: Variant = _world_core.call(
		"compose_world_render_actors",
		static_snapshot,
		records,
	)
	if not composed_variant is Dictionary:
		push_error("WorldRenderWorld actor composer returned a non-Dictionary result")
		return { }
	var composed: Dictionary = composed_variant as Dictionary
	if not bool(composed.get("success", false)):
		push_error(
			"WorldRenderWorld actor composition failed: %s"
			% str(composed.get("error", "unknown error")),
		)
		return { }
	return composed


func _apply_actor_composition(composed: Dictionary) -> void:
	var pages: Array = composed.get("pages", []) as Array
	var next_min_y: int = int(composed.get("page_window_min_y", 0))
	var next_actor_page_ys: Array[int] = []
	for slot_variant: Variant in composed.get("actor_page_slots", PackedInt32Array()):
		next_actor_page_ys.append(next_min_y + int(slot_variant))
	var remap_all_pages: bool = next_min_y != _active_page_window_min_y \
			or pages.size() != int(_last_state.get("render_page_slot_count", pages.size()))
	if remap_all_pages:
		for slot: int in range(MAX_RENDER_PAGE_SLOTS):
			_apply_composed_page_slot(slot, pages)
		_remap_static_pass_depth(next_min_y)
	else:
		var dirty_page_ys: Dictionary = { }
		for page_y: int in _active_actor_page_ys:
			dirty_page_ys[page_y] = true
		for page_y: int in next_actor_page_ys:
			dirty_page_ys[page_y] = true
		for page_y_variant: Variant in dirty_page_ys.keys():
			var slot: int = int(page_y_variant) - next_min_y
			if slot >= 0 and slot < MAX_RENDER_PAGE_SLOTS:
				_apply_composed_page_slot(slot, pages)
	_apply_buffer(
		_actor_shadow_multimesh,
		composed.get("actor_shadow_buffer", PackedFloat32Array()) as PackedFloat32Array,
		int(composed.get("actor_shadow_count", 0)),
		composed.get("actor_shadow_bounds", Rect2()),
	)
	_actor_shadow_layer.visible = _shadow_group_enabled \
			and _actor_shadow_multimesh.instance_count > 0
	_active_actor_page_ys = next_actor_page_ys
	_active_page_window_min_y = next_min_y
	_last_state["instance_count"] = int(composed.get("instance_count", 0))
	_last_state["gpu_buffer_bytes"] = int(composed.get("buffer_float_count", 0)) * GPU_FLOAT_BYTES
	_last_state["actor_count"] = int(composed.get("actor_count", 0))
	_last_state["actor_shadow_count"] = int(composed.get("actor_shadow_count", 0))
	_last_state["render_page_slot_count"] = pages.size()


func _remap_static_pass_depth(composed_min_y: int) -> void:
	# Static buffers retain their uploaded slots when an actor extends the page
	# window. Move only their depth origin so grass and bodies still share pages.
	var slot_offset: int = _active_static_pass_window_min_y - composed_min_y
	for slot: int in range(MAX_RENDER_PAGE_SLOTS):
		_ground_layers[slot].z_index = \
				WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + slot + slot_offset
		_emissive_layers[slot].z_index = \
				WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE + slot + slot_offset
		_overhead_layers[slot].z_index = \
				WorldRuntimeConstants.Z_RENDER_OVERHEAD_PAGE_BASE + slot + slot_offset


func _apply_composed_page_slot(slot: int, pages: Array) -> void:
	if slot < 0 or slot >= MAX_RENDER_PAGE_SLOTS:
		return
	if slot >= pages.size():
		_apply_buffer(_body_multimeshes[slot], PackedFloat32Array(), 0, Rect2())
		_body_layers[slot].visible = false
		return
	var page: Dictionary = pages[slot] as Dictionary
	_apply_buffer(
		_body_multimeshes[slot],
		page.get("body_buffer", PackedFloat32Array()) as PackedFloat32Array,
		int(page.get("body_instance_count", 0)),
		page.get("body_bounds", Rect2()),
	)
	_body_layers[slot].z_index = WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + slot
	_body_layers[slot].visible = _body_group_enabled \
			and _body_multimeshes[slot].instance_count > 0


func _set_visual_proxies_active(active: bool) -> void:
	for reference_variant: Variant in _visual_proxies.values():
		var reference: WeakRef = reference_variant as WeakRef
		var proxy: Object = reference.get_ref() if reference != null else null
		if proxy != null and is_instance_valid(proxy):
			proxy.call("set_world_render_proxy_active", active)


func _exit_tree() -> void:
	_set_visual_proxies_active(false)
	if _ground_material != null:
		WorldTileSetFactory.unregister_ground_visual_field_material(_ground_material)


func get_native_source_bindings() -> Array:
	return _registry.get_native_source_bindings() if _registry != null else []


func publish_snapshot(
		chunk_origins: PackedVector2Array,
		object_results: Array,
		grass_results: Array,
		grass_lod_fraction: float,
) -> bool:
	if not _configured or _world_core == null:
		return false
	var build_started_usec: int = Time.get_ticks_usec()
	var result_variant: Variant = _world_core.call(
		"build_world_render_snapshot",
		chunk_origins,
		object_results,
		grass_results,
		_registry.get_native_source_bindings(),
		grass_lod_fraction,
	)
	var build_elapsed_usec: int = Time.get_ticks_usec() - build_started_usec
	if not result_variant is Dictionary:
		push_error("WorldRenderWorld native builder returned a non-Dictionary result")
		return false
	var result: Dictionary = result_variant as Dictionary
	if not bool(result.get("success", false)):
		push_error(
			"WorldRenderWorld snapshot failed: %s" % str(result.get("error", "unknown error")),
		)
		return false
	result["chunk_count"] = chunk_origins.size()
	result["grass_lod_fraction"] = grass_lod_fraction
	return begin_built_snapshot(result, build_elapsed_usec)


## Validates and retains an immutable worker result without touching the active
## GPU bank. advance_built_snapshot() uploads at most a caller-selected number
## of pages per frame, then swaps the complete bank in one visibility commit.
func begin_built_snapshot(result: Dictionary, build_elapsed_usec: int) -> bool:
	if not _configured or has_pending_snapshot() \
			or not bool(result.get("success", false)):
		return false
	var static_snapshot: Dictionary = result.duplicate(true)
	var composed_variant: Variant = _world_core.call(
		"compose_world_render_actors",
		static_snapshot,
		_collect_actor_records(),
	)
	if not composed_variant is Dictionary:
		push_error("WorldRenderWorld initial actor composer returned a non-Dictionary result")
		return false
	result = composed_variant as Dictionary
	if not bool(result.get("success", false)):
		push_error(
			"WorldRenderWorld initial actor composition failed: %s"
			% str(result.get("error", "unknown error")),
		)
		return false
	var pages: Array = result.get("pages", []) as Array
	var spore_buffer: PackedFloat32Array = result.get(
		"spore_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var actor_shadow_buffer: PackedFloat32Array = result.get(
		"actor_shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var object_shadow_buffer: PackedFloat32Array = result.get(
		"object_shadow_buffer",
		PackedFloat32Array(),
	) as PackedFloat32Array
	var instance_count: int = int(result.get("instance_count", 0))
	var spore_count: int = int(result.get("spore_count", 0))
	var world_shadow_count: int = int(result.get("world_shadow_count", 0))
	var object_shadow_count: int = int(result.get("object_shadow_count", 0))
	var actor_shadow_count: int = int(result.get("actor_shadow_count", 0))
	if pages.size() > MAX_RENDER_PAGE_SLOTS \
			or spore_buffer.size() != spore_count * 12 \
			or object_shadow_buffer.size() \
					!= object_shadow_count * GPU_INSTANCE_STRIDE_FLOATS \
			or actor_shadow_buffer.size() \
					!= actor_shadow_count * GPU_INSTANCE_STRIDE_FLOATS:
		push_error("WorldRenderWorld native buffer/count contract mismatch")
		return false
	var page_instance_total: int = 0
	var page_buffer_float_total: int = 0
	var ground_counts := PackedInt32Array()
	var body_counts := PackedInt32Array()
	var shadow_counts := PackedInt32Array()
	var emissive_counts := PackedInt32Array()
	var overhead_counts := PackedInt32Array()
	ground_counts.resize(MAX_RENDER_PAGE_SLOTS)
	body_counts.resize(MAX_RENDER_PAGE_SLOTS)
	shadow_counts.resize(MAX_RENDER_PAGE_SLOTS)
	emissive_counts.resize(MAX_RENDER_PAGE_SLOTS)
	overhead_counts.resize(MAX_RENDER_PAGE_SLOTS)
	for page_index: int in range(pages.size()):
		var page: Dictionary = pages[page_index] as Dictionary
		var page_count: int = int(page.get("instance_count", 0))
		var pass_ids: Array[String] = ["ground", "body", "shadow", "emissive", "overhead"]
		var pass_counts: Array[int] = []
		for pass_id: String in pass_ids:
			var count_key: String = "body_instance_count" if pass_id == "body" \
					else "%s_count" % pass_id
			var pass_count: int = int(page.get(count_key, 0))
			var pass_buffer: PackedFloat32Array = page.get(
				"%s_buffer" % pass_id,
				PackedFloat32Array(),
			) as PackedFloat32Array
			if pass_buffer.size() != pass_count * GPU_INSTANCE_STRIDE_FLOATS:
				push_error("WorldRenderWorld %s page buffer/count mismatch" % pass_id)
				return false
			pass_counts.append(pass_count)
			page_buffer_float_total += pass_buffer.size()
		ground_counts[page_index] = pass_counts[0]
		body_counts[page_index] = pass_counts[1]
		shadow_counts[page_index] = pass_counts[2]
		emissive_counts[page_index] = pass_counts[3]
		overhead_counts[page_index] = pass_counts[4]
		if page_count != pass_counts[0] + pass_counts[1]:
			push_error("WorldRenderWorld primary pass count mismatch")
			return false
		page_instance_total += page_count
	if page_instance_total != instance_count \
			or _sum_counts(shadow_counts) + object_shadow_count != world_shadow_count:
		push_error("WorldRenderWorld page instance total mismatch")
		return false
	_pending_snapshot_result = result
	_pending_static_snapshot = static_snapshot
	_pending_snapshot_pages = pages
	_pending_snapshot_page_cursor = 0
	_pending_snapshot_stream_cursor = 0
	_pending_snapshot_build_usec = build_elapsed_usec
	_pending_snapshot_upload_usec = 0
	_pending_snapshot_ground_counts = ground_counts
	_pending_snapshot_body_counts = body_counts
	_pending_snapshot_shadow_counts = shadow_counts
	_pending_snapshot_emissive_counts = emissive_counts
	_pending_snapshot_overhead_counts = overhead_counts
	_pending_object_shadow_count = object_shadow_count
	_pending_snapshot_gpu_float_count = page_buffer_float_total + spore_buffer.size() \
			+ object_shadow_buffer.size() + actor_shadow_buffer.size()
	for layers: Array in [
		_staging_ground_layers,
		_staging_body_layers,
		_staging_shadow_layers,
		_staging_emissive_layers,
		_staging_overhead_layers,
	]:
		for layer: MultiMeshInstance2D in layers:
			layer.visible = false
	_staging_object_shadow_layer.visible = false
	_staging_spore_layer.visible = false
	return true


func has_pending_snapshot() -> bool:
	return not _pending_snapshot_result.is_empty()


## Returns true only on the frame where the complete staging bank is committed.
func advance_built_snapshot(max_upload_phases: int = 1) -> bool:
	if not has_pending_snapshot():
		return false
	var upload_started_usec: int = Time.get_ticks_usec()
	var phases_this_call: int = 0
	# One fixed-pass page bundle is one bounded phase. Empty absolute page slots
	# are retained and explicitly cleared.
	while _pending_snapshot_page_cursor < MAX_RENDER_PAGE_SLOTS \
			and phases_this_call < maxi(max_upload_phases, 1):
		phases_this_call += 1
		var page_index: int = _pending_snapshot_page_cursor
		var page: Dictionary = _pending_snapshot_pages[page_index] as Dictionary \
				if page_index < _pending_snapshot_pages.size() else { }
		_apply_buffer(
				_staging_ground_multimeshes[page_index],
				page.get("ground_buffer", PackedFloat32Array()) as PackedFloat32Array,
				_pending_snapshot_ground_counts[page_index],
				page.get("ground_bounds", Rect2()),
			)
		_apply_buffer(
				_staging_body_multimeshes[page_index],
				page.get("body_buffer", PackedFloat32Array()) as PackedFloat32Array,
				_pending_snapshot_body_counts[page_index],
				page.get("body_bounds", Rect2()),
			)
		_apply_buffer(
				_staging_shadow_multimeshes[page_index],
				page.get("shadow_buffer", PackedFloat32Array()) as PackedFloat32Array,
				_pending_snapshot_shadow_counts[page_index],
				page.get("shadow_bounds", Rect2()),
		)
		_apply_buffer(
				_staging_emissive_multimeshes[page_index],
				page.get("emissive_buffer", PackedFloat32Array()) as PackedFloat32Array,
				_pending_snapshot_emissive_counts[page_index],
				page.get("emissive_bounds", Rect2()),
			)
		_apply_buffer(
				_staging_overhead_multimeshes[page_index],
				page.get("overhead_buffer", PackedFloat32Array()) as PackedFloat32Array,
				_pending_snapshot_overhead_counts[page_index],
				page.get("overhead_bounds", Rect2()),
			)
		_staging_ground_layers[page_index].z_index = \
					WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index
		_staging_body_layers[page_index].z_index = \
					WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index
		_staging_shadow_layers[page_index].z_index = WorldRuntimeConstants.Z_WORLD_SHADOW
		_staging_emissive_layers[page_index].z_index = \
					WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE + page_index
		_staging_overhead_layers[page_index].z_index = \
					WorldRuntimeConstants.Z_RENDER_OVERHEAD_PAGE_BASE + page_index
		_pending_snapshot_page_cursor += 1
	_pending_snapshot_upload_usec += Time.get_ticks_usec() - upload_started_usec
	if _pending_snapshot_page_cursor < MAX_RENDER_PAGE_SLOTS:
		return false

	upload_started_usec = Time.get_ticks_usec()
	# Staging may span many frames. Validate the current actor set before the
	# swap so a moved/unregistered proxy cannot reappear in its staged old pose.
	var actor_records: Array = _collect_actor_records()
	var composed: Dictionary = _compose_actor_snapshot(_pending_static_snapshot, actor_records)
	if composed.is_empty():
		return false
	var spore_count: int = int(_pending_snapshot_result.get("spore_count", 0))
	_apply_buffer(
		_staging_spore_multimesh,
		_pending_snapshot_result.get("spore_buffer", PackedFloat32Array()) \
				as PackedFloat32Array,
		spore_count,
		_pending_snapshot_result.get("spore_bounds", Rect2()),
	)
	_apply_buffer(
		_staging_object_shadow_multimesh,
		_pending_snapshot_result.get("object_shadow_buffer", PackedFloat32Array()) \
				as PackedFloat32Array,
		_pending_object_shadow_count,
		_pending_snapshot_result.get("object_shadow_bounds", Rect2()),
	)
	# Nothing in the staging bank becomes drawable before every page is ready.
	# The active bank is hidden and the complete replacement is exposed in this
	# one commit, so terrain/object revisions cannot mix on screen.
	_hide_active_bank()
	for page_index: int in range(MAX_RENDER_PAGE_SLOTS):
		_staging_ground_layers[page_index].visible = \
				_ground_group_enabled and _pending_snapshot_ground_counts[page_index] > 0
		_staging_body_layers[page_index].visible = \
				_body_group_enabled and _pending_snapshot_body_counts[page_index] > 0
		_staging_shadow_layers[page_index].visible = \
				_shadow_group_enabled and _pending_snapshot_shadow_counts[page_index] > 0
		_staging_emissive_layers[page_index].visible = \
				_emissive_group_enabled and _pending_snapshot_emissive_counts[page_index] > 0
		_staging_overhead_layers[page_index].visible = \
				_overhead_group_enabled and _pending_snapshot_overhead_counts[page_index] > 0
	_staging_object_shadow_layer.visible = \
			_shadow_group_enabled and _pending_object_shadow_count > 0
	_actor_shadow_layer.visible = _shadow_group_enabled \
			and _actor_shadow_multimesh.instance_count > 0
	_staging_spore_layer.visible = _spore_group_enabled and spore_count > 0
	_swap_gpu_banks()
	_active_static_snapshot = _pending_static_snapshot
	_active_page_window_min_y = int(_pending_snapshot_result.get("page_window_min_y", 0))
	_active_static_pass_window_min_y = _active_page_window_min_y
	_active_actor_page_ys.clear()
	for slot_variant: Variant in _pending_snapshot_result.get(
			"actor_page_slots",
			PackedInt32Array(),
	):
		_active_actor_page_ys.append(_active_page_window_min_y + int(slot_variant))
	_commit_pending_snapshot_state(spore_count)
	_apply_actor_composition(composed)
	_pending_snapshot_upload_usec += Time.get_ticks_usec() - upload_started_usec
	_last_state["upload_usec"] = _pending_snapshot_upload_usec
	_last_actor_records_hash = hash(actor_records)
	_has_actor_records_hash = true
	_set_visual_proxies_active(true)
	_clear_pending_snapshot_metadata()
	return true


func cancel_pending_snapshot() -> void:
	if not has_pending_snapshot():
		return
	for layers: Array in [
		_staging_ground_layers,
		_staging_body_layers,
		_staging_shadow_layers,
		_staging_emissive_layers,
		_staging_overhead_layers,
	]:
		for layer: MultiMeshInstance2D in layers:
			layer.visible = false
	_staging_object_shadow_layer.visible = false
	_staging_spore_layer.visible = false
	_clear_pending_snapshot_metadata()


func clear_snapshot() -> void:
	cancel_pending_snapshot()
	_hide_active_bank()
	for multimesh: MultiMesh in _ground_multimeshes + _body_multimeshes \
			+ _shadow_multimeshes + _emissive_multimeshes + _overhead_multimeshes \
			+ _staging_ground_multimeshes + _staging_body_multimeshes \
			+ _staging_shadow_multimeshes + _staging_emissive_multimeshes \
			+ _staging_overhead_multimeshes:
		multimesh.instance_count = 0
	_object_shadow_multimesh.instance_count = 0
	_staging_object_shadow_multimesh.instance_count = 0
	_actor_shadow_multimesh.instance_count = 0
	_spore_multimesh.instance_count = 0
	_staging_spore_multimesh.instance_count = 0
	_active_static_snapshot.clear()
	_active_actor_page_ys.clear()
	_has_actor_records_hash = false
	_set_visual_proxies_active(false)
	_last_state = {
		"ready": _configured,
		"instance_count": 0,
		"snapshot_generation": _snapshot_generation,
		"render_registry": _registry.get_debug_contract() if _registry != null else { },
	}


func _commit_pending_snapshot_state(spore_count: int) -> void:
	_snapshot_generation += 1
	var state: Dictionary = _last_state.duplicate(true)
	var descriptor_counts: PackedInt32Array = _pending_snapshot_result.get(
		"descriptor_counts",
		PackedInt32Array(),
	) as PackedInt32Array
	var active_draw_calls: int = _count_nonzero(_pending_snapshot_ground_counts) \
			+ _count_nonzero(_pending_snapshot_body_counts) \
			+ _count_nonzero(_pending_snapshot_shadow_counts) \
			+ _count_nonzero(_pending_snapshot_emissive_counts) \
			+ _count_nonzero(_pending_snapshot_overhead_counts)
	active_draw_calls += 1 if _pending_object_shadow_count > 0 else 0
	active_draw_calls += 1 if int(_pending_snapshot_result.get("actor_shadow_count", 0)) > 0 else 0
	active_draw_calls += 1 if spore_count > 0 else 0
	state.merge({
		"ready": true,
		"snapshot_generation": _snapshot_generation,
		"chunk_count": int(_pending_snapshot_result.get("chunk_count", 0)),
		"instance_count": int(_pending_snapshot_result.get("instance_count", 0)),
		"descriptor_counts": descriptor_counts,
		"descriptor_counts_by_id": _registry.describe_descriptor_counts(descriptor_counts),
		"source_binding_count": int(_pending_snapshot_result.get("source_binding_count", 0)),
		"spore_count": spore_count,
		"grass_lod_fraction": float(_pending_snapshot_result.get("grass_lod_fraction", 1.0)),
		"build_usec": _pending_snapshot_build_usec,
		"upload_usec": _pending_snapshot_upload_usec,
		"gpu_buffer_bytes": _pending_snapshot_gpu_float_count * GPU_FLOAT_BYTES,
		"ground_multimesh_count": _count_nonzero(_pending_snapshot_ground_counts),
		"body_multimesh_count": _count_nonzero(_pending_snapshot_body_counts),
		"shadow_multimesh_count": _count_nonzero(_pending_snapshot_shadow_counts) \
				+ (1 if _pending_object_shadow_count > 0 else 0) \
				+ (1 if int(_pending_snapshot_result.get("actor_shadow_count", 0)) > 0 else 0),
		"emissive_multimesh_count": _count_nonzero(_pending_snapshot_emissive_counts),
		"overhead_multimesh_count": _count_nonzero(_pending_snapshot_overhead_counts),
		"render_page_count": int(_pending_snapshot_result.get("render_page_count", 0)),
		"render_page_slot_count": _pending_snapshot_pages.size(),
		"actor_count": int(_pending_snapshot_result.get("actor_count", 0)),
		"actor_shadow_count": int(_pending_snapshot_result.get("actor_shadow_count", 0)),
		"world_shadow_count": int(_pending_snapshot_result.get("world_shadow_count", 0)),
		"ground_shadow_count": _sum_counts(_pending_snapshot_shadow_counts),
		"object_shadow_count": _pending_object_shadow_count,
		"render_atom_stride_bytes": int(
			_pending_snapshot_result.get("render_atom_stride_bytes", 0)
		),
		"cpu_render_atom_capacity_bytes": int(
			_pending_snapshot_result.get("cpu_render_atom_capacity_bytes", 0)
		),
		"cpu_sort_index_capacity_bytes": int(
			_pending_snapshot_result.get("cpu_sort_index_capacity_bytes", 0)
		),
		"cpu_snapshot_working_set_bound_bytes": int(
			_pending_snapshot_result.get("cpu_snapshot_working_set_bound_bytes", 0)
		),
		"active_draw_call_count": active_draw_calls,
		"authored_draw_call_bound": MAX_RENDER_PAGE_SLOTS * 5 + 3,
		"fixed_material_count": 6,
		"render_registry": _registry.get_debug_contract(),
	}, true)
	_last_state = state


func publish_ground_field(
		chunk_origins: PackedVector2Array,
		grass_results: Array,
) -> bool:
	if not _configured or _world_core == null:
		return false
	var started_usec: int = Time.get_ticks_usec()
	var result_variant: Variant = _world_core.call(
		"build_ground_field_snapshot",
		chunk_origins,
		grass_results,
	)
	var build_usec: int = Time.get_ticks_usec() - started_usec
	if not result_variant is Dictionary:
		push_error("Ground field builder returned a non-Dictionary result")
		return false
	var result: Dictionary = result_variant as Dictionary
	if not bool(result.get("success", false)):
		push_error("Ground field snapshot failed: %s" % str(result.get("error", "unknown error")))
		return false
	var upload_started_usec: int = Time.get_ticks_usec()
	if not WorldTileSetFactory.publish_ground_visual_field(result):
		push_error("Ground field texture upload failed")
		return false
	var state: Dictionary = _last_state.duplicate(true)
	state["ground_field_ready"] = true
	state["ground_field_build_usec"] = build_usec
	state["ground_field_upload_usec"] = Time.get_ticks_usec() - upload_started_usec
	state["ground_field_size"] = Vector2i(
		int(result.get("width", 0)),
		int(result.get("height", 0)),
	)
	state["ground_field_bytes"] = int(result.get("payload_bytes", 0))
	_last_state = state
	return true


func set_season_amount(amount: float) -> void:
	if _body_material != null:
		_body_material.set_shader_parameter("season_amount", clampf(amount, 0.0, 1.0))


func set_sun_lighting(shadow_length_px: float, shadow_opacity: float) -> void:
	if _shadow_material == null:
		return
	var low_sun: float = clampf(
		(shadow_length_px - WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX) / maxf(
			WorldVisualLightingProfile.SHADOW_MAX_LENGTH_PX \
					- WorldVisualLightingProfile.SHADOW_MIN_LENGTH_PX,
			0.001,
		),
		0.0,
		1.0,
	)
	_shadow_material.set_shader_parameter("shadow_length_scale", lerpf(1.0, 1.85, low_sun))
	_shadow_material.set_shader_parameter("object_shadow_softness_texels", lerpf(
		WorldVisualLightingProfile.MIN_OBJECT_SHADOW_SOFTNESS_TEXELS,
		WorldVisualLightingProfile.MAX_OBJECT_SHADOW_SOFTNESS_TEXELS,
		low_sun,
	))
	_shadow_material.set_shader_parameter(
		"object_shadow_opacity",
		clampf(shadow_opacity * 0.60, 0.0, 0.60),
	)


func get_body_material() -> ShaderMaterial:
	return _body_material


func get_debug_state() -> Dictionary:
	return _last_state.duplicate(true)


func set_group_enabled(group: StringName, enabled: bool) -> void:
	match group:
		&"grass":
			_ground_material.set_shader_parameter("ground_profiles_visible", enabled)
		&"grass_shadow":
			_shadow_material.set_shader_parameter("ground_profiles_visible", enabled)
		&"grass_spore":
			_spore_group_enabled = enabled
			_spore_layer.visible = enabled and int(_last_state.get("spore_count", 0)) > 0
		&"objects":
			_body_material.set_shader_parameter("object_profiles_visible", enabled)
			_shadow_material.set_shader_parameter("object_profiles_visible", enabled)
		&"obj_shadow":
			_shadow_material.set_shader_parameter("object_profiles_visible", enabled)
		&"body":
			_body_group_enabled = enabled
			for layer: MultiMeshInstance2D in _body_layers:
				layer.visible = enabled and layer.multimesh.instance_count > 0
		&"ground":
			_ground_group_enabled = enabled
			for layer: MultiMeshInstance2D in _ground_layers:
				layer.visible = enabled and layer.multimesh.instance_count > 0
		&"emissive":
			_emissive_group_enabled = enabled
			for layer: MultiMeshInstance2D in _emissive_layers:
				layer.visible = enabled and layer.multimesh.instance_count > 0
		&"overhead":
			_overhead_group_enabled = enabled
			for layer: MultiMeshInstance2D in _overhead_layers:
				layer.visible = enabled and layer.multimesh.instance_count > 0
		&"shadow":
			_shadow_group_enabled = enabled
			for layer: MultiMeshInstance2D in _shadow_layers:
				layer.visible = enabled and layer.multimesh.instance_count > 0
			_object_shadow_layer.visible = enabled \
					and _object_shadow_multimesh.instance_count > 0
			_actor_shadow_layer.visible = enabled \
					and _actor_shadow_multimesh.instance_count > 0


func _prepare_layers() -> void:
	var unit_quad := QuadMesh.new()
	unit_quad.size = Vector2.ONE
	_object_shadow_multimesh = _make_multimesh(unit_quad, true)
	_staging_object_shadow_multimesh = _make_multimesh(unit_quad, true)
	_actor_shadow_multimesh = _make_multimesh(unit_quad, true)
	_spore_multimesh = _make_multimesh(unit_quad, false)
	_staging_spore_multimesh = _make_multimesh(unit_quad, false)

	for page_index: int in range(MAX_RENDER_PAGE_SLOTS):
		_append_page_layer(
			"Ground", page_index, false, unit_quad, _ground_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index,
			_ground_layers, _ground_multimeshes,
		)
		_append_page_layer(
			"Body", page_index, false, unit_quad, _body_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index,
			_body_layers, _body_multimeshes,
		)
		_append_page_layer(
			"Shadow", page_index, false, unit_quad, _shadow_material,
			_registry.get_texture(&"shadow"),
			WorldRuntimeConstants.Z_WORLD_SHADOW,
			_shadow_layers, _shadow_multimeshes,
		)
		_append_page_layer(
			"Emissive", page_index, false, unit_quad, _emissive_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE + page_index,
			_emissive_layers, _emissive_multimeshes,
		)
		_append_page_layer(
			"Overhead", page_index, false, unit_quad, _overhead_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_OVERHEAD_PAGE_BASE + page_index,
			_overhead_layers, _overhead_multimeshes,
		)
		_append_page_layer(
			"Ground", page_index, true, unit_quad, _ground_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index,
			_staging_ground_layers, _staging_ground_multimeshes,
		)
		_append_page_layer(
			"Body", page_index, true, unit_quad, _body_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_BODY_PAGE_BASE + page_index,
			_staging_body_layers, _staging_body_multimeshes,
		)
		_append_page_layer(
			"Shadow", page_index, true, unit_quad, _shadow_material,
			_registry.get_texture(&"shadow"),
			WorldRuntimeConstants.Z_WORLD_SHADOW,
			_staging_shadow_layers, _staging_shadow_multimeshes,
		)
		_append_page_layer(
			"Emissive", page_index, true, unit_quad, _emissive_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_EMISSIVE_PAGE_BASE + page_index,
			_staging_emissive_layers, _staging_emissive_multimeshes,
		)
		_append_page_layer(
			"Overhead", page_index, true, unit_quad, _overhead_material,
			_registry.get_texture(&"body_base"),
			WorldRuntimeConstants.Z_RENDER_OVERHEAD_PAGE_BASE + page_index,
			_staging_overhead_layers, _staging_overhead_multimeshes,
		)

	_object_shadow_layer = MultiMeshInstance2D.new()
	_object_shadow_layer.name = "WorldRenderObjectShadow"
	_object_shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_object_shadow_layer.texture = _registry.get_texture(&"shadow")
	_object_shadow_layer.material = _shadow_material
	_object_shadow_layer.multimesh = _object_shadow_multimesh
	_object_shadow_layer.z_index = WorldRuntimeConstants.Z_WORLD_SHADOW
	_object_shadow_layer.visible = false
	add_child(_object_shadow_layer)

	_staging_object_shadow_layer = MultiMeshInstance2D.new()
	_staging_object_shadow_layer.name = "WorldRenderObjectShadowStaging"
	_staging_object_shadow_layer.texture_filter = \
			CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_staging_object_shadow_layer.texture = _registry.get_texture(&"shadow")
	_staging_object_shadow_layer.material = _shadow_material
	_staging_object_shadow_layer.multimesh = _staging_object_shadow_multimesh
	_staging_object_shadow_layer.z_index = WorldRuntimeConstants.Z_WORLD_SHADOW
	_staging_object_shadow_layer.visible = false
	add_child(_staging_object_shadow_layer)

	_actor_shadow_layer = MultiMeshInstance2D.new()
	_actor_shadow_layer.name = "WorldRenderActorShadow"
	_actor_shadow_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_actor_shadow_layer.texture = _registry.get_texture(&"actor_shadow")
	_actor_shadow_layer.material = _shadow_material
	_actor_shadow_layer.multimesh = _actor_shadow_multimesh
	_actor_shadow_layer.z_index = WorldRuntimeConstants.Z_ACTOR_SHADOW
	_actor_shadow_layer.visible = false
	add_child(_actor_shadow_layer)

	_spore_layer = MultiMeshInstance2D.new()
	_spore_layer.name = "WorldRenderSpore"
	_spore_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_spore_layer.texture = _grass_atlas
	_spore_layer.material = _spore_material
	_spore_layer.multimesh = _spore_multimesh
	_spore_layer.z_index = WorldRuntimeConstants.Z_GRASS_SPORE
	_spore_layer.visible = false
	add_child(_spore_layer)

	_staging_spore_layer = MultiMeshInstance2D.new()
	_staging_spore_layer.name = "WorldRenderSporeStaging"
	_staging_spore_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_staging_spore_layer.texture = _grass_atlas
	_staging_spore_layer.material = _spore_material
	_staging_spore_layer.multimesh = _staging_spore_multimesh
	_staging_spore_layer.z_index = WorldRuntimeConstants.Z_GRASS_SPORE
	_staging_spore_layer.visible = false
	add_child(_staging_spore_layer)


func _append_page_layer(
		pass_name: String,
		page_index: int,
		staging: bool,
		mesh: Mesh,
		material: Material,
		texture: Texture2D,
		z: int,
		layers: Array[MultiMeshInstance2D],
		multimeshes: Array[MultiMesh],
) -> void:
	var multimesh: MultiMesh = _make_multimesh(mesh, true)
	var layer := MultiMeshInstance2D.new()
	layer.name = "WorldRender%s%sPage%02d" % [
		pass_name,
		"Staging" if staging else "",
		page_index,
	]
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	layer.texture = texture
	layer.material = material
	layer.multimesh = multimesh
	layer.z_index = z
	layer.visible = false
	add_child(layer)
	multimeshes.append(multimesh)
	layers.append(layer)


func _hide_active_bank() -> void:
	for layers: Array in [
		_ground_layers, _body_layers, _shadow_layers, _emissive_layers, _overhead_layers,
	]:
		for layer: MultiMeshInstance2D in layers:
			layer.visible = false
	_object_shadow_layer.visible = false
	_spore_layer.visible = false


func _swap_gpu_banks() -> void:
	var old_ground_layers: Array[MultiMeshInstance2D] = _ground_layers
	_ground_layers = _staging_ground_layers
	_staging_ground_layers = old_ground_layers
	var old_body_layers: Array[MultiMeshInstance2D] = _body_layers
	_body_layers = _staging_body_layers
	_staging_body_layers = old_body_layers
	var old_shadow_layers: Array[MultiMeshInstance2D] = _shadow_layers
	_shadow_layers = _staging_shadow_layers
	_staging_shadow_layers = old_shadow_layers
	var old_emissive_layers: Array[MultiMeshInstance2D] = _emissive_layers
	_emissive_layers = _staging_emissive_layers
	_staging_emissive_layers = old_emissive_layers
	var old_overhead_layers: Array[MultiMeshInstance2D] = _overhead_layers
	_overhead_layers = _staging_overhead_layers
	_staging_overhead_layers = old_overhead_layers

	var old_ground_multimeshes: Array[MultiMesh] = _ground_multimeshes
	_ground_multimeshes = _staging_ground_multimeshes
	_staging_ground_multimeshes = old_ground_multimeshes
	var old_body_multimeshes: Array[MultiMesh] = _body_multimeshes
	_body_multimeshes = _staging_body_multimeshes
	_staging_body_multimeshes = old_body_multimeshes
	var old_shadow_multimeshes: Array[MultiMesh] = _shadow_multimeshes
	_shadow_multimeshes = _staging_shadow_multimeshes
	_staging_shadow_multimeshes = old_shadow_multimeshes
	var old_emissive_multimeshes: Array[MultiMesh] = _emissive_multimeshes
	_emissive_multimeshes = _staging_emissive_multimeshes
	_staging_emissive_multimeshes = old_emissive_multimeshes
	var old_overhead_multimeshes: Array[MultiMesh] = _overhead_multimeshes
	_overhead_multimeshes = _staging_overhead_multimeshes
	_staging_overhead_multimeshes = old_overhead_multimeshes
	var old_object_shadow_layer: MultiMeshInstance2D = _object_shadow_layer
	_object_shadow_layer = _staging_object_shadow_layer
	_staging_object_shadow_layer = old_object_shadow_layer
	var old_object_shadow_multimesh: MultiMesh = _object_shadow_multimesh
	_object_shadow_multimesh = _staging_object_shadow_multimesh
	_staging_object_shadow_multimesh = old_object_shadow_multimesh
	var old_spore_layer: MultiMeshInstance2D = _spore_layer
	_spore_layer = _staging_spore_layer
	_staging_spore_layer = old_spore_layer
	var old_spore_multimesh: MultiMesh = _spore_multimesh
	_spore_multimesh = _staging_spore_multimesh
	_staging_spore_multimesh = old_spore_multimesh


func _clear_pending_snapshot_metadata() -> void:
	_pending_snapshot_result.clear()
	_pending_static_snapshot = { }
	_pending_snapshot_pages.clear()
	_pending_snapshot_page_cursor = 0
	_pending_snapshot_stream_cursor = 0
	_pending_snapshot_build_usec = 0
	_pending_snapshot_upload_usec = 0
	_pending_snapshot_ground_counts = PackedInt32Array()
	_pending_snapshot_body_counts = PackedInt32Array()
	_pending_snapshot_shadow_counts = PackedInt32Array()
	_pending_snapshot_emissive_counts = PackedInt32Array()
	_pending_snapshot_overhead_counts = PackedInt32Array()
	_pending_object_shadow_count = 0
	_pending_snapshot_gpu_float_count = 0


static func _count_nonzero(counts: PackedInt32Array) -> int:
	var result: int = 0
	for count: int in counts:
		if count > 0:
			result += 1
	return result


static func _sum_counts(counts: PackedInt32Array) -> int:
	var result: int = 0
	for count: int in counts:
		result += count
	return result


func _make_multimesh(mesh: Mesh, use_custom_data: bool) -> MultiMesh:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_2D
	multimesh.use_colors = true
	multimesh.use_custom_data = use_custom_data
	multimesh.mesh = mesh
	multimesh.instance_count = 0
	return multimesh


func _apply_buffer(
		multimesh: MultiMesh,
		buffer: PackedFloat32Array,
		instance_count: int,
		bounds_variant: Variant,
) -> void:
	multimesh.instance_count = instance_count
	multimesh.visible_instance_count = instance_count
	if instance_count > 0:
		multimesh.buffer = buffer
	var bounds := Rect2()
	if bounds_variant is Rect2:
		bounds = bounds_variant as Rect2
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		multimesh.custom_aabb = AABB(
			Vector3(bounds.position.x, bounds.position.y, -1.0),
			Vector3(bounds.size.x, bounds.size.y, 2.0),
		)


func _prepare_materials(grass_material: ShaderMaterial) -> void:
	_ground_material = ShaderMaterial.new()
	_ground_material.shader = GROUND_SHADER
	_body_material = ShaderMaterial.new()
	_body_material.shader = BODY_SHADER
	_shadow_material = ShaderMaterial.new()
	_shadow_material.shader = SHADOW_SHADER
	_emissive_material = ShaderMaterial.new()
	_emissive_material.shader = EMISSIVE_SHADER
	_overhead_material = ShaderMaterial.new()
	_overhead_material.shader = OVERHEAD_SHADER

	_ground_material.set_shader_parameter(
		"world_body_base_atlas",
		_registry.get_texture(&"body_base"),
	)
	_ground_material.set_shader_parameter("grass_gust_noise", _grass_wind_noise_texture)
	_ground_material.set_shader_parameter(
		"grass_gust_noise_period_cells",
		float(GRASS_WIND_NOISE_SIZE / GRASS_WIND_NOISE_TEXELS_PER_CELL),
	)
	_body_material.set_shader_parameter(
		"world_body_base_atlas",
		_registry.get_texture(&"body_base"),
	)
	_body_material.set_shader_parameter(
		"world_foliage_atlas",
		_registry.get_texture(&"foliage"),
	)
	_body_material.set_shader_parameter(
		"world_snow_overlay_atlas",
		_registry.get_texture(&"snow_overlay"),
	)
	_body_material.set_shader_parameter(
		"world_wind_mask_atlas",
		_registry.get_texture(&"wind_mask"),
	)
	_body_material.set_shader_parameter(
		"world_snow_mask_atlas",
		_registry.get_texture(&"snow_mask"),
	)
	_body_material.set_shader_parameter(
		"world_season_mask_atlas",
		_registry.get_texture(&"season_mask"),
	)
	_body_material.set_shader_parameter("actor_body_atlas", _registry.get_texture(&"actor_body"))
	_shadow_material.set_shader_parameter("world_shadow_atlas", _registry.get_texture(&"shadow"))
	_shadow_material.set_shader_parameter("actor_shadow_atlas", _registry.get_texture(&"actor_shadow"))
	for material: ShaderMaterial in [
		_ground_material,
		_body_material,
		_shadow_material,
		_emissive_material,
		_overhead_material,
	]:
		material.set_shader_parameter("render_descriptor_lut", _registry.get_descriptor_lut())
		# The LUT is authored-width, not always MAX_SHADER_DESCRIPTORS; the shader
		# default would sample the wrong column for any other capacity.
		material.set_shader_parameter(
			"render_descriptor_capacity",
			float(_registry.get_descriptor_capacity()),
		)
	for material: ShaderMaterial in [
		_ground_material,
		_body_material,
		_emissive_material,
		_overhead_material,
	]:
		material.set_shader_parameter("render_variant_crop_lut", _registry.get_variant_crop_lut())
	_shadow_material.set_shader_parameter(
		"render_variant_anchor_lut",
		_registry.get_variant_anchor_lut(),
	)
	_emissive_material.set_shader_parameter("render_aux_atlas", _registry.get_texture(&"emissive"))
	_overhead_material.set_shader_parameter("render_aux_atlas", _registry.get_texture(&"overhead"))
	_body_material.set_shader_parameter("season_amount", _catalog.get_season_amount())
	_copy_grass_parameter(grass_material, "wind_sway_fraction", "grass_wind_sway_fraction")
	_copy_grass_parameter(grass_material, "storm_lean_fraction", "grass_storm_lean_fraction")
	_copy_grass_parameter(grass_material, "gust_field_scale_px", "grass_gust_field_scale_px")
	_copy_grass_parameter(grass_material, "gust_field_anisotropy", "grass_gust_field_anisotropy")
	_copy_grass_parameter(grass_material, "local_dir_min_deg", "grass_local_dir_min_deg")
	_copy_grass_parameter(grass_material, "local_dir_max_deg", "grass_local_dir_max_deg")
	_copy_grass_parameter(grass_material, "local_dir_gust_gain", "grass_local_dir_gust_gain")
	_copy_grass_parameter(grass_material, "intra_tuft_flutter", "grass_intra_tuft_flutter")
	_copy_grass_parameter(grass_material, "macro_warm_strength", "grass_macro_warm_strength")
	_copy_grass_parameter(grass_material, "macro_dry_strength", "grass_macro_dry_strength")
	WorldTileSetFactory.register_ground_visual_field_material(_ground_material, 4)
	set_sun_lighting(_catalog.get_sun_shadow_length_px(), _catalog.get_sun_shadow_opacity())


func _prepare_grass_wind_noise_texture() -> bool:
	var bytes_variant: Variant = _world_core.call(
		"build_periodic_gradient_noise_texture",
		GRASS_WIND_NOISE_SIZE,
		GRASS_WIND_NOISE_TEXELS_PER_CELL,
	)
	if not bytes_variant is PackedByteArray:
		return false
	var bytes := bytes_variant as PackedByteArray
	if bytes.size() != GRASS_WIND_NOISE_SIZE * GRASS_WIND_NOISE_SIZE:
		return false
	var image := Image.create_from_data(
		GRASS_WIND_NOISE_SIZE,
		GRASS_WIND_NOISE_SIZE,
		false,
		Image.FORMAT_L8,
		bytes,
	)
	if image == null or image.is_empty():
		return false
	_grass_wind_noise_texture = ImageTexture.create_from_image(image)
	return _grass_wind_noise_texture != null


func _copy_grass_parameter(source: ShaderMaterial, source_name: String, target_name: String) -> void:
	var value: Variant = source.get_shader_parameter(source_name)
	if value != null:
		_ground_material.set_shader_parameter(target_name, value)
