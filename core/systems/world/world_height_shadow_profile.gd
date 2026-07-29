class_name WorldHeightShadowProfile
extends Resource

## Presentation-only height model for projected world-object shadows.
##
## Feet/Y depth sorting still owns object-to-object occlusion. This profile is
## a second, orthogonal axis used only to decide which materials may receive a
## shadow cast by a taller object.

## Godot exposes twenty CanvasItem visibility layers. The last layer is
## reserved for the offscreen tall-caster pass; ordinary world viewports still
## see the caster through its regular visibility bits.
const CASTER_VISIBILITY_LAYER_BIT: int = 19
const CASTER_VISIBILITY_LAYER: int = 1 << CASTER_VISIBILITY_LAYER_BIT

enum ReceiverClass {
	GROUND,
	GRASS,
	SMALL_ROCK,
	BUSH,
	TREE,
}

## Authored presentation heights. These are material-class metadata, not
## per-instance z-index overrides and not gameplay/collision dimensions.
@export_group("Field")
@export_range(0.25, 1.0, 0.05) var mask_resolution_scale: float = 0.5
@export var receiver_tint: Color = Color(0.32, 0.34, 0.40, 1.0)
@export_range(0.001, 1.0, 0.001) var height_fade: float = 0.14
@export_enum("Ground", "Grass", "Small Rock", "Bush", "Tree") var caster_class: int = (
	ReceiverClass.TREE
)

@export_group("Heights")
@export_range(0.0, 2.0, 0.01) var ground_height: float = 0.0
@export_range(0.0, 2.0, 0.01) var grass_height: float = 0.12
@export_range(0.0, 2.0, 0.01) var small_rock_height: float = 0.34
@export_range(0.0, 2.0, 0.01) var bush_height: float = 0.66
@export_range(0.0, 2.0, 0.01) var tree_height: float = 1.0

@export_group("Receiver Strength")
@export_range(0.0, 1.0, 0.01) var ground_strength: float = 1.0
@export_range(0.0, 1.0, 0.01) var grass_strength: float = 0.88
@export_range(0.0, 1.0, 0.01) var small_rock_strength: float = 0.94
@export_range(0.0, 1.0, 0.01) var bush_strength: float = 0.72
@export_range(0.0, 1.0, 0.01) var tree_strength: float = 0.0


func height_for(receiver_class: int) -> float:
	match receiver_class:
		ReceiverClass.GROUND:
			return ground_height
		ReceiverClass.GRASS:
			return grass_height
		ReceiverClass.SMALL_ROCK:
			return small_rock_height
		ReceiverClass.BUSH:
			return bush_height
		ReceiverClass.TREE:
			return tree_height
		_:
			push_error("WorldHeightShadowProfile: unknown receiver class %d" % receiver_class)
			return tree_height


func strength_for(receiver_class: int) -> float:
	match receiver_class:
		ReceiverClass.GROUND:
			return ground_strength
		ReceiverClass.GRASS:
			return grass_strength
		ReceiverClass.SMALL_ROCK:
			return small_rock_strength
		ReceiverClass.BUSH:
			return bush_strength
		ReceiverClass.TREE:
			return tree_strength
		_:
			push_error("WorldHeightShadowProfile: unknown receiver class %d" % receiver_class)
			return 0.0


static func mark_tall_caster_path(item: CanvasItem) -> void:
	if item == null or not is_instance_valid(item):
		return
	var current: Node = item
	while current != null:
		if current is CanvasItem:
			var canvas_item: CanvasItem = current as CanvasItem
			canvas_item.visibility_layer |= CASTER_VISIBILITY_LAYER
		current = current.get_parent()
