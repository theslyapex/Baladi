extends SceneTree

func _initialize() -> void:
	var scripts := [
		"res://scripts/game.gd",
		"res://scripts/cloud_account.gd",
		"res://scripts/validate_levels.gd"
	]
	for path in scripts:
		var resource = ResourceLoader.load(path)
		if resource == null:
			push_error("GDScript failed to load: " + path)
			quit(1)
			return
	print("Baladi GDScript syntax validation passed.")
	quit(0)
