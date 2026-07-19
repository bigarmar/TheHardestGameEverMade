extends Node3D
class_name WeaponController

signal fired(collider, hit_point: Vector3)

var camera: Camera3D
var owner_body: CollisionObject3D
var muzzle_light: OmniLight3D
var recoil_tween: Tween
var base_position := Vector3(0.40, -0.33, -0.72)
var sway_target := Vector2.ZERO
var sway_current := Vector2.ZERO
var enabled := true


func setup(camera_node: Camera3D, body: CollisionObject3D) -> void:
	camera = camera_node
	owner_body = body
	_build_weapon()


func _build_weapon() -> void:
	# The weapon art itself is a HUD viewmodel so it stays sharp and readable.
	# This node retains the existing firing raycast and contributes a brief world light.
	position = base_position
	muzzle_light = OmniLight3D.new()
	muzzle_light.light_color = Color("#ffb82e")
	muzzle_light.light_energy = 0.0
	muzzle_light.omni_range = 4.5
	muzzle_light.position = Vector3(0.0, 0.06, -0.94)
	add_child(muzzle_light)


func _process(delta: float) -> void:
	if not enabled:
		return
	sway_current = sway_current.lerp(sway_target, min(1.0, delta * 9.0))
	rotation.x = -sway_current.y * 0.010
	rotation.y = -sway_current.x * 0.012
	var idle := Vector3(sin(Time.get_ticks_msec() * 0.0024) * 0.006, cos(Time.get_ticks_msec() * 0.0031) * 0.008, 0.0)
	position = position.lerp(base_position + idle, min(1.0, delta * 8.0))


func set_sway(relative_motion: Vector2) -> void:
	sway_target = (sway_target + relative_motion).limit_length(35.0)
	var tween := create_tween()
	tween.tween_property(self, "sway_target", Vector2.ZERO, 0.16)


func fire() -> void:
	if not enabled or camera == null:
		return
	_show_muzzle_flash()
	_recoil()
	var origin := camera.global_position
	var destination := origin + (-camera.global_transform.basis.z * 100.0)
	var query := PhysicsRayQueryParameters3D.create(origin, destination)
	if owner_body != null:
		query.exclude = [owner_body.get_rid()]
	query.collide_with_areas = true
	var result := get_world_3d().direct_space_state.intersect_ray(query)
	var collider = result.get("collider", null)
	var point: Vector3 = result.get("position", destination)
	fired.emit(collider, point)
	if collider != null and collider.has_method("hit"):
		collider.hit(point)


func _show_muzzle_flash() -> void:
	if muzzle_light == null:
		return
	muzzle_light.light_energy = 6.5
	var tween := create_tween()
	tween.tween_property(muzzle_light, "light_energy", 0.0, 0.07)


func _recoil() -> void:
	if recoil_tween != null and recoil_tween.is_valid():
		recoil_tween.kill()
	position = base_position + Vector3(0.0, 0.035, 0.16)
	rotation.x = deg_to_rad(7.0)
	recoil_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	recoil_tween.set_parallel(true)
	recoil_tween.tween_property(self, "position", base_position, 0.16)
	recoil_tween.tween_property(self, "rotation:x", 0.0, 0.18)
