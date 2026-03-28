extends SceneTree

func _initialize() -> void:
	call_deferred("_run_validation")

func _run_validation() -> void:
	print("[CodexScriptModeSmoke] OK")
	quit(0)
