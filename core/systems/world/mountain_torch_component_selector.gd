class_name MountainTorchComponentSelector
extends RefCounted

## Torch-only ownership codes. ACTIVE owns the excavated source tile itself.
## SUPPORT lets the derived light-blocking mask consume the native C-S feather
## in the immediately adjacent non-dug tile. This never changes excavation,
## collision or the construction-roof reveal.
const ACTIVE_CODE: int = 255
const SUPPORT_CODE: int = 64


static func build_component_support_halo(
		active_halo: PackedByteArray,
		dug_halo: PackedByteArray,
) -> PackedByteArray:
	var side: int = _square_mask_side(active_halo)
	if side <= 0 or dug_halo.size() != active_halo.size():
		return PackedByteArray()

	var reveal := PackedByteArray()
	reveal.resize(active_halo.size())
	for index: int in range(reveal.size()):
		if int(active_halo[index]) != 0:
			reveal[index] = ACTIVE_CODE

	# Native excavation feathering reaches at most the immediately adjacent
	# tile. Expand from sparse active sources; this runs only on a shadow-field
	# cache miss while the player is inside a cavity.
	for y: int in range(side):
		for x: int in range(side):
			var index: int = y * side + x
			if int(active_halo[index]) == 0:
				continue
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var neighbour_x: int = x + offset_x
					var neighbour_y: int = y + offset_y
					if neighbour_x < 0 or neighbour_y < 0 \
							or neighbour_x >= side or neighbour_y >= side:
						continue
					var neighbour_index: int = neighbour_y * side + neighbour_x
					if int(active_halo[neighbour_index]) == 0 \
							and int(dug_halo[neighbour_index]) == 0:
						reveal[neighbour_index] = SUPPORT_CODE

	# A support cell shared with a foreign dug source is ambiguous. Fail closed:
	# entering one cave must not let its torch see through a separate cavity.
	for y: int in range(side):
		for x: int in range(side):
			var index: int = y * side + x
			if int(dug_halo[index]) == 0 or int(active_halo[index]) != 0:
				continue
			for offset_y: int in range(-1, 2):
				for offset_x: int in range(-1, 2):
					if offset_x == 0 and offset_y == 0:
						continue
					var neighbour_x: int = x + offset_x
					var neighbour_y: int = y + offset_y
					if neighbour_x < 0 or neighbour_y < 0 \
							or neighbour_x >= side or neighbour_y >= side:
						continue
					var neighbour_index: int = neighbour_y * side + neighbour_x
					if int(reveal[neighbour_index]) == SUPPORT_CODE:
						reveal[neighbour_index] = 0
	return reveal


static func _square_mask_side(mask: PackedByteArray) -> int:
	if mask.is_empty():
		return 0
	var side: int = floori(sqrt(float(mask.size())))
	return side if side > 0 and side * side == mask.size() else 0
