extends GdUnitTestSuite

const MATERIAL_SLOT_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_material_slot.gd"
const RECIPE_SCRIPT_PATH := "res://data/terrain_visual/terrain_visual_recipe.gd"
const DEFAULT_ROCK_RECIPE_PATH := "res://data/terrain_visual/recipes/rock_default.tres"


func test_invalid_recipe_reports_required_fields() -> void:
	var recipe: Resource = _new_resource(RECIPE_SCRIPT_PATH)
	if recipe == null:
		return

	var errors: PackedStringArray = recipe.call("validate")

	assert_that(errors.has("id is required")).is_true()
	assert_that(errors.has("top_material is required")).is_true()
	assert_that(errors.has("face_material is required")).is_true()
	assert_that(errors.has("base_material is required")).is_true()
	assert_that(errors.has("back_material is required")).is_true()


func test_image_material_requires_albedo_texture() -> void:
	var material_slot: Resource = _new_resource(MATERIAL_SLOT_SCRIPT_PATH)
	if material_slot == null:
		return
	material_slot.set("source", &"image")

	var errors: PackedStringArray = material_slot.call("validate")

	assert_that(errors.has("image_albedo is required when source is image")).is_true()


func test_default_rock_recipe_loads_and_validates() -> void:
	var recipe: Resource = load(DEFAULT_ROCK_RECIPE_PATH)

	assert_that(recipe).is_not_null()
	assert_that(recipe.get("id")).is_equal(&"core:rock_default")
	assert_that(recipe.get("surface_kind")).is_equal(&"rock")
	assert_that(recipe.call("is_valid_recipe")).is_true()
	assert_that(recipe.call("validate").is_empty()).is_true()


func _new_resource(script_path: String) -> Resource:
	var script: Script = load(script_path)
	assert_that(script).is_not_null()
	if script == null:
		return null
	return script.new()
