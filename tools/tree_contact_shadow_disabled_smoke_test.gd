extends SceneTree

const WorldDecorBatchLayer = preload("res://core/systems/world/world_decor_batch_layer.gd")
const WorldObjectPacketLayer = preload("res://core/systems/world/world_object_packet_layer.gd")

const OBJECT_KIND_TREE: int = 4

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var layer := WorldObjectPacketLayer.new()
	root.add_child(layer)
	layer.set_tree_atlas(_make_texture(1536, 1536))
	layer.configure_packet(_single_tree_packet())
	layer.set_sun_lighting(220.0, 90.0, 0.5, 18.0)

	var state: Dictionary = layer.get_debug_state()
	_assert(int(state.get("tree_count", 0)) == 1, "WorldObjectPacketLayer must consume the synthetic tree.")
	_assert(
		not bool(state.get("tree_contact_shadow_enabled", true)),
		"Tree flat contact shadow must stay disabled; it creates an oval spot under the sprite.",
	)

	var tree_batch: Node = layer.get_node_or_null("TreeObjectPacketBatchLayer")
	_assert(tree_batch != null, "Tree sprite batch layer must exist.")
	if tree_batch != null:
		var batch_state: Dictionary = tree_batch.call("get_debug_state") as Dictionary
		_assert(int(batch_state.get("instance_count", 0)) == 1, "Tree sprite batch must contain one instance.")
		_assert(
			int(batch_state.get("shadow_instance_count", -1)) == 0,
			"Tree contact-shadow batch must stay empty.",
		)

	var silhouette_layer: Node = layer.get_node_or_null("TreeSilhouetteShadowLayer")
	_assert(silhouette_layer != null and silhouette_layer.visible, "Tree sun silhouette shadow must remain available.")

	layer.free()
	if _failed:
		quit(1)
		return
	print("tree_contact_shadow_disabled_smoke_test: OK")
	quit(0)


func _single_tree_packet() -> Dictionary:
	return {
		"object_kind": PackedByteArray([OBJECT_KIND_TREE]),
		"object_local_x_px_q4": PackedByteArray([128]),
		"object_local_y_px_q4": PackedByteArray([128]),
		"object_size_px": PackedByteArray([180]),
		"object_atlas_index": PackedByteArray([0]),
		"object_variant": PackedByteArray([0]),
		"object_flags": PackedByteArray([0]),
		"object_tint": PackedByteArray([255]),
		"object_phase": PackedByteArray([0]),
	}


func _make_texture(width: int, height: int) -> Texture2D:
	var image := Image.create(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	_failed = true
	push_error(message)
