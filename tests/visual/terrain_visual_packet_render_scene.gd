extends Node2D

const TerrainVisualPacketMaterialBuilder = preload(
	"res://data/terrain_visual/terrain_visual_packet_material.gd"
)

var _quad: ColorRect = null


func apply_packet(packet: Dictionary, debug_mode: int) -> void:
	_ensure_quad()
	var material_builder: RefCounted = TerrainVisualPacketMaterialBuilder.new()
	_quad.material = material_builder.build_material(packet, debug_mode)
	_quad.size = Vector2(
		float(packet.get("pixel_width", 0)),
		float(packet.get("pixel_height", 0)),
	)


func _ready() -> void:
	_ensure_quad()


func _ensure_quad() -> void:
	if _quad != null and is_instance_valid(_quad):
		return
	_quad = ColorRect.new()
	_quad.name = "PacketRenderQuad"
	_quad.position = Vector2.ZERO
	_quad.color = Color.WHITE
	add_child(_quad)
