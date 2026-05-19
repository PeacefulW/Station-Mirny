extends GdUnitTestSuite

const RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"
const TerrainVisualRecipePayload = preload(
	"res://data/terrain_visual/terrain_visual_recipe_payload.gd"
)


func test_payload_serializes_authoring_shape_controls() -> void:
	var recipe: Resource = load(RECIPE_PATH).duplicate(true)
	recipe.set("crown_bevel_px", 3.0)
	recipe.set("outer_corner_radius_px", 17.0)
	recipe.set("inner_corner_radius_px", 19.0)
	recipe.set("corner_round_px", 11.0)
	recipe.set("diagonal_smooth_px", 13.0)
	recipe.set("contour_relax", 0.25)
	recipe.set("contour_warp_px", 2.5)
	recipe.set("corner_variation", 0.65)
	recipe.set("geometry_variance", 0.85)
	recipe.set("shape_supersampling", 4)
	recipe.set("edge_debris", 0.35)
	recipe.set("edge_color_strength", 0.45)
	recipe.set("contact_outline_enabled", true)
	recipe.set("contact_outline_width_px", 5.0)
	recipe.set("contact_outline_color", Color(0.1, 0.2, 0.3, 1.0))
	recipe.set("normal_detail_strength", 3.5)
	recipe.set("height_to_normal_blur_radius_px", 2.0)
	recipe.set("bake_height_shading_for_reference", true)

	var payload := TerrainVisualRecipePayload.make_payload(recipe)

	assert_that(payload.get("crown_bevel_px")).is_equal(3.0)
	assert_that(payload.get("outer_corner_radius_px")).is_equal(17.0)
	assert_that(payload.get("inner_corner_radius_px")).is_equal(19.0)
	assert_that(payload.get("corner_round_px")).is_equal(11.0)
	assert_that(payload.get("diagonal_smooth_px")).is_equal(13.0)
	assert_that(payload.get("contour_relax")).is_equal(0.25)
	assert_that(payload.get("contour_warp_px")).is_equal(2.5)
	assert_that(payload.get("corner_variation")).is_equal(0.65)
	assert_that(payload.get("geometry_variance")).is_equal(0.85)
	assert_that(payload.get("shape_supersampling")).is_equal(4)
	assert_that(payload.get("edge_debris")).is_equal(0.35)
	assert_that(payload.get("edge_color_strength")).is_equal(0.45)
	assert_that(payload.get("contact_outline_enabled")).is_equal(true)
	assert_that(payload.get("contact_outline_width_px")).is_equal(5.0)
	assert_that(payload.get("contact_outline_color")).is_equal(Color(0.1, 0.2, 0.3, 1.0))
	assert_that(payload.get("normal_detail_strength")).is_equal(3.5)
	assert_that(payload.get("height_to_normal_blur_radius_px")).is_equal(2.0)
	assert_that(payload.get("bake_height_shading_for_reference")).is_equal(true)


func test_payload_keeps_recipe_default_shape_controls() -> void:
	var recipe: Resource = load(RECIPE_PATH).duplicate(true)
	var payload := TerrainVisualRecipePayload.make_payload(recipe)

	assert_that(float(payload.get("corner_round_px"))).is_greater(0.0)
	assert_that(float(payload.get("diagonal_smooth_px"))).is_greater(0.0)
	assert_that(float(payload.get("contour_relax"))).is_greater(0.0)
	assert_that(float(payload.get("contour_warp_px"))).is_greater(0.0)
	assert_that(float(payload.get("edge_debris"))).is_greater(0.0)
	assert_that(float(payload.get("edge_color_strength"))).is_greater(0.0)
	assert_that(float(payload.get("contact_outline_width_px"))).is_greater(0.0)
	assert_that(float(payload.get("normal_detail_strength"))).is_greater(0.0)
	assert_that(int(payload.get("shape_supersampling"))).is_equal(4)
