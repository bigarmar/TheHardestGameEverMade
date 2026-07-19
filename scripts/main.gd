extends Node

const SaveManagerScript = preload("res://scripts/systems/save_manager.gd")
const AudioManagerScript = preload("res://scripts/systems/audio_manager.gd")
const AchievementManagerScript = preload("res://scripts/systems/achievement_manager.gd")
const TransitionManagerScript = preload("res://scripts/systems/transition_manager.gd")
const PlayerScript = preload("res://scripts/gameplay/player_controller.gd")
const TargetScript = preload("res://scripts/gameplay/target_controller.gd")
const HUDScript = preload("res://scripts/ui/hud_controller.gd")
const PortraitScript = preload("res://scripts/ui/portrait_controller.gd")
const CommandBackdropScript = preload("res://scripts/ui/command_backdrop.gd")
const CommandButtonScript = preload("res://scripts/ui/command_button.gd")
const CommandTheme = preload("res://assets/ui/command_theme.tres")

const DIFFICULTIES := {
	"Easy": "Suitable for players who value survival.",
	"Normal": "The intended experience.",
	"Hard": "Mistakes will not be forgiven.",
	"Expert": "Designed for elite players.",
	"Impossible": "Completion is considered statistically unlikely."
}

const LOADING_TIPS := [
	"Conserve your ammunition.",
	"Study the target's movement patterns.",
	"Hesitation can be fatal.",
	"The target knows you are coming.",
	"Remember your training.",
	"There is no shame in returning to Easy Mode.",
	"Survival is never guaranteed."
]

const LOADING_PHASES := [
	"Preparing battlefield.",
	"Evaluating player survival probability.",
	"Calculating enemy intelligence.",
	"Securing final authorization.",
	"Accepting the inevitable."
]

const DIFFICULTY_REDUCER_NOTIFICATION := "Difficulty reduced from Impossible to Impossible."
const EASTER_NOTIFICATION_WIDTH := 500.0
const EASTER_NOTIFICATION_RIGHT_MARGIN := 24.0

var save_manager
var audio_manager
var achievement_manager
var transition_manager
var notification_layer: CanvasLayer
var notification_stack: VBoxContainer

var ui_root: Control
var world_root: Node3D
var hud
var player
var target
var pause_layer: CanvasLayer
var credits_tween: Tween

var state := "boot"
var selected_difficulty := "Normal"
var campaign_started_msec := 0
var campaign_elapsed := 0.0
var session_shots := 0
var session_hits := 0
var session_misses := 0
var pacifist_awarded := false
var autosave_clock := 0.0
var red_lights: Array = []
var ceiling_lights: Array = []
var disabled_ceiling_lights: Dictionary = {}
var combat_environment: Environment
var combat_key_light: DirectionalLight3D
var behind_duck: Node3D
var duck_discovered := false
var death_layer: CanvasLayer
var settings_from_pause := false
var ui_action_lock := false
var victory_music_active := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	randomize()
	save_manager = SaveManagerScript.new()
	save_manager.name = "SaveManager"
	add_child(save_manager)
	audio_manager = AudioManagerScript.new()
	audio_manager.name = "AudioManager"
	add_child(audio_manager)
	achievement_manager = AchievementManagerScript.new()
	achievement_manager.name = "AchievementManager"
	add_child(achievement_manager)
	transition_manager = TransitionManagerScript.new()
	transition_manager.name = "SceneTransitionManager"
	add_child(transition_manager)
	achievement_manager.setup(save_manager, _show_achievement_notification)
	audio_manager.set_volumes(
		float(save_manager.get_setting("master_volume", 0.85)),
		float(save_manager.get_setting("music_volume", 0.60)),
		float(save_manager.get_setting("sfx_volume", 0.85))
	)
	_build_notification_layer()
	_apply_saved_display_settings()
	call_deferred("_opening_sequence")


func _process(delta: float) -> void:
	if not get_tree().paused:
		if state == "gameplay":
			campaign_elapsed = max(0.0, (Time.get_ticks_msec() - campaign_started_msec) / 1000.0)
			if hud != null:
				hud.update_readout(campaign_elapsed, session_shots, session_misses)
			if session_shots == 0 and campaign_elapsed >= 10.0 and hud != null:
				hud.set_portrait("impatient")
			if session_shots == 0 and campaign_elapsed >= 30.0 and not pacifist_awarded:
				pacifist_awarded = true
				achievement_manager.on_pacifist()
			_check_behind_duck_discovery()
			save_manager.add_time(delta, 0.0)
		else:
			save_manager.add_time(0.0, delta)
		autosave_clock += delta
		if autosave_clock >= 10.0:
			autosave_clock = 0.0
			save_manager.save_data()
	for index in red_lights.size():
		var light = red_lights[index]
		if is_instance_valid(light):
			light.light_energy = 2.7 + sin(Time.get_ticks_msec() * 0.006 + index * 1.7) * 1.35


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_command_button_hover(event.position)
		return
	if not (event is InputEventMouseButton):
		return
	_update_command_button_hover(event.position)
	if not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		for node in get_tree().get_nodes_in_group("command_buttons"):
			if is_instance_valid(node) and node.has_method("set_pointer_pressed"):
				node.set_pointer_pressed(false)
		return
	var command_buttons := get_tree().get_nodes_in_group("command_buttons")
	for index in range(command_buttons.size() - 1, -1, -1):
		var button := command_buttons[index] as Button
		if is_instance_valid(button) and not button.disabled and button.is_visible_in_tree() and button.get_global_rect().has_point(event.position):
			if button.has_method("set_pointer_pressed"):
				button.set_pointer_pressed(true)
			button.grab_focus()
			button.emit_signal("pressed")
			get_viewport().set_input_as_handled()
			return


func _update_command_button_hover(pointer_position: Vector2) -> void:
	for node in get_tree().get_nodes_in_group("command_buttons"):
		var button := node as Button
		if not is_instance_valid(button) or not button.is_visible_in_tree() or not button.has_method("set_pointer_hovered"):
			continue
		var entered := bool(button.set_pointer_hovered(button.get_global_rect().has_point(pointer_position)))
		if entered:
			_on_menu_hover()


func _exit_tree() -> void:
	if save_manager != null:
		save_manager.save_data()


func _build_notification_layer() -> void:
	notification_layer = CanvasLayer.new()
	notification_layer.layer = 110
	notification_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(notification_layer)
	notification_stack = VBoxContainer.new()
	notification_stack.size = Vector2(EASTER_NOTIFICATION_WIDTH, 280)
	notification_stack.add_theme_constant_override("separation", 10)
	notification_layer.add_child(notification_stack)
	_layout_notification_stack()
	get_viewport().size_changed.connect(_layout_notification_stack)


func _layout_notification_stack() -> void:
	if not is_instance_valid(notification_stack):
		return
	var viewport_width := get_viewport().get_visible_rect().size.x
	notification_stack.position = Vector2(maxf(12.0, viewport_width - EASTER_NOTIFICATION_WIDTH - EASTER_NOTIFICATION_RIGHT_MARGIN), 24.0)


func _opening_sequence() -> void:
	state = "opening"
	_clear_ui()
	var background := _add_background(Color("#02050a"), Color("#0a1a24"))
	var line := ColorRect.new()
	line.position = Vector2(370, 350)
	line.size = Vector2(540, 2)
	line.color = Color("#d83c2e")
	background.add_child(line)
	var label := _label("FINAL AUTHORIZATION GRANTED", 23, Color("#dbe9ef"), HORIZONTAL_ALIGNMENT_CENTER)
	label.position = Vector2(290, 286)
	label.size = Vector2(700, 48)
	label.modulate.a = 0.0
	background.add_child(label)
	var sub := _label("A CAMPAIGN OF UNPRECEDENTED CONSEQUENCE", 12, Color("#718897"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(290, 364)
	sub.size = Vector2(700, 28)
	sub.modulate.a = 0.0
	background.add_child(sub)
	var tween := create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.42)
	tween.parallel().tween_property(sub, "modulate:a", 1.0, 0.68)
	tween.tween_interval(0.62)
	tween.tween_property(label, "modulate:a", 0.0, 0.24)
	await tween.finished
	_show_title()


func _show_title() -> void:
	_destroy_world()
	state = "menu"
	victory_music_active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_clear_ui()
	audio_manager.play_ambience(false)
	audio_manager.play_music("menu")
	var bg := _add_background(Color("#02070d"), Color("#102734"))
	_add_scanlines(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_theme_constant_override("margin_left", 58)
	margin.add_theme_constant_override("margin_right", 58)
	margin.add_theme_constant_override("margin_top", 52)
	margin.add_theme_constant_override("margin_bottom", 46)
	bg.add_child(margin)
	var composition := HBoxContainer.new()
	composition.mouse_filter = Control.MOUSE_FILTER_PASS
	composition.add_theme_constant_override("separation", 54)
	margin.add_child(composition)

	var left_column := VBoxContainer.new()
	left_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_column.add_theme_constant_override("separation", 10)
	composition.add_child(left_column)
	var clearance := _label("OMEGA CLEARANCE // FINAL CAMPAIGN", 15, Color("#ff5143"))
	left_column.add_child(clearance)
	var title_gap := Control.new()
	title_gap.custom_minimum_size.y = 22
	left_column.add_child(title_gap)
	var title := _label("THE HARDEST GAME\nEVER MADE", 60, Color("#edf3f5"))
	title.custom_minimum_size.y = 132
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	left_column.add_child(title)
	var subtitle := _label("FEW BEGIN. FEWER FINISH.", 21, Color("#8db9cd"))
	left_column.add_child(subtitle)
	var red_rule := _rule(Color("#ed4035"), 3)
	red_rule.custom_minimum_size.x = 0
	left_column.add_child(red_rule)
	var intel_gap := Control.new()
	intel_gap.custom_minimum_size.y = 20
	left_column.add_child(intel_gap)
	var intel := PanelContainer.new()
	intel.custom_minimum_size.y = 228
	intel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	intel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.055, 0.075, 0.88), Color("#3c7890"), 2, 5))
	left_column.add_child(intel)
	var intel_box := VBoxContainer.new()
	intel_box.add_theme_constant_override("separation", 8)
	intel.add_child(intel_box)
	intel_box.add_child(_label("MISSION INTELLIGENCE", 19, Color("#76d8ec")))
	intel_box.add_child(_rule(Color("#28566b"), 1))
	intel_box.add_child(_label("THREAT LEVEL", 13, Color("#78919e")))
	intel_box.add_child(_label("EXTREME", 42, Color("#f04437")))
	intel_box.add_child(_label("SURVIVAL PROBABILITY: CLASSIFIED", 16, Color("#dce8ec")))
	intel_box.add_child(_label("ONE TARGET REMAINS. FAILURE IS NOT AN OPTION.", 13, Color("#90b4c2")))
	intel_box.add_child(_label("LIVE TACTICAL FEED // WORLD GRID ONLINE", 11, Color("#5d8b9d")))

	var terminal := PanelContainer.new()
	terminal.mouse_filter = Control.MOUSE_FILTER_PASS
	terminal.custom_minimum_size = Vector2(360, 0)
	terminal.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terminal.add_theme_stylebox_override("panel", _panel_style(Color(0.012, 0.034, 0.052, 0.94), Color("#426f85"), 2, 6))
	composition.add_child(terminal)
	var terminal_box := VBoxContainer.new()
	terminal_box.mouse_filter = Control.MOUSE_FILTER_PASS
	terminal_box.alignment = BoxContainer.ALIGNMENT_CENTER
	terminal_box.add_theme_constant_override("separation", 11)
	terminal.add_child(terminal_box)
	var terminal_emblem := _label("\u03a9", 32, Color("#68b9d2"), HORIZONTAL_ALIGNMENT_CENTER)
	terminal_box.add_child(terminal_emblem)
	terminal_box.add_child(_label("COMMAND TERMINAL", 18, Color("#91cbe0"), HORIZONTAL_ALIGNMENT_CENTER))
	terminal_box.add_child(_rule(Color("#315d73"), 1))
	var campaign := _menu_button("CAMPAIGN", _show_campaign_briefing)
	campaign.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(campaign)
	var achievements := _menu_button("ACHIEVEMENTS", _show_achievements)
	achievements.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(achievements)
	var statistics := _menu_button("STATISTICS", _show_statistics)
	statistics.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(statistics)
	var credits := _menu_button("CREDITS", _show_credits)
	credits.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(credits)
	var settings := _menu_button("SETTINGS", _show_settings)
	settings.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(settings)
	var quit := _menu_button("QUIT", _quit_game)
	quit.custom_minimum_size = Vector2(0, 58)
	terminal_box.add_child(quit)
	var build_readout := _label("SYSTEMS NOMINAL // LOCAL SAVE ACTIVE", 10, Color("#557d8e"), HORIZONTAL_ALIGNMENT_CENTER)
	terminal_box.add_child(build_readout)
	transition_manager.fade_in(0.45)


func _show_campaign_briefing() -> void:
	state = "briefing"
	_clear_ui()
	audio_manager.play_sfx("menu_confirm")
	var bg := _add_background(Color("#03070b"), Color("#16242a"))
	_add_scanlines(bg)
	var card := PanelContainer.new()
	card.position = Vector2(170, 82)
	card.size = Vector2(940, 555)
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.04, 0.97), Color("#8e2924"), 2, 5))
	bg.add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	card.add_child(box)
	var kicker := _label("TOP SECRET // EYES ONLY", 13, Color("#f14b3d"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(kicker)
	var heading := _label("FINAL CAMPAIGN", 48, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(heading)
	box.add_child(_rule(Color("#a62d27"), 4))
	var copy := _label("The world has waited long enough.\n\nOne target remains.\n\nFailure is not an option.", 23, Color("#c5d1d6"), HORIZONTAL_ALIGNMENT_CENTER)
	copy.custom_minimum_size.y = 220
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(copy)
	box.add_child(_menu_button("BEGIN CAMPAIGN", _show_difficulty, true))
	box.add_child(_menu_button("RETURN TO TITLE", _show_title))


func _show_difficulty() -> void:
	state = "difficulty"
	_clear_ui()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := _add_background(Color("#02060b"), Color("#121d27"))
	_add_scanlines(bg)
	var title := _label("SELECT DIFFICULTY", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.position = Vector2(240, 42)
	title.size = Vector2(800, 58)
	bg.add_child(title)
	var sub := _label("Choose carefully. The campaign cannot be underestimated.", 15, Color("#8397a4"), HORIZONTAL_ALIGNMENT_CENTER)
	sub.position = Vector2(240, 100)
	sub.size = Vector2(800, 30)
	bg.add_child(sub)
	var list := VBoxContainer.new()
	list.position = Vector2(245, 148)
	list.size = Vector2(790, 460)
	list.add_theme_constant_override("separation", 9)
	bg.add_child(list)
	for difficulty in DIFFICULTIES:
		var difficulty_name: String = str(difficulty)
		var impossible: bool = difficulty_name == "Impossible"
		var button := CommandButtonScript.new()
		button.text = "%s\n%s" % [difficulty_name.to_upper(), DIFFICULTIES[difficulty_name]]
		button.custom_minimum_size = Vector2(790, 76)
		button.add_theme_font_size_override("font_size", 17 if not impossible else 19)
		button.add_theme_color_override("font_color", Color("#f5f7f8"))
		button.add_theme_color_override("font_hover_color", Color.WHITE)
		button.set_command_styles(
			_panel_style(Color(0.035, 0.055, 0.068, 0.96) if not impossible else Color(0.16, 0.015, 0.012, 0.97), Color("#315263") if not impossible else Color("#ff3829"), 2, 3),
			_red_hover_style(),
			_panel_style(Color(0.22, 0.01, 0.008, 1.0), Color("#ff2d22"), 3, 3),
			_focus_style()
		)
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_on_difficulty_selected.bind(difficulty_name))
		button.mouse_entered.connect(_on_menu_hover)
		button.add_to_group("command_buttons")
		list.add_child(button)
	var back := _menu_button("BACK", _show_campaign_briefing)
	back.position = Vector2(35, 650)
	back.size = Vector2(180, 46)
	bg.add_child(back)


func _on_difficulty_selected(difficulty: String) -> void:
	selected_difficulty = difficulty
	audio_manager.play_sfx("menu_confirm")
	if difficulty == "Impossible":
		_show_impossible_warning()
	else:
		_start_loading(difficulty)


func _show_impossible_warning() -> void:
	state = "impossible_warning"
	_clear_ui()
	audio_manager.play_sfx("warning")
	var bg := _add_background(Color("#120000"), Color("#380503"))
	_add_scanlines(bg)
	for x in range(-100, 1400, 120):
		var stripe := ColorRect.new()
		stripe.position = Vector2(x, 0)
		stripe.size = Vector2(34, 720)
		stripe.rotation = deg_to_rad(18.0)
		stripe.color = Color(0.30, 0.02, 0.015, 0.34)
		bg.add_child(stripe)
	var panel := PanelContainer.new()
	panel.position = Vector2(260, 105)
	panel.size = Vector2(760, 505)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.08, 0.005, 0.005, 0.97), Color("#ff3327"), 4, 3))
	bg.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 15)
	panel.add_child(box)
	var warning := _label("WARNING", 55, Color("#ff3327"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(warning)
	box.add_child(_rule(Color("#ff3327"), 5))
	var copy := _label("Impossible Mode is intended only for the most experienced players.\n\nSome players have required several seconds to complete it.\n\nDo you accept the consequences?", 20, Color("#f1dddd"), HORIZONTAL_ALIGNMENT_CENTER)
	copy.custom_minimum_size.y = 220
	copy.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(copy)
	box.add_child(_menu_button("I AM READY", _accept_impossible, true, true))
	box.add_child(_menu_button("I VALUE MY LIFE", _value_life))


func _accept_impossible() -> void:
	_start_loading("Impossible")


func _value_life() -> void:
	save_manager.increment_stat("valued_life_count", 1)
	_show_difficulty()


func _start_loading(difficulty: String) -> void:
	selected_difficulty = difficulty
	save_manager.record_difficulty_selection(difficulty)
	call_deferred("_loading_sequence")


func _loading_sequence() -> void:
	_destroy_world()
	state = "loading"
	_clear_ui()
	var bg := _add_background(Color("#02070c"), Color("#0b1c25"))
	_add_scanlines(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 180)
	margin.add_theme_constant_override("margin_right", 180)
	margin.add_theme_constant_override("margin_top", 80)
	margin.add_theme_constant_override("margin_bottom", 82)
	bg.add_child(margin)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.045, 0.062, 0.95), Color("#3e7890"), 2, 6))
	margin.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("MISSION DESIGNATION // FINAL TARGET", 13, Color("#73cce4"), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("DEPLOYMENT IN PROGRESS", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var danger := _label("THREAT LEVEL: %s" % selected_difficulty.to_upper(), 15, Color("#ff5042") if selected_difficulty == "Impossible" else Color("#7ad7e8"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(danger)
	box.add_child(_rule(Color("#315f73"), 1))
	var phase_label := _label(LOADING_PHASES[0], 20, Color("#d1e1e6"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(phase_label)
	var progress := ProgressBar.new()
	progress.custom_minimum_size = Vector2(0, 28)
	progress.min_value = 0
	progress.max_value = 100
	progress.show_percentage = false
	progress.add_theme_stylebox_override("background", _panel_style(Color("#050e14"), Color("#315d70"), 2, 3))
	progress.add_theme_stylebox_override("fill", _panel_style(Color("#cf392e"), Color("#ff7165"), 1, 3))
	box.add_child(progress)
	var percent := _label("0%", 42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(percent)
	var indicator := _label("[ SCANNING TACTICAL GRID ]", 12, Color("#76cde0"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(indicator)
	var tip := _label("CONSERVE YOUR AMMUNITION.", 15, Color("#90b4c2"), HORIZONTAL_ALIGNMENT_CENTER)
	tip.custom_minimum_size.y = 42
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(tip)
	# Bind this infinite pulse to the loading indicator so it is discarded with the UI.
	var pulse := indicator.create_tween()
	pulse.tween_property(indicator, "modulate:a", 0.35, 0.45)
	pulse.tween_property(indicator, "modulate:a", 1.0, 0.45)
	pulse.set_loops()
	for value in range(101):
		if state != "loading":
			return
		progress.value = value
		percent.text = "%d%%" % value
		if value % 20 == 0:
			var phase_index := mini(int(value / 20), LOADING_PHASES.size() - 1)
			phase_label.text = LOADING_PHASES[phase_index]
			tip.text = LOADING_TIPS[int(value / 20) % LOADING_TIPS.size()].to_upper()
			indicator.text = "[ %s // GRID SCAN %02d ]" % ["VERIFYING SYSTEMS" if value < 60 else "FINALIZING DEPLOYMENT", value]
			audio_manager.play_sfx("loading")
		await get_tree().create_timer(0.035).timeout
	_begin_gameplay()


func _begin_gameplay() -> void:
	state = "deploying"
	victory_music_active = false
	_clear_ui()
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_game_world()
	hud = HUDScript.new()
	hud.name = "HUDController"
	add_child(hud)
	hud.setup(selected_difficulty)
	player.mouse_sensitivity = float(save_manager.get_setting("mouse_sensitivity", 0.22))
	player.set_controls_enabled(false)
	audio_manager.play_music("battle")
	audio_manager.play_ambience(true)
	transition_manager.fade_in(0.35)
	call_deferred("_countdown_sequence")


func _countdown_sequence() -> void:
	var overlay := PanelContainer.new()
	overlay.position = Vector2(480, 205)
	overlay.size = Vector2(320, 230)
	overlay.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.025, 0.035, 0.90), Color("#e84134"), 3, 4))
	ui_root.add_child(overlay)
	var count := _label("3", 96, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	overlay.add_child(count)
	for number in [3, 2, 1]:
		count.text = str(number)
		count.scale = Vector2(1.25, 1.25)
		count.pivot_offset = overlay.size * 0.5
		audio_manager.play_sfx("countdown")
		var tween := create_tween()
		tween.tween_property(count, "scale", Vector2.ONE, 0.25)
		await get_tree().create_timer(0.68).timeout
	count.text = "CAMPAIGN\nINITIATED"
	count.add_theme_font_size_override("font_size", 30)
	audio_manager.play_sfx("menu_confirm")
	await get_tree().create_timer(0.55).timeout
	overlay.queue_free()
	session_shots = 0
	session_hits = 0
	session_misses = 0
	pacifist_awarded = false
	campaign_elapsed = 0.0
	campaign_started_msec = Time.get_ticks_msec()
	state = "gameplay"
	player.set_controls_enabled(true)
	hud.reveal_objective()


func _build_game_world() -> void:
	world_root = Node3D.new()
	world_root.name = "FinalCombatChamber"
	add_child(world_root)
	red_lights.clear()
	ceiling_lights.clear()
	disabled_ceiling_lights.clear()
	behind_duck = null
	duck_discovered = false

	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#03070a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#183040")
	environment.ambient_light_energy = 0.42
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.tonemap_exposure = 1.18
	environment.glow_enabled = true
	environment.glow_intensity = 0.85
	environment.fog_enabled = true
	environment.fog_light_color = Color("#18313a")
	environment.fog_light_energy = 0.42
	environment.fog_density = 0.012
	environment.fog_height = 0.0
	environment.fog_height_density = 0.12
	environment.volumetric_fog_enabled = true
	environment.volumetric_fog_density = 0.018
	environment.volumetric_fog_length = 22.0
	world_environment.environment = environment
	world_root.add_child(world_environment)
	combat_environment = environment

	var floor_mat := _material_3d(Color("#20292e"), 0.78, 0.24)
	var floor_alt := _material_3d(Color("#11181d"), 0.72, 0.34)
	var wall_mat := _material_3d(Color("#22292d"), 0.68, 0.42)
	var wall_dark := _material_3d(Color("#0b1014"), 0.86, 0.27)
	var cyan_emission := _emissive_3d(Color("#2fc0d4"), 2.6)
	var red_emission := _emissive_3d(Color("#db2d24"), 3.8)
	var yellow_mat := _emissive_3d(Color("#e6a92b"), 1.2)

	_make_static_box(world_root, Vector3(0, -0.25, 0), Vector3(14, 0.5, 18), floor_mat)
	_make_static_box(world_root, Vector3(-7.2, 2.55, 0), Vector3(0.42, 5.6, 18.4), wall_mat)
	_make_static_box(world_root, Vector3(7.2, 2.55, 0), Vector3(0.42, 5.6, 18.4), wall_mat)
	_make_static_box(world_root, Vector3(0, 2.55, -9.2), Vector3(14.4, 5.6, 0.42), wall_mat)
	_make_static_box(world_root, Vector3(0, 2.55, 9.2), Vector3(14.4, 5.6, 0.42), wall_mat)

	for x in range(-3, 4):
		for z in range(-4, 5):
			var panel_mat = floor_alt if (x + z) % 2 == 0 else floor_mat
			_make_visual_box(world_root, Vector3(x * 1.95, 0.015, z * 1.95), Vector3(1.82, 0.035, 1.82), panel_mat)

	for x in [-5.4, -2.7, 0.0, 2.7, 5.4]:
		_make_visual_box(world_root, Vector3(x, 5.15, 0), Vector3(0.22, 0.22, 18.0), wall_dark)
		for z in [-6.6, -2.2, 2.2, 6.6]:
			_make_visual_box(world_root, Vector3(x, 4.98, z), Vector3(0.12, 0.12, 2.7), cyan_emission)

	for z in [-7.6, -3.8, 0.0, 3.8, 7.6]:
		_make_visual_box(world_root, Vector3(-7.0, 2.7, z), Vector3(0.10, 3.6, 1.35), wall_dark)
		_make_visual_box(world_root, Vector3(7.0, 2.7, z), Vector3(0.10, 3.6, 1.35), wall_dark)

	for side in [-1.0, 1.0]:
		_make_visual_box(world_root, Vector3(side * 2.4, 1.85, -8.9), Vector3(2.0, 3.5, 0.22), wall_dark)
		_make_visual_box(world_root, Vector3(side * 3.45, 1.85, -8.66), Vector3(0.10, 2.8, 0.06), red_emission)
	_make_visual_box(world_root, Vector3(0, 4.75, -8.7), Vector3(7.2, 0.34, 0.20), red_emission)

	for i in range(-6, 7):
		if i % 2 == 0:
			_make_visual_box(world_root, Vector3(i * 0.34, 0.045, -3.4), Vector3(0.27, 0.04, 0.92), yellow_mat)
		else:
			_make_visual_box(world_root, Vector3(i * 0.34, 0.045, -3.4), Vector3(0.27, 0.04, 0.92), wall_dark)

	var platform := MeshInstance3D.new()
	var platform_mesh := CylinderMesh.new()
	platform_mesh.top_radius = 2.25
	platform_mesh.bottom_radius = 2.55
	platform_mesh.height = 0.42
	platform.mesh = platform_mesh
	platform.position = Vector3(0, 0.16, -5.9)
	platform.material_override = wall_mat
	world_root.add_child(platform)
	var platform_ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 2.18
	ring_mesh.outer_radius = 2.28
	platform_ring.mesh = ring_mesh
	platform_ring.position = Vector3(0, 0.39, -5.9)
	platform_ring.material_override = red_emission
	world_root.add_child(platform_ring)

	var rear_door := _make_visual_box(world_root, Vector3(0, 2.0, 9.0), Vector3(4.6, 4.0, 0.34), wall_dark)
	_make_visual_box(rear_door, Vector3(-1.8, 0, -0.20), Vector3(0.08, 3.5, 0.06), cyan_emission)
	_make_visual_box(rear_door, Vector3(1.8, 0, -0.20), Vector3(0.08, 3.5, 0.06), cyan_emission)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-58, -28, 0)
	key_light.light_color = Color("#b8d8e9")
	key_light.light_energy = 0.75
	key_light.shadow_enabled = true
	world_root.add_child(key_light)
	combat_key_light = key_light
	for light_data in [
		[Vector3(-5.8, 3.8, -5.4), Color("#ff2e22")],
		[Vector3(5.8, 3.8, -5.4), Color("#ff2e22")],
		[Vector3(-5.8, 3.8, 4.8), Color("#20a8cf")],
		[Vector3(5.8, 3.8, 4.8), Color("#20a8cf")]
	]:
		var light := OmniLight3D.new()
		light.position = light_data[0]
		light.light_color = light_data[1]
		light.light_energy = 3.0
		light.omni_range = 8.0
		light.shadow_enabled = true
		world_root.add_child(light)
		red_lights.append(light)

	# These are physical facility signs rather than camera-facing floating labels.
	_make_framed_surface(world_root, _make_facility_sign_texture("ChamberIdentityViewport", "OMEGA RANGE // FINAL TARGET", "THREAT LEVEL: EXTREME", Color("#ed4e43")), Vector3(0, 4.05, -8.965), Vector2(4.7, 0.68), Vector3.ZERO, Color("#5d2023"), Color("#ed4e43"), 0.12).name = "FinalTargetChamberSign"
	_make_framed_surface(world_root, _make_facility_sign_texture("ContainmentWarningViewport", "OMEGA CONTAINMENT", "LOCKED", Color("#58d5e5")), Vector3(6.965, 2.9, -2.2), Vector2(1.72, 0.48), Vector3(0, -90, 0), Color("#16414b"), Color("#58d5e5"), 0.10).name = "ContainmentWarningSign"
	_build_easter_eggs(cyan_emission, yellow_mat)

	target = TargetScript.new()
	target.name = "FinalStationaryTarget"
	target.position = Vector3(0, 2.25, -5.9)
	world_root.add_child(target)
	target.configure()
	target.destroyed.connect(_on_target_destroyed)

	player = PlayerScript.new()
	player.name = "PlayerController"
	player.position = Vector3(0, 0.05, 4.0)
	world_root.add_child(player)
	player.shot_fired.connect(_on_player_shot)
	player.pause_requested.connect(_toggle_pause)


func _on_player_shot(collider, hit_point: Vector3) -> void:
	if state != "gameplay":
		return
	var hit_target: bool = collider != null and collider.is_in_group("campaign_target")
	session_shots += 1
	if hud != null:
		hud.play_weapon_fire()
	audio_manager.play_sfx("gunshot")
	if hit_target:
		session_hits += 1
		audio_manager.play_sfx("impact")
		if hud != null:
			hud.flash_crosshair_success()
	else:
		session_misses += 1
		if hud != null:
			hud.set_portrait("concerned" if session_misses < 5 else "disappointed")
		_handle_easter_egg_hit(collider)
	achievement_manager.on_shot(session_shots, session_misses)
	if hud != null:
		hud.update_readout(campaign_elapsed, session_shots, session_misses)


func _build_easter_eggs(cyan_material: Material, yellow_material: Material) -> void:
	# 1. Forbidden poster: its full framed bounds fit to the left of the target rail.
	var forbidden_poster := _make_easter_egg_panel("forbidden_poster", Vector3(-5.20, 2.2, -8.965), Vector3(2.95, 1.55, 0.04), _material_3d(Color("#2b1215"), 0.42, 0.46))
	forbidden_poster.name = "ForbiddenPosterCollision"
	_make_framed_surface(forbidden_poster, _make_forbidden_poster_texture(), Vector3(0, 0, 0.022), Vector2(2.76, 1.42), Vector3.ZERO, Color("#6a1c22"), Color("#f64b42"), 0.16).name = "ForbiddenPosterSurface"

	# 2. Emergency reducer on the left wall.
	# Keep the shootable trigger just in front of the left-wall collider.
	var reducer := _make_easter_egg_panel("difficulty_reducer", Vector3(-6.72, 2.0, 3.35), Vector3(0.04, 1.25, 2.25), _material_3d(Color("#123442"), 0.60, 0.34))
	_make_framed_surface(reducer, _make_reducer_panel_texture(), Vector3(0, 0, 0.022), Vector2(1.05, 1.92), Vector3(0, 90, 0), Color("#0b2933"), Color("#54dbe5"), 0.28).name = "DifficultyReducerFace"
	var reducer_lamp := OmniLight3D.new()
	reducer_lamp.light_color = Color("#36d7df")
	reducer_lamp.light_energy = 1.5
	reducer_lamp.omni_range = 2.4
	reducer.add_child(reducer_lamp)

	# 3. Ceiling-mounted warning; the tiny duck waits behind the player.
	_make_framed_surface(world_root, _make_look_behind_warning_texture(), Vector3(0, 4.55, 1.0), Vector2(3.75, 0.88), Vector3(90, 0, 0), Color("#36210d"), Color("#d9982d"), 0.14).name = "LookBehindCeilingWarning"
	var pedestal := _make_static_box(world_root, Vector3(0, 0.58, 7.75), Vector3(0.78, 1.12, 0.78), _material_3d(Color("#27333a"), 0.78, 0.26))
	pedestal.name = "TinyDuckPedestal"
	behind_duck = _make_tiny_duck(pedestal, Vector3(0, 0.83, 0), yellow_material)
	behind_duck.name = "BehindYouDuck"

	# 4. Four deliberately shootable ceiling fixtures.
	for fixture_data in [
		[Vector3(-3.4, 4.68, 1.0), "ceiling_light_a"],
		[Vector3(3.4, 4.68, 1.0), "ceiling_light_b"],
		[Vector3(-3.4, 4.68, -4.2), "ceiling_light_c"],
		[Vector3(3.4, 4.68, -4.2), "ceiling_light_d"]
	]:
		_make_destructible_ceiling_light(fixture_data[0], str(fixture_data[1]), cyan_material)


func _make_easter_egg_panel(id: String, position_value: Vector3, size_value: Vector3, material: Material) -> StaticBody3D:
	var panel := _make_static_box(world_root, position_value, size_value, material)
	panel.name = id.to_pascal_case()
	panel.set_meta("easter_egg_id", id)
	panel.add_to_group("easter_egg")
	return panel


func _make_textured_quad(parent: Node, texture: Texture2D, position_value: Vector3, size_value: Vector2, rotation_value: Vector3, glow_color: Color = Color.WHITE, glow_strength := 0.0) -> MeshInstance3D:
	var surface := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = size_value
	surface.mesh = mesh
	surface.position = position_value
	surface.rotation_degrees = rotation_value
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	if glow_strength > 0.0:
		material.emission_enabled = true
		material.emission = glow_color
		material.emission_texture = texture
		material.emission_energy_multiplier = glow_strength
	surface.material_override = material
	parent.add_child(surface)
	return surface


func _make_framed_surface(parent: Node, texture: Texture2D, position_value: Vector3, size_value: Vector2, rotation_value: Vector3, frame_color: Color, screen_glow: Color, glow_strength := 0.0) -> Node3D:
	var mount := Node3D.new()
	mount.position = position_value
	mount.rotation_degrees = rotation_value
	parent.add_child(mount)
	var backing := _make_visual_box(mount, Vector3(0, 0, -0.024), Vector3(size_value.x + 0.18, size_value.y + 0.18, 0.055), _material_3d(Color("#10161a"), 0.72, 0.30))
	backing.name = "PosterBacking"
	var edge_material := _emissive_3d(frame_color, 0.22)
	_make_visual_box(mount, Vector3(0, size_value.y * 0.5 + 0.055, 0.025), Vector3(size_value.x + 0.19, 0.11, 0.07), edge_material)
	_make_visual_box(mount, Vector3(0, -size_value.y * 0.5 - 0.055, 0.025), Vector3(size_value.x + 0.19, 0.11, 0.07), edge_material)
	_make_visual_box(mount, Vector3(size_value.x * 0.5 + 0.055, 0, 0.025), Vector3(0.11, size_value.y + 0.19, 0.07), edge_material)
	_make_visual_box(mount, Vector3(-size_value.x * 0.5 - 0.055, 0, 0.025), Vector3(0.11, size_value.y + 0.19, 0.07), edge_material)
	var screen := _make_textured_quad(mount, texture, Vector3(0, 0, 0.038), size_value, Vector3.ZERO, screen_glow, glow_strength)
	screen.name = "MountedSurface"
	return mount


func _make_surface_viewport(viewport_name: String, viewport_size: Vector2i, transparent := false) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = viewport_size
	viewport.transparent_bg = transparent
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	world_root.add_child(viewport)
	return viewport


func _make_viewport_label(parent: Control, text_value: String, position_value: Vector2, size_value: Vector2, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_CENTER) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = position_value
	label.size = size_value
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	parent.add_child(label)
	return label


func _make_forbidden_poster_texture() -> Texture2D:
	var viewport := _make_surface_viewport("ForbiddenPosterViewport", Vector2i(1280, 720))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color("#200b0f")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var inner := ColorRect.new()
	inner.color = Color("#3a141a")
	inner.position = Vector2(30, 30)
	inner.size = Vector2(1220, 660)
	root.add_child(inner)
	for rect_data in [[Vector2(30, 30), Vector2(1220, 10)], [Vector2(30, 680), Vector2(1220, 10)], [Vector2(30, 30), Vector2(10, 660)], [Vector2(1240, 30), Vector2(10, 660)]]:
		var edge := ColorRect.new()
		edge.color = Color("#f24d43")
		edge.position = rect_data[0]
		edge.size = rect_data[1]
		root.add_child(edge)
	_make_viewport_label(root, "ABSOLUTELY UNDER NO\nCIRCUMSTANCES", Vector2(54, 74), Vector2(1172, 202), 54, Color("#ffd0c8"))
	var warning_strip := ColorRect.new()
	warning_strip.color = Color("#981b20")
	warning_strip.position = Vector2(92, 332)
	warning_strip.size = Vector2(1096, 144)
	root.add_child(warning_strip)
	_make_viewport_label(root, "DO NOT SHOOT THIS POSTER", Vector2(104, 351), Vector2(1072, 102), 58, Color("#fff5ea"))
	_make_viewport_label(root, "AUTHORIZED PERSONNEL ONLY", Vector2(54, 538), Vector2(1172, 60), 24, Color("#b36d68"))
	return viewport.get_texture()


func _make_reducer_panel_texture() -> Texture2D:
	var viewport := _make_surface_viewport("DifficultyReducerViewport", Vector2i(720, 1280))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color("#08232d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	for rect_data in [[Vector2(22, 22), Vector2(676, 10)], [Vector2(22, 1248), Vector2(676, 10)], [Vector2(22, 22), Vector2(10, 1236)], [Vector2(688, 22), Vector2(10, 1236)]]:
		var edge := ColorRect.new()
		edge.color = Color("#69e4ef")
		edge.position = rect_data[0]
		edge.size = rect_data[1]
		root.add_child(edge)
	_make_viewport_label(root, "EMERGENCY", Vector2(36, 112), Vector2(648, 82), 59, Color("#c3fbff"))
	_make_viewport_label(root, "DIFFICULTY", Vector2(36, 212), Vector2(648, 82), 59, Color("#c3fbff"))
	_make_viewport_label(root, "REDUCER", Vector2(36, 312), Vector2(648, 82), 59, Color("#c3fbff"))
	var indicator := ColorRect.new()
	indicator.color = Color("#53d9e3")
	indicator.position = Vector2(170, 548)
	indicator.size = Vector2(380, 380)
	root.add_child(indicator)
	_make_viewport_label(root, "+", Vector2(170, 568), Vector2(380, 340), 268, Color("#eaffff"))
	_make_viewport_label(root, "FOR WHEN IT GETS HARD", Vector2(42, 1060), Vector2(636, 70), 25, Color("#8bd5da"))
	return viewport.get_texture()


func _make_look_behind_warning_texture() -> Texture2D:
	var viewport := _make_surface_viewport("LookBehindWarningViewport", Vector2i(1280, 300))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color("#27180c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	for rect_data in [[Vector2(0, 0), Vector2(1280, 10)], [Vector2(0, 290), Vector2(1280, 10)], [Vector2(0, 0), Vector2(10, 300)], [Vector2(1270, 0), Vector2(10, 300)]]:
		var edge := ColorRect.new()
		edge.color = Color("#f1ba50")
		edge.position = rect_data[0]
		edge.size = rect_data[1]
		root.add_child(edge)
	_make_viewport_label(root, "DO NOT LOOK BEHIND YOU", Vector2(24, 62), Vector2(1232, 176), 72, Color("#ffd47a"))
	return viewport.get_texture()


func _make_facility_sign_texture(viewport_name: String, header_text: String, message_text: String, accent: Color) -> Texture2D:
	var viewport := _make_surface_viewport(viewport_name, Vector2i(960, 280))
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color("#071116")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)
	var inset := ColorRect.new()
	inset.color = Color("#10242b")
	inset.position = Vector2(20, 20)
	inset.size = Vector2(920, 240)
	root.add_child(inset)
	for rect_data in [[Vector2(20, 20), Vector2(920, 6)], [Vector2(20, 254), Vector2(920, 6)], [Vector2(20, 20), Vector2(6, 240)], [Vector2(934, 20), Vector2(6, 240)]]:
		var edge := ColorRect.new()
		edge.color = accent
		edge.position = rect_data[0]
		edge.size = rect_data[1]
		root.add_child(edge)
	_make_viewport_label(root, header_text, Vector2(48, 42), Vector2(864, 54), 28, accent)
	var divider := ColorRect.new()
	divider.color = Color(accent.r, accent.g, accent.b, 0.66)
	divider.position = Vector2(90, 108)
	divider.size = Vector2(780, 3)
	root.add_child(divider)
	_make_viewport_label(root, message_text, Vector2(42, 126), Vector2(876, 92), 43, Color("#ecf8f5"))
	return viewport.get_texture()


func _make_tiny_duck(parent: Node, position_value: Vector3, yellow_material: Material) -> Node3D:
	var duck := Node3D.new()
	duck.position = position_value
	parent.add_child(duck)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.22
	body_mesh.height = 0.34
	body.mesh = body_mesh
	body.material_override = yellow_material
	duck.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.15
	head_mesh.height = 0.25
	head.mesh = head_mesh
	head.position = Vector3(0, 0.20, -0.05)
	head.material_override = yellow_material
	duck.add_child(head)
	_make_visual_box(duck, Vector3(0, 0.18, -0.19), Vector3(0.15, 0.055, 0.09), _emissive_3d(Color("#ff8c29"), 1.0))
	return duck


func _make_destructible_ceiling_light(position_value: Vector3, id: String, light_material: Material) -> void:
	var fixture := _make_easter_egg_panel(id, position_value, Vector3(1.55, 0.16, 0.66), light_material)
	fixture.name = "Destructible" + id.to_pascal_case()
	var core := _make_visual_box(fixture, Vector3(0, -0.12, 0), Vector3(1.02, 0.06, 0.18), _emissive_3d(Color("#c5fbff"), 3.5))
	core.name = "LightCore"
	var light := OmniLight3D.new()
	light.name = "FixtureLight"
	light.position = Vector3(0, -0.22, 0)
	light.light_color = Color("#73e8f2")
	light.light_energy = 1.8
	light.omni_range = 5.6
	fixture.add_child(light)
	ceiling_lights.append(fixture)


func _handle_easter_egg_hit(collider) -> void:
	if collider == null or not collider.has_meta("easter_egg_id"):
		return
	var id := str(collider.get_meta("easter_egg_id"))
	match id:
		"forbidden_poster":
			_trigger_forbidden_poster_death()
		"difficulty_reducer":
			_show_easter_egg_notification(DIFFICULTY_REDUCER_NOTIFICATION, Color("#6fe3eb"))
		"ceiling_light_a", "ceiling_light_b", "ceiling_light_c", "ceiling_light_d":
			_disable_ceiling_light(collider, id)


func _disable_ceiling_light(fixture: StaticBody3D, id: String) -> void:
	if disabled_ceiling_lights.has(id):
		return
	disabled_ceiling_lights[id] = true
	for child in fixture.get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
		elif child is MeshInstance3D:
			child.material_override = _material_3d(Color("#10181d"), 0.76, 0.40)
		elif child is OmniLight3D:
			child.light_energy = 0.0
	if disabled_ceiling_lights.size() < ceiling_lights.size():
		return
	if combat_environment != null:
		combat_environment.ambient_light_energy = 0.16
		combat_environment.fog_light_energy = 0.18
	if combat_key_light != null:
		combat_key_light.light_energy = 0.34
	_show_easter_egg_notification("Congratulations. You made this harder.", Color("#ffbd54"))
	achievement_manager.unlock("self_sabotage")


func _check_behind_duck_discovery() -> void:
	if duck_discovered or player == null or player.camera == null or not is_instance_valid(behind_duck):
		return
	var to_duck: Vector3 = behind_duck.global_position - player.camera.global_position
	if to_duck.length() > 7.5:
		return
	var forward: Vector3 = -player.camera.global_transform.basis.z.normalized()
	if forward.dot(to_duck.normalized()) > 0.82:
		duck_discovered = true
		achievement_manager.unlock("you_looked")


func _show_easter_egg_notification(text_value: String, color: Color) -> void:
	var is_difficulty_reducer := text_value == DIFFICULTY_REDUCER_NOTIFICATION
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(EASTER_NOTIFICATION_WIDTH if is_difficulty_reducer else 450.0, 64)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	panel.modulate.a = 0.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.065, 0.97), color, 2, 4))
	notification_stack.add_child(panel)
	var label := _label(text_value, 14 if is_difficulty_reducer else 16, color, HORIZONTAL_ALIGNMENT_CENTER)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if is_difficulty_reducer:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	var appear := create_tween().set_parallel(true)
	appear.tween_property(panel, "modulate:a", 1.0, 0.20)
	var disappear := create_tween()
	disappear.tween_interval(3.2)
	disappear.tween_property(panel, "modulate:a", 0.0, 0.28)
	disappear.tween_callback(panel.queue_free)


func _trigger_forbidden_poster_death() -> void:
	if state != "gameplay":
		return
	state = "poster_death"
	if player != null:
		player.set_controls_enabled(false)
	if hud != null:
		hud.visible = false
	audio_manager.play_ambience(false)
	audio_manager.stop_music()
	transition_manager.overlay.color = Color(0.0, 0.0, 0.0, 0.0)
	var fade := create_tween()
	fade.tween_property(transition_manager.overlay, "color:a", 1.0, 0.46)
	await fade.finished
	if state == "poster_death":
		_show_poster_death_ui()


func _show_poster_death_ui() -> void:
	if is_instance_valid(death_layer):
		death_layer.queue_free()
	audio_manager.play_music("poster_death")
	death_layer = CanvasLayer.new()
	death_layer.layer = 120
	death_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(death_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(350, 200)
	panel.size = Vector2(580, 300)
	panel.modulate.a = 0.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.0, 0.0, 0.0, 0.94), Color("#d52b27"), 3, 4))
	death_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	panel.add_child(box)
	box.add_child(_label("YOU DIED", 52, Color("#ff2d29"), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_menu_button("Back to Home Screen", _poster_death_to_title))
	box.add_child(_menu_button("Try Again", _poster_death_try_again, true))
	var reveal := create_tween()
	reveal.tween_property(panel, "modulate:a", 1.0, 0.30)


func _poster_death_to_title() -> void:
	audio_manager.stop_music()
	if is_instance_valid(death_layer):
		death_layer.queue_free()
	death_layer = null
	_show_title()


func _poster_death_try_again() -> void:
	audio_manager.stop_music()
	if is_instance_valid(death_layer):
		death_layer.queue_free()
	death_layer = null
	transition_manager.fade_in(0.25)
	_start_loading(selected_difficulty)


func _on_target_destroyed() -> void:
	if state != "gameplay":
		return
	campaign_elapsed = max(0.0, (Time.get_ticks_msec() - campaign_started_msec) / 1000.0)
	state = "victory"
	player.set_controls_enabled(false)
	player.cinematic_shake(1.6)
	hud.mark_enemy_defeated()
	hud.set_portrait("shocked")
	audio_manager.play_ambience(false)
	victory_music_active = true
	audio_manager.play_music("victory")
	transition_manager.flash(Color(1.0, 0.24, 0.09, 0.78), 0.52)
	_spawn_confetti()
	audio_manager.play_sfx("confetti")
	call_deferred("_victory_sequence")


func _victory_sequence() -> void:
	await get_tree().create_timer(0.48).timeout
	var panel := PanelContainer.new()
	panel.position = Vector2(250, 150)
	panel.size = Vector2(780, 275)
	panel.modulate.a = 0.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.015, 0.025, 0.035, 0.95), Color("#ffb72b"), 4, 4))
	ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var heading := _label("CAMPAIGN COMPLETED", 48, Color("#ffdc5e"), HORIZONTAL_ALIGNMENT_CENTER)
	box.add_child(heading)
	box.add_child(_label("CONGRATULATIONS", 27, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("You beat the hardest game ever made.", 20, Color("#cad8df"), HORIZONTAL_ALIGNMENT_CENTER))
	panel.scale = Vector2(0.72, 0.72)
	panel.pivot_offset = panel.size * 0.5
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.34)
	tween.tween_property(panel, "scale", Vector2.ONE, 0.42)
	await get_tree().create_timer(2.85).timeout
	save_manager.record_completion(selected_difficulty, campaign_elapsed, session_shots, session_hits, session_misses)
	achievement_manager.on_completion(selected_difficulty, campaign_elapsed)
	_show_results()


func _spawn_confetti() -> void:
	if world_root == null:
		return
	var particles := GPUParticles3D.new()
	particles.name = "CivilizationSavedConfetti"
	particles.position = Vector3(0, 4.7, -2.0)
	particles.amount = 850
	particles.lifetime = 3.8
	particles.one_shot = true
	particles.explosiveness = 0.92
	particles.visibility_aabb = AABB(Vector3(-9, -6, -12), Vector3(18, 14, 24))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(6.5, 0.3, 7.5)
	process.direction = Vector3(0, 1, 0)
	process.spread = 88.0
	process.initial_velocity_min = 4.0
	process.initial_velocity_max = 10.0
	process.gravity = Vector3(0, -7.8, 0)
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("#ff3b30"), Color("#ffd43b"), Color("#36d7ff"), Color("#7cff75"), Color("#f464ff")])
	var color_ramp := GradientTexture1D.new()
	color_ramp.gradient = gradient
	process.color_ramp = color_ramp
	particles.process_material = process
	var confetti_mesh := BoxMesh.new()
	confetti_mesh.size = Vector3(0.08, 0.025, 0.24)
	confetti_mesh.material = _material_3d(Color.WHITE, 0.20, 0.40)
	particles.draw_pass_1 = confetti_mesh
	world_root.add_child(particles)
	particles.emitting = true


func _show_results() -> void:
	state = "results"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if hud != null:
		hud.visible = false
	_clear_ui()
	var bg := _add_background(Color("#03070b"), Color("#182a31"))
	_add_scanlines(bg)
	var heading := _label("AFTER ACTION REPORT", 14, Color("#ff5a48"), HORIZONTAL_ALIGNMENT_CENTER)
	heading.position = Vector2(320, 28)
	heading.size = Vector2(640, 26)
	bg.add_child(heading)
	var complete := _label("CAMPAIGN COMPLETED", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	complete.position = Vector2(260, 55)
	complete.size = Vector2(760, 50)
	bg.add_child(complete)

	var stats_panel := PanelContainer.new()
	stats_panel.position = Vector2(70, 125)
	stats_panel.size = Vector2(710, 475)
	stats_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.045, 0.96), Color("#37596b"), 2, 4))
	bg.add_child(stats_panel)
	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 7)
	stats_panel.add_child(stats_box)
	var accuracy := 0.0 if session_shots == 0 else float(session_hits) / session_shots * 100.0
	var rows := [
		["SELECTED DIFFICULTY", selected_difficulty.to_upper()],
		["COMPLETION TIME", "%.2f SECONDS" % campaign_elapsed],
		["SHOTS FIRED", str(session_shots)],
		["SHOTS LANDED", str(session_hits)],
		["SHOTS MISSED", str(session_misses)],
		["ACCURACY", "%.1f%%" % accuracy],
		["CAMPAIGN COMPLETION", "100%"],
		["ENEMIES DEFEATED", "1"],
		["CONTINENTS SAVED", "7"]
	]
	for row_data in rows:
		var row := HBoxContainer.new()
		var left := _label(row_data[0], 15, Color("#7f96a3"))
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(left)
		var right := _label(row_data[1], 17, Color("#ecf3f5"), HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(right)
		stats_box.add_child(row)
		stats_box.add_child(_rule(Color("#173241"), 1))

	var rank_panel := PanelContainer.new()
	rank_panel.position = Vector2(810, 125)
	rank_panel.size = Vector2(400, 475)
	rank_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.05, 0.025, 0.02, 0.97), Color("#f0a72a"), 3, 4))
	bg.add_child(rank_panel)
	var rank_box := VBoxContainer.new()
	rank_box.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_box.add_theme_constant_override("separation", 10)
	rank_panel.add_child(rank_box)
	rank_box.add_child(_label("RANK", 15, Color("#b79558"), HORIZONTAL_ALIGNMENT_CENTER))
	rank_box.add_child(_label("S++++", 62, Color("#ffcf43"), HORIZONTAL_ALIGNMENT_CENTER))
	rank_box.add_child(_label("LEGENDARY", 25, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	var portrait := PortraitScript.new()
	portrait.custom_minimum_size = Vector2(240, 150)
	portrait.set_expression("exhausted" if int(save_manager.stats()["total_campaign_completions"]) >= 3 else "proud")
	rank_box.add_child(portrait)
	var messages := [
		"Historians will speak of this moment.",
		"Humanity owes you a debt it can never repay.",
		"The target never stood a chance.",
		"Few have achieved what you accomplished today.",
		"Civilization may finally rest."
	]
	var message := _label(messages.pick_random(), 14, Color("#d9c9a7"), HORIZONTAL_ALIGNMENT_CENTER)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rank_box.add_child(message)

	var button_row := HBoxContainer.new()
	button_row.position = Vector2(145, 625)
	button_row.size = Vector2(990, 60)
	button_row.add_theme_constant_override("separation", 15)
	bg.add_child(button_row)
	button_row.add_child(_menu_button("WATCH CREDITS", _show_credits))
	button_row.add_child(_menu_button("PLAY AGAIN", _show_difficulty, true))
	button_row.add_child(_menu_button("RETIRE UNDEFEATED", _show_title))


func _show_achievements() -> void:
	_destroy_world()
	state = "achievements"
	_clear_ui()
	var bg := _add_background(Color("#03070b"), Color("#14222c"))
	_add_scanlines(bg)
	var heading := _label("ACHIEVEMENTS", 42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	heading.position = Vector2(280, 32)
	heading.size = Vector2(720, 60)
	bg.add_child(heading)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(190, 115)
	scroll.size = Vector2(900, 505)
	bg.add_child(scroll)
	var list := VBoxContainer.new()
	list.custom_minimum_size.x = 870
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	for entry in achievement_manager.entries():
		var unlocked := bool(entry["unlocked"])
		var panel := PanelContainer.new()
		panel.custom_minimum_size.y = 78
		panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.055, 0.065, 0.94) if unlocked else Color(0.025, 0.028, 0.032, 0.94), Color("#53c8da") if unlocked else Color("#303b42"), 2, 3))
		list.add_child(panel)
		var row := HBoxContainer.new()
		panel.add_child(row)
		var icon := _label("◆" if unlocked else "◇", 31, Color("#70ebd8") if unlocked else Color("#4c5961"), HORIZONTAL_ALIGNMENT_CENTER)
		icon.custom_minimum_size.x = 55
		row.add_child(icon)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)
		text_box.add_child(_label(entry["title"] if unlocked else "CLASSIFIED ACHIEVEMENT", 17, Color.WHITE if unlocked else Color("#697780")))
		text_box.add_child(_label(entry["description"] if unlocked else "Complete additional operations to reveal.", 13, Color("#8ca0aa") if unlocked else Color("#4c5961")))
	var back := _menu_button("BACK", _show_title)
	back.position = Vector2(38, 650)
	back.size = Vector2(190, 46)
	bg.add_child(back)


func _show_statistics() -> void:
	_destroy_world()
	state = "statistics"
	_clear_ui()
	var bg := _add_background(Color("#03070b"), Color("#13212a"))
	_add_scanlines(bg)
	var heading := _label("CAMPAIGN STATISTICS", 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	heading.position = Vector2(240, 36)
	heading.size = Vector2(800, 55)
	bg.add_child(heading)
	var panel := PanelContainer.new()
	panel.position = Vector2(185, 110)
	panel.size = Vector2(910, 525)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.045, 0.96), Color("#2b5265"), 2, 4))
	bg.add_child(panel)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 42)
	grid.add_theme_constant_override("v_separation", 8)
	panel.add_child(grid)
	var s: Dictionary = save_manager.stats()
	var shots := int(s["total_shots_fired"])
	var accuracy := 0.0 if shots == 0 else float(s["total_successful_hits"]) / shots * 100.0
	var stats_rows := [
		["Total campaign completions", str(s["total_campaign_completions"])],
		["Fastest campaign time", _time_or_dash(float(s["fastest_campaign_time"]))],
		["Slowest campaign time", _time_or_dash(float(s["slowest_campaign_time"]))],
		["Total shots fired", str(s["total_shots_fired"])],
		["Total successful hits", str(s["total_successful_hits"])],
		["Total misses", str(s["total_misses"])],
		["Overall accuracy", "%.1f%%" % accuracy],
		["Most selected difficulty", save_manager.most_selected_difficulty()],
		["Easy completions", str(s["difficulty_completions"]["Easy"])],
		["Normal completions", str(s["difficulty_completions"]["Normal"])],
		["Hard completions", str(s["difficulty_completions"]["Hard"])],
		["Expert completions", str(s["difficulty_completions"]["Expert"])],
		["Impossible completions", str(s["difficulty_completions"]["Impossible"])],
		["Total time spent playing", _format_duration(float(s["total_time_playing"]))],
		["Total time spent in menus", _format_duration(float(s["total_time_menus"]))],
		["Credits completed", str(s["credits_completed"])],
		["I VALUE MY LIFE selected", str(s["valued_life_count"])],
		["Combat-to-menu ratio", _combat_menu_ratio(s)]
	]
	for data_row in stats_rows:
		var name_label := _label(data_row[0].to_upper(), 14, Color("#7e949f"))
		var value_label := _label(data_row[1], 17, Color("#ecf4f6"), HORIZONTAL_ALIGNMENT_RIGHT)
		value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(name_label)
		grid.add_child(value_label)
	var back := _menu_button("BACK", _show_title)
	back.position = Vector2(38, 650)
	back.size = Vector2(190, 46)
	bg.add_child(back)


func _show_settings(from_pause := false) -> void:
	settings_from_pause = from_pause
	if not from_pause:
		_destroy_world()
	elif hud != null:
		hud.visible = false
	state = "settings_pause" if from_pause else "settings"
	get_tree().paused = false
	_clear_ui()
	var bg := _add_background(Color("#03070b"), Color("#12212a"))
	_add_scanlines(bg)
	var heading := _label("SETTINGS", 42, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	heading.position = Vector2(300, 42)
	heading.size = Vector2(680, 55)
	bg.add_child(heading)
	var panel := PanelContainer.new()
	panel.position = Vector2(300, 120)
	panel.size = Vector2(680, 490)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.035, 0.045, 0.97), Color("#33586a"), 2, 5))
	bg.add_child(panel)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 16)
	panel.add_child(list)
	_add_slider_setting(list, "MASTER VOLUME", "master_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(list, "MUSIC VOLUME", "music_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(list, "SOUND-EFFECTS VOLUME", "sfx_volume", 0.0, 1.0, 0.01)
	_add_slider_setting(list, "MOUSE SENSITIVITY", "mouse_sensitivity", 0.05, 0.60, 0.01)
	var full_row := HBoxContainer.new()
	list.add_child(full_row)
	var full_label := _label("FULLSCREEN", 16, Color("#b7c5cc"))
	full_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full_row.add_child(full_label)
	var full := CheckButton.new()
	full.button_pressed = bool(save_manager.get_setting("fullscreen", false))
	full.toggled.connect(_on_fullscreen_changed)
	full_row.add_child(full)
	var res_row := HBoxContainer.new()
	list.add_child(res_row)
	var res_label := _label("DISPLAY RESOLUTION", 16, Color("#b7c5cc"))
	res_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	res_row.add_child(res_label)
	var option := OptionButton.new()
	var resolutions := ["1280x720", "1366x768", "1600x900", "1920x1080"]
	for resolution in resolutions:
		option.add_item(resolution)
	var current := str(save_manager.get_setting("resolution", "1280x720"))
	option.select(maxi(0, resolutions.find(current)))
	option.item_selected.connect(_on_resolution_selected.bind(resolutions))
	res_row.add_child(option)
	var back_callable := _return_to_pause if from_pause else _show_title
	var back := _menu_button("APPLY AND BACK", back_callable, true)
	list.add_child(back)


func _add_slider_setting(parent: VBoxContainer, label_text: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var column := VBoxContainer.new()
	parent.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := _label(label_text, 15, Color("#b7c5cc"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var value_label := _label("%.2f" % float(save_manager.get_setting(key, minimum)), 14, Color("#63d6e4"), HORIZONTAL_ALIGNMENT_RIGHT)
	value_label.custom_minimum_size.x = 70
	header.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = float(save_manager.get_setting(key, minimum))
	slider.value_changed.connect(_on_setting_slider_changed.bind(key, value_label))
	column.add_child(slider)


func _on_setting_slider_changed(value: float, key: String, value_label: Label) -> void:
	value_label.text = "%.2f" % value
	save_manager.set_setting(key, value, false)
	if key == "mouse_sensitivity" and player != null:
		player.mouse_sensitivity = value
	audio_manager.set_volumes(
		float(save_manager.get_setting("master_volume", 0.85)),
		float(save_manager.get_setting("music_volume", 0.60)),
		float(save_manager.get_setting("sfx_volume", 0.85))
	)


func _on_fullscreen_changed(value: bool) -> void:
	save_manager.set_setting("fullscreen", value)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if value else DisplayServer.WINDOW_MODE_WINDOWED)


func _on_resolution_selected(index: int, resolutions: Array) -> void:
	var resolution: String = resolutions[index]
	save_manager.set_setting("resolution", resolution)
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED:
		var parts := resolution.split("x")
		DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))


func _apply_saved_display_settings() -> void:
	var fullscreen := bool(save_manager.get_setting("fullscreen", false))
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _toggle_pause() -> void:
	if state == "gameplay":
		_show_pause()
	elif state == "paused":
		_resume_game()


func _show_pause() -> void:
	if state != "gameplay":
		return
	state = "paused"
	player.set_controls_enabled(false)
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 70
	pause_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(pause_layer)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	pause_layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.position = Vector2(430, 95)
	panel.size = Vector2(420, 535)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.035, 0.045, 0.98), Color("#a82f28"), 3, 4))
	pause_layer.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 13)
	panel.add_child(box)
	box.add_child(_label("CAMPAIGN PAUSED", 32, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_label("The target remains contained. For now.", 13, Color("#8799a2"), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_menu_button("RESUME", _resume_game, true))
	box.add_child(_menu_button("SETTINGS", _pause_to_settings))
	box.add_child(_menu_button("RESTART CAMPAIGN", _restart_campaign))
	box.add_child(_menu_button("RETURN TO MAIN MENU", _pause_to_main))
	box.add_child(_menu_button("QUIT", _quit_game, false, true))
	get_tree().paused = true


func _resume_game() -> void:
	get_tree().paused = false
	if is_instance_valid(pause_layer):
		pause_layer.queue_free()
	pause_layer = null
	state = "gameplay"
	player.set_controls_enabled(true)


func _pause_to_settings() -> void:
	get_tree().paused = false
	if is_instance_valid(pause_layer):
		pause_layer.queue_free()
	pause_layer = null
	_show_settings(true)


func _return_to_pause() -> void:
	save_manager.save_data()
	_clear_ui()
	if hud != null:
		hud.visible = true
	state = "gameplay"
	_show_pause()


func _restart_campaign() -> void:
	get_tree().paused = false
	if is_instance_valid(pause_layer):
		pause_layer.queue_free()
	_start_loading(selected_difficulty)


func _pause_to_main() -> void:
	get_tree().paused = false
	_show_title()


func _show_credits() -> void:
	_destroy_world()
	state = "credits"
	_clear_ui()
	audio_manager.play_music("credits")
	var bg := _add_background(Color("#010305"), Color("#0b161c"))
	_add_scanlines(bg)
	var viewport := Control.new()
	viewport.position = Vector2(170, 0)
	viewport.size = Vector2(940, 720)
	viewport.clip_contents = true
	bg.add_child(viewport)
	var roll := VBoxContainer.new()
	roll.position = Vector2(90, 720)
	roll.size = Vector2(760, 2700)
	roll.add_theme_constant_override("separation", 10)
	viewport.add_child(roll)
	var title := _label("THE HARDEST GAME EVER MADE", 38, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	title.custom_minimum_size.y = 100
	roll.add_child(title)
	var credits := [
		["Created by", "Alex Martinez"],
		["Designed by", "Alex Martinez"],
		["Campaign Director", "Alex Martinez"],
		["Director of Target Placement", "Alex Martinez"],
		["Lead Difficulty Consultant", "Alex Martinez"],
		["Target Movement Supervisor", "Position Vacant"],
		["Ammunition Conservation Specialist", "Not Required"],
		["Historical Accuracy", "Absolutely None"],
		["Emotional Support", "The Restart Button"],
		["Person Responsible for This", "Alex Martinez"],
		["Person Who Could Have Stopped This", "Also Alex Martinez"],
		["Special Thanks", "The Player, for believing in themselves"],
		["In Memory of", "The Target"]
	]
	for pair in credits:
		var role := _label(pair[0], 14, Color("#6f8793"), HORIZONTAL_ALIGNMENT_CENTER)
		role.custom_minimum_size.y = 30
		roll.add_child(role)
		var person := _label(pair[1], 22, Color("#e7edef"), HORIZONTAL_ALIGNMENT_CENTER)
		person.custom_minimum_size.y = 56
		roll.add_child(person)
	var end := _label("THE END", 52, Color("#ffcf49"), HORIZONTAL_ALIGNMENT_CENTER)
	end.custom_minimum_size.y = 150
	roll.add_child(end)
	var back := _menu_button("RETURN TO TITLE", _show_title)
	back.position = Vector2(28, 650)
	back.size = Vector2(220, 46)
	bg.add_child(back)
	credits_tween = create_tween()
	credits_tween.tween_property(roll, "position:y", -2500.0, 19.0).set_trans(Tween.TRANS_LINEAR)
	credits_tween.tween_callback(_credits_completed)


func _credits_completed() -> void:
	if state != "credits":
		return
	save_manager.increment_stat("credits_completed", 1)
	achievement_manager.on_credits_completed()
	var panel := PanelContainer.new()
	panel.position = Vector2(390, 205)
	panel.size = Vector2(500, 300)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.03, 0.04, 0.98), Color("#e5b33b"), 3, 4))
	ui_root.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	panel.add_child(box)
	box.add_child(_label("THE END", 48, Color("#ffcf49"), HORIZONTAL_ALIGNMENT_CENTER))
	box.add_child(_menu_button("RETURN TO TITLE", _show_title))


func _show_achievement_notification(title: String, description: String) -> void:
	audio_manager.play_sfx("achievement")
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 92)
	panel.modulate.a = 0.0
	panel.position.x = 80
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.07, 0.075, 0.98), Color("#61e0cf"), 2, 4))
	notification_stack.add_child(panel)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var icon := _label("◆", 34, Color("#70f0d0"), HORIZONTAL_ALIGNMENT_CENTER)
	icon.custom_minimum_size.x = 55
	row.add_child(icon)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	box.add_child(_label("ACHIEVEMENT UNLOCKED", 11, Color("#72a9a8")))
	box.add_child(_label(title, 17, Color.WHITE))
	box.add_child(_label(description, 12, Color("#a5b9bd")))
	var tween := create_tween().set_parallel(true)
	tween.tween_property(panel, "modulate:a", 1.0, 0.22)
	tween.tween_property(panel, "position:x", 0.0, 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var out := create_tween()
	out.tween_interval(4.2)
	out.tween_property(panel, "modulate:a", 0.0, 0.30)
	out.tween_callback(panel.queue_free)


func _clear_ui() -> void:
	ui_action_lock = false
	if is_instance_valid(ui_root):
		remove_child(ui_root)
		ui_root.free()
	ui_root = Control.new()
	ui_root.name = "UIRoot"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.process_mode = Node.PROCESS_MODE_ALWAYS
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_root.theme = CommandTheme
	add_child(ui_root)


func _destroy_world() -> void:
	get_tree().paused = false
	audio_manager.stop_music()
	if is_instance_valid(death_layer):
		death_layer.free()
	death_layer = null
	if is_instance_valid(pause_layer):
		pause_layer.free()
	pause_layer = null
	if is_instance_valid(hud):
		hud.free()
	hud = null
	if is_instance_valid(world_root):
		world_root.free()
	world_root = null
	player = null
	target = null
	red_lights.clear()
	ceiling_lights.clear()
	disabled_ceiling_lights.clear()
	combat_environment = null
	combat_key_light = null
	behind_duck = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _add_background(start_color: Color, end_color: Color) -> Control:
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_root.add_child(holder)
	var texture_rect := TextureRect.new()
	texture_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var gradient := Gradient.new()
	gradient.set_color(0, start_color)
	gradient.set_color(1, end_color)
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 1280
	texture.height = 720
	texture.fill_from = Vector2(0.05, 0.05)
	texture.fill_to = Vector2(0.95, 0.95)
	texture_rect.texture = texture
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(texture_rect)
	var backdrop := CommandBackdropScript.new()
	backdrop.configure(start_color, end_color)
	holder.add_child(backdrop)
	return holder


func _add_scanlines(parent: Control) -> void:
	for y in range(0, 720, 8):
		var line := ColorRect.new()
		line.position = Vector2(0, y)
		line.size = Vector2(1280, 1)
		line.color = Color(0.35, 0.65, 0.72, 0.035)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(line)


func _add_corner_marks(parent: Control) -> void:
	for point in [Vector2(26, 26), Vector2(1218, 26), Vector2(26, 668), Vector2(1218, 668)]:
		var mark := Panel.new()
		mark.position = point
		mark.size = Vector2(36, 26)
		mark.add_theme_stylebox_override("panel", _panel_style(Color.TRANSPARENT, Color("#31596b"), 2, 0))
		parent.add_child(mark)


func _menu_button(text_value: String, callback: Callable, primary := false, danger := false) -> Button:
	var button := CommandButtonScript.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(330, 52)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var normal_bg := Color(0.025, 0.065, 0.090, 0.98)
	var border := Color("#3e7188")
	if primary:
		normal_bg = Color(0.035, 0.105, 0.135, 0.98)
		border = Color("#66c8dd")
	if danger:
		normal_bg = Color(0.20, 0.02, 0.018, 0.98)
		border = Color("#ff392d")
	button.set_command_styles(
		_panel_style(normal_bg, border, 2, 4),
		_red_hover_style(),
		_panel_style(Color(0.20, 0.008, 0.006, 1.0), Color("#ff2d22"), 3, 4),
		_focus_style()
	)
	var arrow := _label("›", 30, Color("#78cce0"), HORIZONTAL_ALIGNMENT_CENTER)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	arrow.position = Vector2(-38, 0)
	arrow.size = Vector2(28, 52)
	arrow.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	button.add_child(arrow)
	button.pressed.connect(_trigger_ui_action.bind(callback))
	button.add_to_group("command_buttons")
	button.mouse_entered.connect(func() -> void:
		arrow.add_theme_color_override("font_color", Color("#ffe0d8"))
		_on_menu_hover()
	)
	button.mouse_exited.connect(func() -> void:
		arrow.add_theme_color_override("font_color", Color("#78cce0"))
	)
	button.button_down.connect(func() -> void:
		button.pivot_offset = button.size * 0.5
		button.scale = Vector2(0.985, 0.985)
	)
	button.button_up.connect(func() -> void:
		button.scale = Vector2.ONE
	)
	return button


func _trigger_ui_action(callback: Callable) -> void:
	if ui_action_lock or not callback.is_valid():
		return
	ui_action_lock = true
	callback.call_deferred()


func _on_menu_hover() -> void:
	audio_manager.play_sfx("menu_move")


func _label(text_value: String, font_size: int, color: Color, alignment := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.88))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.horizontal_alignment = alignment
	return label


func _panel_style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	style.shadow_color = Color(border.r, border.g, border.b, 0.14)
	style.shadow_size = 5
	style.shadow_offset = Vector2.ZERO
	return style


func _red_hover_style(background_alpha := 0.78) -> StyleBoxFlat:
	var style := _panel_style(Color(0.48, 0.025, 0.012, background_alpha), Color("#ff5547"), 3, 4)
	style.shadow_color = Color(1.0, 0.08, 0.035, 0.58)
	style.shadow_size = 9
	style.shadow_offset = Vector2.ZERO
	return style


func _focus_style() -> StyleBoxFlat:
	var style := _panel_style(Color(0.0, 0.0, 0.0, 0.0), Color("#73d7eb"), 2, 4)
	style.shadow_color = Color(0.26, 0.80, 0.93, 0.52)
	style.shadow_size = 7
	return style


func _rule(color: Color, height: int) -> ColorRect:
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(40, height)
	rule.color = color
	return rule


func _material_3d(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _emissive_3d(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material_3d(color, 0.44, 0.26)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _make_static_box(parent: Node, position_value: Vector3, size_value: Vector3, material: Material) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position_value
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size_value
	collision.shape = shape
	body.add_child(collision)
	return body


func _make_visual_box(parent: Node, position_value: Vector3, size_value: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size_value
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _make_label_3d(parent: Node, text_value: String, position_value: Vector3, font_size: int, color: Color, billboard := false) -> Label3D:
	var label := Label3D.new()
	label.text = text_value
	label.position = position_value
	label.font_size = font_size
	label.modulate = color
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.88)
	label.pixel_size = 0.0045
	if billboard:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	parent.add_child(label)
	return label


func _time_or_dash(value: float) -> String:
	return "—" if value <= 0.0 else "%.2f s" % value


func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	return "%02d:%02d:%02d" % [total / 3600, (total % 3600) / 60, total % 60]


func _combat_menu_ratio(stats: Dictionary) -> String:
	var gameplay := float(stats["total_time_playing"])
	var menus := float(stats["total_time_menus"])
	if gameplay <= 0.01:
		return "Menus remain undefeated"
	return "1 : %.1f" % (menus / gameplay)


func _quit_game() -> void:
	save_manager.save_data()
	get_tree().quit()
