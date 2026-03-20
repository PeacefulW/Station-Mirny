class_name PickupItemCommand
extends GameCommand

var _player: Player = null
var _item_id: String = ""
var _amount: int = 0
var _pickup_node: Node = null

func setup(player: Player, item_id: String, amount: int, pickup_node: Node = null) -> PickupItemCommand:
	_player = player
	_item_id = item_id
	_amount = amount
	_pickup_node = pickup_node
	return self

func execute() -> Dictionary:
	if not _player:
		return {
			"success": false,
			"message_key": "SYSTEM_PLAYER_NOT_FOUND",
		}
	if _item_id.is_empty() or _amount <= 0:
		return {
			"success": false,
			"message_key": "SYSTEM_PICKUP_INVALID",
		}
	var collected_amount: int = _player.collect_item(_item_id, _amount)
	if collected_amount <= 0:
		return {
			"success": false,
			"message_key": "SYSTEM_INVENTORY_FULL",
		}
	if _pickup_node and is_instance_valid(_pickup_node):
		_pickup_node.queue_free()
	return {
		"success": true,
		"message_key": "SYSTEM_ITEM_PICKED_UP",
		"message_args": {
			"amount": collected_amount,
		},
		"collected_amount": collected_amount,
	}