extends CharacterBody3D
class_name PlayerController

signal shot_fired(collider, hit_point: Vector3)
signal pause_requested

const WeaponScript = preload("res://scripts/gameplay/weapon_controller.gd")

var camera_pivot: Node3D
var camera: Camera3D
var weapon: WeaponController
var controls_enabled := false
var mouse_sensitivity := 0.22
var walk_speed := 4.4
var sprint_speed := 6.2
var gravity := 18.0
var headbob_time := 0.0
var screen_shake := 0.0


func _ready() -> void:
	_build_controller()


func _build_controller() -> void:
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.38
	capsule.height = 1.75
	collider.shape = capsule
	collider.position.y = 0.90
	add_child(collider)

	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.position.y = 1.58
	add_child(camera_pivot)

	camera = Camera3D.new()
	camera.name = "PlayerCamera"
	camera.current = true
	camera.fov = 76.0
	camera.near = 0.05
	camera_pivot.add_child(camera)

	weapon = WeaponScript.new()
	weapon.name = "WeaponController"
	camera.add_child(weapon)
	weapon.setup(camera, self)
	weapon.fired.connect(_on_weapon_fired)


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if weapon != null:
		weapon.enabled = value
	if value:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		pause_requested.emit()
		get_viewport().set_input_as_handled()
		return
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotation.y -= deg_to_rad(event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x -= deg_to_rad(event.relative.y * mouse_sensitivity)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(-70.0), deg_to_rad(70.0))
		weapon.set_sway(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		weapon.fire()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if not controls_enabled:
		velocity.x = move_toward(velocity.x, 0.0, delta * 16.0)
		velocity.z = move_toward(velocity.z, 0.0, delta * 16.0)
		if not is_on_floor():
			velocity.y -= gravity * delta
		move_and_slide()
		return
	var input_vec := Vector2(
		float(Input.is_key_pressed(KEY_D)) - float(Input.is_key_pressed(KEY_A)),
		float(Input.is_key_pressed(KEY_S)) - float(Input.is_key_pressed(KEY_W))
	).normalized()
	var direction := (transform.basis * Vector3(input_vec.x, 0.0, input_vec.y)).normalized()
	var target_speed := sprint_speed if Input.is_key_pressed(KEY_SHIFT) else walk_speed
	velocity.x = move_toward(velocity.x, direction.x * target_speed, delta * 19.0)
	velocity.z = move_toward(velocity.z, direction.z * target_speed, delta * 19.0)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = -0.2
	move_and_slide()
	_update_headbob(delta, Vector2(velocity.x, velocity.z).length())


func _process(delta: float) -> void:
	if screen_shake > 0.0 and camera != null:
		screen_shake = max(0.0, screen_shake - delta * 4.0)
		camera.rotation.z = randf_range(-screen_shake, screen_shake) * 0.018
	else:
		if camera != null:
			camera.rotation.z = lerp(camera.rotation.z, 0.0, min(1.0, delta * 12.0))


func _update_headbob(delta: float, speed: float) -> void:
	if camera == null:
		return
	if speed > 0.5 and is_on_floor():
		headbob_time += delta * speed * 2.1
		camera.position.x = sin(headbob_time) * 0.018
		camera.position.y = abs(cos(headbob_time)) * 0.026
	else:
		camera.position = camera.position.lerp(Vector3.ZERO, min(1.0, delta * 8.0))


func _on_weapon_fired(collider, hit_point: Vector3) -> void:
	screen_shake = 0.7
	shot_fired.emit(collider, hit_point)


func cinematic_shake(amount := 1.0) -> void:
	screen_shake = max(screen_shake, amount)
