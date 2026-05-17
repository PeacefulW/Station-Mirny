@tool
extends EditorPlugin

const WORKBENCH_SCENE: PackedScene = preload(
	"res://addons/biome_visual_authoring_v2/terrain_visual_workbench.tscn"
)

var _workbench: Control = null


func _enter_tree() -> void:
	_workbench = WORKBENCH_SCENE.instantiate() as Control
	if _workbench == null:
		push_error("Biome Visual Authoring V2 failed to instantiate workbench.")
		return
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _workbench)


func _exit_tree() -> void:
	if _workbench == null:
		return
	remove_control_from_docks(_workbench)
	_workbench.free()
	_workbench = null
