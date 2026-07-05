extends SceneTree

# Retired diagnostic. Mountain torch blocking now uses MountainTorchShadowField
# instead of per-chunk engine LightOccluder2D geometry.
#
# Run the current proof instead:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_shadow_field_probe.gd


func _init() -> void:
	print("mountain_torch_occluder_render_probe retired; use tools/mountain_torch_shadow_field_probe.gd")
	quit(0)
