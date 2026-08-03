extends SceneTree
## Behavioral and static contract probe for threshold-revealed exposure telemetry.
## The probe exercises the production widget with the production balance while
## source checks protect its quiet, signal-local HUD composition.

const WIDGET_PATH: String = "res://scenes/ui/hud/hud_exposure_widget.gd"
const COMPONENT_PATH: String = (
	"res://core/entities/components/player_exposure_component.gd"
)
const BALANCE_PATH: String = "res://data/balance/player_exposure_balance.tres"
const ICONS_PATH: String = "res://scenes/ui/hud/hud_icons.gd"
const PALETTE_PATH: String = "res://scenes/ui/hud/hud_palette.gd"
const MANAGER_PATH: String = "res://scenes/ui/hud/hud_manager.gd"
const FADE_SETTLE_SECONDS: float = 0.24

var _failed: bool = false


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var widget_source: String = FileAccess.get_file_as_string(WIDGET_PATH)
	var icons_source: String = FileAccess.get_file_as_string(ICONS_PATH)
	var manager_source: String = FileAccess.get_file_as_string(MANAGER_PATH)
	_assert(not widget_source.is_empty(), "Exposure widget source must be readable.")
	_assert(not icons_source.is_empty(), "HUD icon source must be readable.")
	_assert(not manager_source.is_empty(), "HUD manager source must be readable.")
	_check_static_contract(widget_source, icons_source, manager_source)

	var widget_script: Script = load(WIDGET_PATH) as Script
	var component_script: Script = load(COMPONENT_PATH) as Script
	var palette_script: Script = load(PALETTE_PATH) as Script
	var balance: Resource = load(BALANCE_PATH) as Resource
	_assert(widget_script != null, "Exposure widget script must compile.")
	_assert(component_script != null, "Exposure component script must compile.")
	_assert(palette_script != null, "HUD palette script must compile.")
	_assert(balance != null, "Exposure balance must load.")
	if widget_script == null or component_script == null \
			or palette_script == null or balance == null:
		_finish()
		return

	var widget: Control = widget_script.new() as Control
	root.add_child(widget)
	await process_frame
	await process_frame
	# The probe injects the component directly; prevent periodic PlayerAuthority
	# discovery from replacing it while fade tweens are being exercised.
	widget.set_process(false)

	var component: Node = component_script.new() as Node
	component.set("balance", balance)
	widget.set("_component", component)
	var exposure_handler: Callable = Callable(widget, "_on_exposure_changed")
	component.connect("exposure_changed", exposure_handler)
	_assert(
		component.is_connected("exposure_changed", exposure_handler),
		"Widget test seam must receive the component-local exposure signal.",
	)

	var wetness_group: Control = widget.get_node_or_null(
		"ExposureMetrics/WetnessMetric",
	) as Control
	var cold_group: Control = widget.get_node_or_null(
		"ExposureMetrics/ColdMetric",
	) as Control
	var wetness_icon: Control = widget.get_node_or_null(
		"ExposureMetrics/WetnessMetric/WetnessIcon",
	) as Control
	var cold_icon: Control = widget.get_node_or_null(
		"ExposureMetrics/ColdMetric/ColdIcon",
	) as Control
	var wetness_label: Label = widget.get_node_or_null(
		"ExposureMetrics/WetnessMetric/WetnessValue",
	) as Label
	var cold_label: Label = widget.get_node_or_null(
		"ExposureMetrics/ColdMetric/ColdValue",
	) as Label
	_assert(wetness_group != null, "Wetness metric group must exist.")
	_assert(cold_group != null, "Cold metric group must exist.")
	_assert(wetness_icon != null, "Wetness glyph must exist.")
	_assert(cold_icon != null, "Cold glyph must exist.")
	_assert(wetness_label != null, "Wetness numeric label must exist.")
	_assert(cold_label != null, "Cold numeric label must exist.")
	if wetness_group == null or cold_group == null \
			or wetness_icon == null or cold_icon == null \
			or wetness_label == null or cold_label == null:
		widget.queue_free()
		component.free()
		await process_frame
		_finish()
		return

	var palette: Dictionary = palette_script.get_script_constant_map()
	var neutral_color: Color = palette.get("TEXT_SECONDARY", Color.TRANSPARENT)
	var warning_color: Color = palette.get("CAUTION", Color.TRANSPARENT)
	var critical_color: Color = palette.get("CRITICAL", Color.TRANSPARENT)

	# Both values below their visibility thresholds: the quiet HUD stays absent.
	component.call("_set_state", 0.09, 0.11)
	await process_frame
	_assert(not widget.visible, "Below-threshold exposure row must stay hidden.")
	_assert(not wetness_group.visible, "Below-threshold wetness must stay hidden.")
	_assert(not cold_group.visible, "Below-threshold cold must stay hidden.")

	# A component signal, not an EventBus packet, reveals wetness on its own.
	component.call("_set_state", 0.26, 0.0)
	_assert(widget.visible, "Wet-only state must reveal the exposure row.")
	_assert(wetness_group.visible, "Wet-only state must reveal wetness.")
	_assert(not cold_group.visible, "Wet-only state must keep cold hidden.")
	_assert(wetness_label.text == "26%", "Wetness must use a numeric percent label.")
	_assert(
		_is_numeric_percent(wetness_label.text),
		"Wetness label must contain only digits and percent.",
	)
	await create_timer(FADE_SETTLE_SECONDS).timeout
	_assert(
		is_equal_approx(widget.modulate.a, 1.0),
		"Exposure row must complete its short reveal fade.",
	)

	# Independent thresholds permit both compact glyph/value groups at once.
	component.call("_set_state", 0.24, 0.30)
	await process_frame
	_assert(wetness_group.visible and cold_group.visible, "Both exposure metrics must coexist.")
	_assert(wetness_label.text == "24%", "Wetness rounding must remain deterministic.")
	_assert(cold_label.text == "30%", "Cold load must use a numeric percent label.")
	_assert(
		_is_numeric_percent(cold_label.text),
		"Cold label must contain only digits and percent.",
	)
	_assert(
		_colors_match(wetness_label.get_theme_color("font_color"), neutral_color)
		and _colors_match(cold_label.get_theme_color("font_color"), neutral_color),
		"Visible values below warning must use the quiet neutral palette.",
	)

	# Warning begins at CAUTION, then reaches CRITICAL at the authored threshold.
	component.call("_set_state", 0.45, 0.45)
	await process_frame
	_assert(
		_colors_match(wetness_label.get_theme_color("font_color"), warning_color)
		and _colors_match(cold_label.get_theme_color("font_color"), warning_color),
		"Warning thresholds must use HudPalette.CAUTION.",
	)
	_assert(
		_colors_match(wetness_icon.get("_color"), warning_color)
		and _colors_match(cold_icon.get("_color"), warning_color),
		"Warning glyphs and values must share the caution color.",
	)

	component.call("_set_state", 0.80, 0.80)
	await process_frame
	_assert(
		_colors_match(wetness_label.get_theme_color("font_color"), critical_color)
		and _colors_match(cold_label.get_theme_color("font_color"), critical_color),
		"Critical thresholds must use HudPalette.CRITICAL.",
	)
	_assert(
		_colors_match(wetness_icon.get("_color"), critical_color)
		and _colors_match(cold_icon.get("_color"), critical_color),
		"Critical glyphs and values must share the critical color.",
	)

	# Returning below both thresholds fades the whole row, then clears children.
	component.call("_set_state", 0.09, 0.11)
	_assert(widget.visible, "Hide transition must begin from the still-visible row.")
	_assert(not bool(widget.get("_target_visible")), "Hide fade target must switch immediately.")
	await create_timer(FADE_SETTLE_SECONDS).timeout
	_assert(not widget.visible, "Exposure row must hide after its fade completes.")
	_assert(is_zero_approx(widget.modulate.a), "Hidden exposure row must finish at zero alpha.")
	_assert(
		not wetness_group.visible and not cold_group.visible,
		"Hidden exposure row must clear both metric groups.",
	)

	widget.queue_free()
	component.free()
	await process_frame
	_finish()


func _check_static_contract(
		widget_source: String,
		icons_source: String,
		manager_source: String,
) -> void:
	_assert(
		widget_source.contains(
			"_make_icon(\"WetnessIcon\", HudIcons.Id.WETNESS)",
		)
		and widget_source.contains(
			"_make_icon(\"ColdIcon\", HudIcons.Id.COLD)",
		),
		"Exposure metrics must wire dedicated WETNESS and COLD glyphs.",
	)
	_assert(
		icons_source.contains("WETNESS,")
		and icons_source.contains("COLD,")
		and icons_source.contains("_draw_wetness(canvas, rect, color, width)")
		and icons_source.contains("_draw_cold(canvas, rect, color, width)"),
		"WETNESS and COLD glyphs must remain code-drawn by HudIcons.",
	)
	_assert(
		widget_source.contains(
			"_component.exposure_changed.connect(_on_exposure_changed)",
		)
		and not widget_source.contains("EventBus"),
		"Exposure HUD must subscribe directly to its player component, never EventBus.",
	)
	_assert(
		not widget_source.contains("Localization.")
		and not widget_source.contains("ColorRect.new()")
		and not widget_source.contains("PanelContainer.new()")
		and not widget_source.contains("ProgressBar.new()")
		and not widget_source.contains("TextureProgressBar.new()")
		and not widget_source.contains("HudAlarm")
		and not widget_source.contains("AlarmVignette"),
		"Exposure HUD must add no localization label, scrim, meter, or alarm surface.",
	)
	_assert(
		widget_source.contains("label.text = \"%d%%\"")
		and widget_source.contains("create_tween()")
		and widget_source.contains("_fade_tween.tween_callback(_finish_hide)"),
		"Exposure HUD must use numeric percent labels and a bounded fade hide.",
	)

	var oxygen_index: int = manager_source.find(
		"_top_left.add_child(HudOxygenWidget.new())",
	)
	var hp_index: int = manager_source.find(
		"_top_left.add_child(HudHpWidget.new())",
		oxygen_index,
	)
	var exposure_index: int = manager_source.find(
		"_top_left.add_child(HudExposureWidget.new())",
		hp_index,
	)
	var rule_index: int = manager_source.find(
		"_top_left.add_child(_make_rule(HudRule.Fade.TO_RIGHT))",
		exposure_index,
	)
	var status_index: int = manager_source.find(
		"_top_left.add_child(HudStatusWidget.new())",
		rule_index,
	)
	_assert(
		oxygen_index >= 0
		and oxygen_index < hp_index
		and hp_index < exposure_index
		and exposure_index < rule_index
		and rule_index < status_index,
		"Survival plate order must be oxygen, HP, exposure, rule, status.",
	)


func _is_numeric_percent(value: String) -> bool:
	if not value.ends_with("%"):
		return false
	var digits: String = value.trim_suffix("%")
	return not digits.is_empty() and digits.is_valid_int()


func _colors_match(actual: Color, expected: Color) -> bool:
	return actual.is_equal_approx(expected)


func _finish() -> void:
	if _failed:
		quit(1)
		return
	print("hud_exposure_probe: OK")
	quit(0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	_failed = true
