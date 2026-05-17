extends GdUnitTestSuite

const V2_RUNTIME_SETTING := "station_mirny/terrain_visual/v2_chunk_runtime_enabled"
const V2_SPEC_PATH := "res://docs/02_system_specs/world/biome_visual_authoring_variant_d_v2.md"
const V1_SPEC_PATH := "res://docs/02_system_specs/world/biome_visual_authoring_variant_d.md"
const HYBRID_SPEC_PATH := "res://docs/02_system_specs/world/terrain_hybrid_presentation.md"
const SYSTEM_API_PATH := "res://docs/02_system_specs/meta/system_api.md"
const PACKET_SCHEMAS_PATH := "res://docs/02_system_specs/meta/packet_schemas.md"
const MODDING_CONTRACTS_PATH := "res://docs/02_system_specs/meta/modding_extension_contracts.md"
const ARCHIVE_NOTE_PATH := "res://tools/rimworld-autotile-lab/ARCHIVED.md"


func test_v2_runtime_is_default_canonical_chunk_visual_path() -> void:
	assert_that(ProjectSettings.has_setting(V2_RUNTIME_SETTING)).is_true()
	assert_that(bool(ProjectSettings.get_setting(V2_RUNTIME_SETTING, false))).is_true()


func test_cutover_docs_leave_v2_as_only_active_terrain_visual_truth() -> void:
	var v2_spec := _read_text(V2_SPEC_PATH)
	var v1_spec := _read_text(V1_SPEC_PATH)
	var hybrid_spec := _read_text(HYBRID_SPEC_PATH)
	var archive_note := _read_text(ARCHIVE_NOTE_PATH)

	assert_that(
		v2_spec.contains("IT9 decision: Variant D v2 is the canonical terrain visual path"),
	).is_true()
	assert_that(v1_spec.contains("status: superseded")).is_true()
	assert_that(v1_spec.contains("superseded_by:")).is_true()
	assert_that(v1_spec.contains("biome_visual_authoring_variant_d_v2.md")).is_true()
	assert_that(
		hybrid_spec.contains("Variant D v2 is the canonical active terrain visual path for rock"),
	).is_true()
	assert_that(archive_note.contains("historical reference")).is_true()
	assert_that(archive_note.contains("not a runtime source of truth")).is_true()


func test_public_contract_docs_describe_v2_as_canonical_not_feature_flagged() -> void:
	var system_api := _read_text(SYSTEM_API_PATH)
	var packet_schemas := _read_text(PACKET_SCHEMAS_PATH)
	var modding_contracts := _read_text(MODDING_CONTRACTS_PATH)

	assert_that(
		system_api.contains("canonical bridge from authoritative chunk terrain data"),
	).is_true()
	assert_that(
		packet_schemas.contains("canonical `ChunkView` rock runtime presentation"),
	).is_true()
	assert_that(
		modding_contracts.contains("canonical runtime rock chunk presentation"),
	).is_true()
	assert_that(system_api.contains("feature-flagged bridge from authoritative")).is_false()
	assert_that(packet_schemas.contains("feature-flagged `ChunkView` rock runtime")).is_false()
	assert_that(modding_contracts.contains("feature-flagged runtime rock chunk")).is_false()


func _read_text(path: String) -> String:
	assert_that(FileAccess.file_exists(path)).is_true()
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)
