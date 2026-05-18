class_name TerrainVisualRecipePayload
extends RefCounted

const FIXED_GAME_TILE_SIZE_PX := 64
const MAX_RUNTIME_SHAPE_SUPERSAMPLING := 4


static func make_payload(recipe: Resource) -> Dictionary:
	if recipe == null:
		return { }
	return {
		"schema_version": int(recipe.get("schema_version")),
		"recipe_id": recipe.get("id"),
		"surface_kind": recipe.get("surface_kind"),
		"tile_size_px": FIXED_GAME_TILE_SIZE_PX,
		"runtime_tile_size_px": FIXED_GAME_TILE_SIZE_PX,
		"rim_width_px": float(recipe.get("rim_width_px")),
		"south_height_px": float(recipe.get("south_height_px")),
		"north_height_px": float(recipe.get("north_height_px")),
		"side_height_px": float(recipe.get("side_height_px")),
		"face_power": float(recipe.get("face_power")),
		"back_drop": float(recipe.get("back_drop")),
		"crown_bevel_px": float(recipe.get("crown_bevel_px")),
		"outer_corner_radius_px": float(recipe.get("outer_corner_radius_px")),
		"inner_corner_radius_px": float(recipe.get("inner_corner_radius_px")),
		"corner_round_px": float(recipe.get("corner_round_px")),
		"diagonal_smooth_px": float(recipe.get("diagonal_smooth_px")),
		"contour_relax": float(recipe.get("contour_relax")),
		"contour_warp_px": float(recipe.get("contour_warp_px")),
		"corner_variation": float(recipe.get("corner_variation")),
		"geometry_variance": float(recipe.get("geometry_variance")),
		"shape_supersampling": clampi(
			int(recipe.get("shape_supersampling")),
			1,
			MAX_RUNTIME_SHAPE_SUPERSAMPLING,
		),
		"edge_debris": float(recipe.get("edge_debris")),
		"edge_color_strength": float(recipe.get("edge_color_strength")),
		"contact_outline_enabled": bool(recipe.get("contact_outline_enabled")),
		"contact_outline_width_px": float(recipe.get("contact_outline_width_px")),
		"contact_outline_color": recipe.get("contact_outline_color"),
		"normal_strength": float(recipe.get("normal_strength")),
		"normal_detail_strength": float(recipe.get("normal_detail_strength")),
		"height_to_normal_blur_radius_px": float(recipe.get("height_to_normal_blur_radius_px")),
		"bake_height_shading_for_reference": bool(recipe.get("bake_height_shading_for_reference")),
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
