extends GdUnitTestSuite

func test_gdunit_addon_metadata_is_available() -> void:
	var config := ConfigFile.new()

	assert_that(FileAccess.file_exists("res://addons/gdUnit4/plugin.cfg")).is_true()
	assert_int(config.load("res://addons/gdUnit4/plugin.cfg")).is_equal(OK)
	assert_that(config.get_value("plugin", "name", "")).is_equal("gdUnit4")


func test_agent_validation_entrypoints_exist() -> void:
	assert_that(FileAccess.file_exists("res://tools/agent/Invoke-AgentValidation.ps1")).is_true()
	assert_that(FileAccess.file_exists("res://tools/agent/Invoke-GdUnit4.ps1")).is_true()
	assert_that(
		FileAccess.file_exists("res://tools/agent/Invoke-GDScriptFormatCheck.ps1"),
	).is_true()
	assert_that(
		FileAccess.file_exists("res://tools/agent/Update-GDExtensionCompileDatabase.ps1"),
	).is_true()


func test_gdextension_hygiene_entrypoint_exists() -> void:
	assert_that(FileAccess.file_exists("res://gdextension/SConstruct")).is_true()
