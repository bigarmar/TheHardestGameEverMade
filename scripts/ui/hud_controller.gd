extends CanvasLayer
class_name HUDController

const PortraitScript = preload("res://scripts/ui/portrait_controller.gd")
const WeaponViewmodelScript = preload("res://scripts/ui/weapon_viewmodel.gd")

var time_label: Label
var ammo_label: Label
var enemy_label: Label
var accuracy_label: Label
var portrait: PortraitController
var objective_panel: PanelContainer
var objective_label: Label
var notification_host: VBoxContainer
var weapon_viewmodel


func setup(difficulty: String) -> void:
	layer = 20
	_build_top_bar(difficulty)
	_build_bottom_bar()
	_build_crosshair()
	_build_weapon_viewmodel()
	_build_objective()


func _build_top_bar(difficulty: String) -> void:
	var top := PanelContainer.new()
	top.position = Vector2(22, 18)
	top.size = Vector2(1236, 64)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.05, 0.93), Color("#2d7f9d"), 2, 5))
	add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	top.add_child(row)
	row.add_child(_stat_label("HEALTH  100", Color("#70f0d0"), 18))
	row.add_child(_divider())
	row.add_child(_stat_label("ARMOR  100", Color("#6bb8ff"), 18))
	row.add_child(_divider())
	ammo_label = _stat_label("AMMUNITION  999", Color("#ffd55e"), 18)
	row.add_child(ammo_label)
	row.add_child(_divider())
	enemy_label = _stat_label("ENEMIES REMAINING  1", Color("#ff6a58"), 18)
	row.add_child(enemy_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var diff := _stat_label(difficulty.to_upper(), Color("#ff4438") if difficulty == "Impossible" else Color("#c8d7e3"), 16)
	row.add_child(diff)


func _build_bottom_bar() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(22, 558)
	panel.size = Vector2(1236, 142)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.045, 0.96), Color("#8b2822"), 2, 4))
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(184, 124)
	portrait_frame.add_theme_stylebox_override("panel", _panel_style(Color("#080c10"), Color("#ee3e2f"), 3, 3))
	row.add_child(portrait_frame)
	portrait = PortraitScript.new()
	portrait.custom_minimum_size = Vector2(176, 116)
	portrait_frame.add_child(portrait)

	var mission_box := VBoxContainer.new()
	mission_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(mission_box)
	var mission := _stat_label("FINAL CAMPAIGN // AUTHORIZATION OMEGA", Color("#a9bac7"), 13)
	mission_box.add_child(mission)
	var objective := _stat_label("PRIMARY OBJECTIVE:  SHOOT THE TARGET", Color.WHITE, 23)
	mission_box.add_child(objective)
	accuracy_label = _stat_label("SHOTS 0  //  ACCURACY 100.0%", Color("#768d9d"), 15)
	mission_box.add_child(accuracy_label)

	var timer_box := VBoxContainer.new()
	timer_box.custom_minimum_size.x = 220
	row.add_child(timer_box)
	var timer_heading := _stat_label("CAMPAIGN TIMER", Color("#ff624d"), 13)
	timer_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_box.add_child(timer_heading)
	time_label = _stat_label("00.00", Color.WHITE, 38)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	timer_box.add_child(time_label)


func _build_crosshair() -> void:
	var center := Control.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.position = Vector2(-18, -18)
	center.size = Vector2(36, 36)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.z_index = 20
	for rect_data in [Rect2(16, 2, 4, 10), Rect2(16, 24, 4, 10), Rect2(2, 16, 10, 4), Rect2(24, 16, 10, 4)]:
		var arm := ColorRect.new()
		arm.position = rect_data.position
		arm.size = rect_data.size
		arm.color = Color(0.75, 0.95, 1.0, 0.88)
		center.add_child(arm)


func _build_weapon_viewmodel() -> void:
	weapon_viewmodel = WeaponViewmodelScript.new()
	weapon_viewmodel.name = "WeaponViewmodel"
	add_child(weapon_viewmodel)


func _build_objective() -> void:
	objective_panel = PanelContainer.new()
	objective_panel.position = Vector2(390, 170)
	objective_panel.size = Vector2(500, 164)
	objective_panel.modulate.a = 0.0
	objective_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.055, 0.94), Color("#ff4938"), 3, 5))
	add_child(objective_panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	objective_panel.add_child(box)
	var final_label := _stat_label("FINAL CAMPAIGN", Color("#ff5444"), 16)
	final_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(final_label)
	objective_label = _stat_label("PRIMARY OBJECTIVE\nSHOOT THE TARGET", Color.WHITE, 28)
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(objective_label)


func reveal_objective() -> void:
	objective_panel.modulate.a = 0.0
	objective_panel.scale = Vector2(0.84, 0.84)
	objective_panel.pivot_offset = objective_panel.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(objective_panel, "modulate:a", 1.0, 0.32)
	tween.tween_property(objective_panel, "scale", Vector2.ONE, 0.38)
	var hide_tween := create_tween()
	hide_tween.tween_interval(2.25)
	hide_tween.tween_property(objective_panel, "modulate:a", 0.0, 0.45)


func update_readout(elapsed: float, shots: int, misses: int) -> void:
	if time_label != null:
		time_label.text = "%05.2f" % elapsed
	var accuracy := 100.0 if shots == 0 else (float(shots - misses) / shots) * 100.0
	if accuracy_label != null:
		accuracy_label.text = "SHOTS %d  //  MISSES %d  //  ACCURACY %.1f%%" % [shots, misses, accuracy]


func mark_enemy_defeated() -> void:
	enemy_label.text = "ENEMIES REMAINING  0"
	enemy_label.modulate = Color("#70f0a6")


func set_portrait(expression: String) -> void:
	if portrait != null:
		portrait.set_expression(expression)


func flash_crosshair_success() -> void:
	var flash := Label.new()
	flash.text = "✦"
	flash.position = Vector2(620, 325)
	flash.add_theme_font_size_override("font_size", 42)
	flash.add_theme_color_override("font_color", Color("#ffdf58"))
	add_child(flash)
	var tween := create_tween().set_parallel(true)
	tween.tween_property(flash, "modulate:a", 0.0, 0.45)
	tween.tween_property(flash, "scale", Vector2(2.0, 2.0), 0.45)
	tween.tween_callback(flash.queue_free).set_delay(0.46)


func play_weapon_fire() -> void:
	if weapon_viewmodel != null:
		weapon_viewmodel.fire()


func _stat_label(text_value: String, color: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", font_size)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _divider() -> ColorRect:
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(2, 36)
	divider.color = Color("#1f4255")
	return divider


func _panel_style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style
