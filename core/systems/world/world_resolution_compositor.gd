class_name WorldResolutionCompositor
extends Node
## One bounded-resolution pass for every depth-participating world visual.
##
## The viewport keeps the main viewport's logical size/FOV and shares its
## World2D, physics and camera transform. Only its physical fill resolution is
## reduced. The completed world texture is composited once at native output
## resolution; HUD/loading UI remains native and is never rendered twice.

const WorldRenderVisibility = preload(
	"res://core/systems/world/world_render_visibility.gd"
)

@export_range(0.25, 1.0, 0.05) var world_render_scale: float = 1.0:
	set(value):
		world_render_scale = clampf(value, 0.25, 1.0)
		if is_inside_tree():
			_apply_render_mode()

## Off by default. Dedicated probes opt in explicitly and release builds never
## pay viewport timing instrumentation overhead through this owner.
@export var enable_render_time_measurement: bool = false:
	set(value):
		enable_render_time_measurement = value
		if is_inside_tree():
			_sync_render_time_measurement()

var _main_viewport: Viewport = null
var _terrain_viewport: SubViewport = null
var _composite_layer: CanvasLayer = null
var _composite_rect: TextureRect = null
var _routed_branch_ids: Dictionary = { }
var _native_scale_bypass: bool = true


func _ready() -> void:
	process_priority = 1000
	_main_viewport = get_viewport()
	assert(_main_viewport != null, "WorldResolutionCompositor requires a viewport")
	_build_terrain_viewport()
	_build_composite_surface()
	if not _main_viewport.size_changed.is_connected(_sync_render_size):
		_main_viewport.size_changed.connect(_sync_render_size)
	if not get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.connect(_on_scene_node_added)
	_route_registered_world_branches()
	_apply_render_mode()


func _exit_tree() -> void:
	if get_tree() != null and get_tree().node_added.is_connected(_on_scene_node_added):
		get_tree().node_added.disconnect(_on_scene_node_added)
	for branch_id_variant: Variant in _routed_branch_ids.keys():
		var branch: Object = instance_from_id(int(branch_id_variant))
		if branch == null or not is_instance_valid(branch):
			continue
		if branch is Node \
				and (branch as Node).child_entered_tree.is_connected(
					_on_world_branch_child_entered,
				):
			(branch as Node).child_entered_tree.disconnect(_on_world_branch_child_entered)
	_routed_branch_ids.clear()
	if _main_viewport != null and is_instance_valid(_main_viewport) \
			and _main_viewport.size_changed.is_connected(_sync_render_size):
		_main_viewport.size_changed.disconnect(_sync_render_size)
	# The viewport is owned by the main viewport rather than this retiring world
	# scene, so detach its texture and retire it after the current tree mutation.
	# Freeing it synchronously from _exit_tree() is not legal while Godot is
	# removing the world branch.
	if _composite_rect != null and is_instance_valid(_composite_rect):
		_composite_rect.texture = null
	if _terrain_viewport != null and is_instance_valid(_terrain_viewport):
		_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		RenderingServer.viewport_set_measure_render_time(
			_terrain_viewport.get_viewport_rid(),
			false,
		)
		_terrain_viewport.queue_free()
		_terrain_viewport = null
	if _main_viewport != null and is_instance_valid(_main_viewport):
		RenderingServer.viewport_set_canvas_cull_mask(
			_main_viewport.get_viewport_rid(),
			0xFFFFFFFF,
		)


func _process(_delta: float) -> void:
	if not _native_scale_bypass:
		_sync_canvas_transform()


func get_world_viewport_rid() -> RID:
	if _native_scale_bypass and _main_viewport != null and is_instance_valid(_main_viewport):
		return _main_viewport.get_viewport_rid()
	return _terrain_viewport.get_viewport_rid() \
			if _terrain_viewport != null and is_instance_valid(_terrain_viewport) \
			else RID()


func get_world_render_size() -> Vector2i:
	if _native_scale_bypass and _main_viewport != null and is_instance_valid(_main_viewport):
		return _main_viewport.size
	return _terrain_viewport.size \
			if _terrain_viewport != null and is_instance_valid(_terrain_viewport) \
			else Vector2i.ZERO


func get_static_terrain_viewport_rid() -> RID:
	return RID() if _native_scale_bypass else get_world_viewport_rid()


func get_static_terrain_render_size() -> Vector2i:
	return Vector2i.ZERO if _native_scale_bypass else get_world_render_size()


func _build_terrain_viewport() -> void:
	_terrain_viewport = SubViewport.new()
	_terrain_viewport.name = "WorldRenderViewport"
	_terrain_viewport.disable_3d = true
	_terrain_viewport.transparent_bg = false
	_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_terrain_viewport.world_2d = _main_viewport.world_2d
	_terrain_viewport.handle_input_locally = false
	# Keep the shared-World2D viewport directly under the main viewport. Nesting
	# it below WorldRuntimeV0 (a Node2D) gives it an internal canvas parent and
	# Godot 4.7 disconnects that hook twice when the world scene is retired.
	_main_viewport.add_child(_terrain_viewport)
	RenderingServer.viewport_set_canvas_cull_mask(
		_terrain_viewport.get_viewport_rid(),
		WorldRenderVisibility.WORLD_VIEWPORT_MASK,
	)


func _build_composite_surface() -> void:
	_composite_layer = CanvasLayer.new()
	_composite_layer.name = "WorldCompositeLayer"
	_composite_layer.layer = -100
	add_child(_composite_layer)
	_composite_rect = TextureRect.new()
	_composite_rect.name = "WorldComposite"
	_composite_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_composite_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_composite_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_composite_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_composite_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_composite_rect.texture = _terrain_viewport.get_texture()
	_composite_layer.add_child(_composite_rect)


func _sync_render_size() -> void:
	if _main_viewport == null or _terrain_viewport == null:
		return
	var output_size: Vector2i = _main_viewport.size
	if output_size.x <= 0 or output_size.y <= 0:
		return
	_terrain_viewport.size = Vector2i(
		maxi(1, roundi(float(output_size.x) * world_render_scale)),
		maxi(1, roundi(float(output_size.y) * world_render_scale)),
	)
	_sync_logical_size_override()
	_terrain_viewport.size_2d_override_stretch = true


func _apply_render_mode() -> void:
	if _main_viewport == null or _terrain_viewport == null:
		return
	_native_scale_bypass = world_render_scale >= 0.999
	if _native_scale_bypass:
		# At native scale the main viewport consumes the routed world layer itself.
		# The auxiliary viewport and fullscreen blit stay completely disabled.
		RenderingServer.viewport_set_canvas_cull_mask(
			_main_viewport.get_viewport_rid(),
			WorldRenderVisibility.MAIN_VIEWPORT_MASK
					| WorldRenderVisibility.WORLD_VIEWPORT_MASK,
		)
		_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		if _composite_layer != null:
			_composite_layer.visible = false
	else:
		RenderingServer.viewport_set_canvas_cull_mask(
			_main_viewport.get_viewport_rid(),
			WorldRenderVisibility.MAIN_VIEWPORT_MASK,
		)
		_terrain_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		if _composite_layer != null:
			_composite_layer.visible = true
		_sync_render_size()
		_sync_canvas_transform()
	_sync_render_time_measurement()


func _sync_render_time_measurement() -> void:
	if _terrain_viewport == null or not is_instance_valid(_terrain_viewport):
		return
	RenderingServer.viewport_set_measure_render_time(
		_terrain_viewport.get_viewport_rid(),
		OS.is_debug_build() and enable_render_time_measurement and not _native_scale_bypass,
	)


func _sync_canvas_transform() -> void:
	if _main_viewport == null or _terrain_viewport == null:
		return
	# Mirror the main viewport's visible logical rectangle. The backing texture
	# may have a different physical size after a desktop-window resize, but its
	# centre and Camera2D coordinates must remain identical to the main canvas.
	# UI scaling is handled separately by ThemeDB.
	_sync_logical_size_override()
	_terrain_viewport.canvas_transform = _main_viewport.canvas_transform


func _sync_logical_size_override() -> void:
	if _main_viewport == null or _terrain_viewport == null:
		return
	var visible_rect: Rect2 = _main_viewport.get_visible_rect()
	var effective_logical_size := Vector2i(
		maxi(1, roundi(visible_rect.size.x)),
		maxi(1, roundi(visible_rect.size.y)),
	)
	if _terrain_viewport.size_2d_override != effective_logical_size:
		_terrain_viewport.size_2d_override = effective_logical_size


func _route_registered_world_branches() -> void:
	for node: Node in get_tree().get_nodes_in_group(
			WorldRenderVisibility.WORLD_RENDER_SOURCE_GROUP,
	):
		_route_world_branch(node)


func _on_scene_node_added(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group(WorldRenderVisibility.WORLD_RENDER_SOURCE_GROUP):
		_route_world_branch.call_deferred(node)


func _route_world_branch(branch: Node) -> void:
	if branch == null or not is_instance_valid(branch) or not branch.is_inside_tree():
		return
	var branch_id: int = branch.get_instance_id()
	if not _routed_branch_ids.has(branch_id):
		_routed_branch_ids[branch_id] = true
		if not branch.child_entered_tree.is_connected(_on_world_branch_child_entered):
			branch.child_entered_tree.connect(_on_world_branch_child_entered)
	# Canvas traversal is parent-gated. Structural ancestors may own unrelated
	# native HUD CanvasLayers, so preserve their existing bits and only add the
	# world-pass bit needed to reach this branch.
	var ancestor: Node = branch.get_parent()
	while ancestor != null:
		if ancestor is CanvasItem:
			(ancestor as CanvasItem).visibility_layer |= \
					WorldRenderVisibility.WORLD_PASS_LAYER
		ancestor = ancestor.get_parent()
	_route_world_subtree(branch)


func _on_world_branch_child_entered(child: Node) -> void:
	_route_world_subtree.call_deferred(child)


func _route_world_subtree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is CanvasItem:
		WorldRenderVisibility.route_canvas_item_to_world_pass(node as CanvasItem)
	# A nested viewport is an independent render graph (height masks, minimaps,
	# future reflections). Its children must keep their own visibility contract.
	if node is Viewport:
		return
	for child: Node in node.get_children():
		_route_world_subtree(child)
