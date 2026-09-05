class_name WorldRenderRecord
extends RefCounted
## Shared painter contract for static records and interactive visual proxies.
##
## Static records are produced by WorldCore. Interactive owners publish the
## same canonical painter tuple plus one unit-quad transform; RenderWorld is the
## sole owner that turns either source into GPU buffers.

const RENDER_PAGE_HEIGHT_PX: float = 1024.0

const SEMANTIC_GROUND_BODY: int = 0
const SEMANTIC_STATIC_BODY: int = 10
const SEMANTIC_ACTOR_BODY: int = 20

const PROFILE_GRASS: int = 0
const PROFILE_LAYERED_TREE: int = 1
const PROFILE_SMALL_ROCK: int = 2
const PROFILE_LAYERED_BUSH: int = 3
const PROFILE_DYNAMIC_ACTOR: int = 4


static func page_y_for_feet(feet_y: float) -> int:
	return floori(feet_y / RENDER_PAGE_HEIGHT_PX)


## Converts Sprite2D's authored frame rectangle, transform and offset into the
## unit-quad transform consumed by a 2D MultiMesh. The result is world-space;
## no SceneTree transform lookup is needed by RenderWorld after registration.
static func unit_quad_transform_for_sprite(
		sprite: Sprite2D,
		frame_size_px: Vector2,
) -> Transform2D:
	if sprite == null:
		return Transform2D.IDENTITY
	var source: Transform2D = sprite.global_transform
	return Transform2D(
		source.x * frame_size_px.x,
		source.y * frame_size_px.y,
		source * sprite.offset,
	)
