class_name TerrainVisualRecipePayload
extends RefCounted

static func make_payload(recipe: Resource) -> Dictionary:
	if recipe == null:
		return { }
	return {
		"schema_version": int(recipe.get("schema_version")),
		"recipe_id": recipe.get("id"),
		"surface_kind": recipe.get("surface_kind"),
		"tile_size_px": int(recipe.get("tile_size_px")),
		"rim_width_px": float(recipe.get("rim_width_px")),
		"south_height_px": float(recipe.get("south_height_px")),
		"north_height_px": float(recipe.get("north_height_px")),
		"side_height_px": float(recipe.get("side_height_px")),
		"face_power": float(recipe.get("face_power")),
		"back_drop": float(recipe.get("back_drop")),
		"normal_strength": float(recipe.get("normal_strength")),
	}


static func recipe_id(recipe: Resource) -> StringName:
	if recipe == null:
		return &""
	var id: Variant = recipe.get("id")
	if id is StringName:
		return id
	if id is String:
		return StringName(id)
	return &""
