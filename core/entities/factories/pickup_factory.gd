class_name PickupFactory
extends RefCounted

## Фабрика предметов на земле.

func create_item_pickup(item_id: String, amount: int, position: Vector2) -> Area2D:
	var pickup := Area2D.new()
	pickup.global_position = position
	pickup.collision_layer = 0
	pickup.collision_mask = 1
	pickup.monitoring = true
	pickup.monitorable = false
	pickup.set_meta("item_id", item_id)
	pickup.set_meta("amount", amount)

	var visual := Sprite2D.new()
	visual.name = "Visual"
	var item_data: ItemData = ItemRegistry.get_item(item_id)
	visual.texture = item_data.icon if item_data else null
	pickup.add_child(visual)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 18.0
	collision.shape = shape
	pickup.add_child(collision)

	return pickup
