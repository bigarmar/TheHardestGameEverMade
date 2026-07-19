extends Control
class_name WeaponViewmodel

const DUCK_HANDGUN_TEXTURE = preload("res://assets/textures/weapons/duck_handgun.png")
const REAR_SIGHT_LOCAL_POSITION := Vector2(260.0, 197.0)
const MUZZLE_LOCAL_POSITION := Vector2(165.0, 156.0)
const SHOW_AIM_DEBUG := false

var weapon: TextureRect
var base_position := Vector2(60.0, -360.0)
var base_rotation := deg_to_rad(2.1332369)
var elapsed := 0.0
var movement_phase := 0.0
var recoil_strength := 0.0
var flash_time := 0.0
var smoke_time := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	z_index = 8

	weapon = TextureRect.new()
	weapon.name = "DuckHandgun"
	weapon.texture = DUCK_HANDGUN_TEXTURE
	weapon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	weapon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	weapon.set_anchors_preset(Control.PRESET_TOP_LEFT)
	weapon.position = base_position
	weapon.size = Vector2(422.0, 540.0)
	weapon.pivot_offset = Vector2(354.0, 490.0)
	weapon.modulate = Color("#f3f7ff")
	add_child(weapon)


func _fit_viewport() -> void:
	size = get_viewport().get_visible_rect().size


func fire() -> void:
	recoil_strength = 1.0
	flash_time = 0.105
	smoke_time = 0.30
	queue_redraw()


func _process(delta: float) -> void:
	if weapon == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if size != viewport_size:
		size = viewport_size
	elapsed += delta
	recoil_strength = move_toward(recoil_strength, 0.0, delta * 8.0)
	flash_time = max(0.0, flash_time - delta)
	smoke_time = max(0.0, smoke_time - delta)

	var move_input := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	)
	var moving := move_input.length_squared() > 0.01
	if moving:
		movement_phase += delta * (12.0 if Input.is_key_pressed(KEY_SHIFT) else 8.5)
	else:
		movement_phase = lerp(movement_phase, 0.0, min(1.0, delta * 4.0))

	var idle_sway := Vector2(sin(elapsed * 1.15) * 2.8, cos(elapsed * 0.92) * 2.2)
	var movement_bob := Vector2.ZERO
	if moving:
		movement_bob = Vector2(sin(movement_phase) * 7.0, abs(cos(movement_phase)) * 5.5)
	var recoil_offset := Vector2(15.0, 23.0) * recoil_strength

	weapon.position = Vector2(viewport_size.x * 0.5, viewport_size.y) + base_position + idle_sway + movement_bob + recoil_offset
	weapon.scale = Vector2.ONE * (1.0 + recoil_strength * 0.032)
	weapon.rotation = _aligned_rotation_for_current_transform()
	queue_redraw()


func _weapon_local_position(local_position: Vector2) -> Vector2:
	var offset := (local_position - weapon.pivot_offset) * weapon.scale
	return weapon.position + weapon.pivot_offset + offset.rotated(weapon.rotation)


func _muzzle_position() -> Vector2:
	return _weapon_local_position(MUZZLE_LOCAL_POSITION)


func _aligned_rotation_for_current_transform() -> float:
	var rear_from_pivot := (REAR_SIGHT_LOCAL_POSITION - weapon.pivot_offset) * weapon.scale
	var bore_axis := (MUZZLE_LOCAL_POSITION - REAR_SIGHT_LOCAL_POSITION) * weapon.scale
	var pivot_global := weapon.position + weapon.pivot_offset
	var crosshair := get_viewport().get_visible_rect().size * 0.5
	var desired_from_pivot := crosshair - pivot_global
	var alignment_constant := bore_axis.cross(rear_from_pivot)
	var cosine_term := bore_axis.cross(desired_from_pivot)
	var sine_term := -bore_axis.y * desired_from_pivot.y - bore_axis.x * desired_from_pivot.x
	var amplitude := sqrt(cosine_term * cosine_term + sine_term * sine_term)
	if amplitude < 0.001:
		return base_rotation
	var phase := atan2(sine_term, cosine_term)
	var angle_offset := acos(clamp(alignment_constant / amplitude, -1.0, 1.0))
	var candidate_a := phase + angle_offset
	var candidate_b := phase - angle_offset
	if absf(wrapf(candidate_a - base_rotation, -PI, PI)) <= absf(wrapf(candidate_b - base_rotation, -PI, PI)):
		return candidate_a
	return candidate_b


func _draw() -> void:
	if weapon == null:
		return
	var muzzle := _muzzle_position()
	var rear_sight := _weapon_local_position(REAR_SIGHT_LOCAL_POSITION)
	var barrel_direction := (muzzle - rear_sight).normalized()
	var side_direction := barrel_direction.rotated(PI * 0.5)
	if SHOW_AIM_DEBUG:
		var crosshair := get_viewport().get_visible_rect().size * 0.5
		var bore_direction := (muzzle - rear_sight).normalized()
		draw_line(rear_sight, rear_sight + bore_direction * 2000.0, Color("#4ff6ff"), 3.0)
		draw_line(rear_sight, crosshair, Color("#ff4edf"), 3.0)
		draw_circle(rear_sight, 7.0, Color("#ff4edf"))
		draw_circle(muzzle, 7.0, Color("#4ff6ff"))
	if flash_time > 0.0:
		var flash_amount := flash_time / 0.105
		var flare_length := 84.0 * (0.80 + flash_amount * 0.42)
		var flare_width := 38.0 * (0.75 + flash_amount * 0.45)
		draw_rect(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size), Color(1.0, 0.22, 0.05, 0.055 * flash_amount))
		draw_circle(muzzle, 48.0 * flash_amount, Color(1.0, 0.18, 0.02, 0.22 * flash_amount))
		draw_circle(muzzle, 29.0 * flash_amount, Color(1.0, 0.62, 0.10, 0.72 * flash_amount))
		draw_circle(muzzle, 12.0 * flash_amount, Color(1.0, 0.94, 0.52, 0.98 * flash_amount))
		draw_colored_polygon(PackedVector2Array([
			muzzle - side_direction * flare_width + barrel_direction * 2.0,
			muzzle + barrel_direction * flare_length,
			muzzle + side_direction * flare_width + barrel_direction * 2.0
		]), Color(1.0, 0.42, 0.04, 0.84 * flash_amount))
		draw_colored_polygon(PackedVector2Array([
			muzzle - side_direction * 25.0,
			muzzle - barrel_direction * flare_length * 0.45,
			muzzle + side_direction * 25.0
		]), Color(1.0, 0.80, 0.16, 0.58 * flash_amount))

	if smoke_time > 0.0:
		var smoke_amount := smoke_time / 0.30
		var drift := (1.0 - smoke_amount) * 46.0
		for index in range(3):
			var offset := side_direction * ((index - 1) * 9.0 + sin(elapsed * 7.0 + index) * 4.0) + barrel_direction * (drift + index * 9.0)
			draw_circle(muzzle + offset, (8.0 + index * 4.0) * smoke_amount, Color(0.58, 0.64, 0.70, 0.15 * smoke_amount))
