class_name WorldRenderVisibility
extends RefCounted
## Explicit render-routing contract for the world-resolution compositor.
##
## Everything which participates in world-space depth (terrain, vegetation,
## actors and world effects) uses WORLD_PASS_LAYER and is rendered exactly once
## by the bounded-resolution world viewport. Native output keeps only UI and
## deliberately sparse screen-space presentation. Shadow-caster bits are
## orthogonal and are preserved when a CanvasItem is routed.

const MAIN_WORLD_LAYER: int = 1 << 0
# CanvasItem.light_mask is a separate namespace from visibility_layer. Authored
# world materials and dynamically generated MultiMeshes use Godot's default
# light bit 0, so player PointLight2D nodes must continue to target that bit
# even though their pixels are routed through WORLD_PASS_LAYER below.
const WORLD_LIGHT_MASK: int = 1 << 0
# Bit 18 is isolated from the main-world bit so scaled rendering can route the
# complete world branch through exactly one viewport.
const WORLD_PASS_LAYER: int = 1 << 18
## Compatibility name for ChunkView's existing routing API.
const STATIC_TERRAIN_LAYER: int = WORLD_PASS_LAYER
const MAIN_VIEWPORT_MASK: int = MAIN_WORLD_LAYER
const WORLD_VIEWPORT_MASK: int = WORLD_PASS_LAYER
const WORLD_RENDER_SOURCE_GROUP: StringName = &"world_render_source"


static func route_canvas_item_to_static_terrain(item: CanvasItem) -> void:
	route_canvas_item_to_world_pass(item)


static func route_canvas_item_to_world_pass(item: CanvasItem) -> void:
	if item == null:
		return
	# Items with no main-world bit are not world-color sources and must not be
	# introduced into the compositor pass by routing alone.
	if (item.visibility_layer & MAIN_WORLD_LAYER) == 0:
		return
	item.visibility_layer = \
			(item.visibility_layer & ~MAIN_WORLD_LAYER) | WORLD_PASS_LAYER
	if item is Light2D:
		(item as Light2D).range_item_cull_mask = WORLD_LIGHT_MASK
