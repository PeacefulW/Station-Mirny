extends Player


func _ready() -> void:
	# The reload smoke needs only PlayerAuthority's typed local-player contract.
	# Skipping the production state-machine setup keeps this fixture minimal and
	# avoids unrelated RefCounted state cycles during headless teardown.
	add_to_group("player")
