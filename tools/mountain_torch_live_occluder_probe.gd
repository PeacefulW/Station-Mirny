extends SceneTree

# Retired diagnostic. Live torch-vs-mountain blocking no longer builds near-chunk
# LightOccluder2D nodes; it is handled by MountainTorchShadowField over the native
# mountain mask.
#
# Run the current proof instead:
#   Godot_v4.7-stable_win64_console.exe --path . -s tools/mountain_torch_shadow_field_probe.gd


func _init() -> void:
	print("mountain_torch_live_occluder_probe retired; use tools/mountain_torch_shadow_field_probe.gd")
	quit(0)
