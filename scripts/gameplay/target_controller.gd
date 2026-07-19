extends StaticBody3D
class_name TargetController

signal destroyed

var is_destroyed := false
var spark_particles: GPUParticles3D


func configure() -> void:
	add_to_group("campaign_target")
	_build_target()


func _build_target() -> void:
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 3.2, 0.50)
	collision.shape = box
	add_child(collision)

	var backing := MeshInstance3D.new()
	var backing_mesh := CylinderMesh.new()
	backing_mesh.top_radius = 1.62
	backing_mesh.bottom_radius = 1.62
	backing_mesh.height = 0.34
	backing.mesh = backing_mesh
	backing.rotation_degrees.x = 90.0
	backing.material_override = _material(Color("#252c32"), 0.88, 0.23)
	add_child(backing)

	var rings := [
		[1.42, Color("#6b1010")],
		[1.08, Color("#ded7c2")],
		[0.74, Color("#8e1714")],
		[0.38, Color("#ff3d25")]
	]
	var z_offset := 0.20
	for ring_data in rings:
		var ring := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = ring_data[0]
		mesh.bottom_radius = ring_data[0]
		mesh.height = 0.055
		ring.mesh = mesh
		ring.rotation_degrees.x = 90.0
		ring.position.z = z_offset
		ring.material_override = _emissive_material(ring_data[1], 1.8 if ring_data[0] < 0.5 else 0.35)
		add_child(ring)
		z_offset += 0.04

	for side in [-1.0, 1.0]:
		var support := MeshInstance3D.new()
		var support_mesh := BoxMesh.new()
		support_mesh.size = Vector3(0.18, 2.8, 0.18)
		support.mesh = support_mesh
		support.position = Vector3(side * 1.15, -2.75, -0.15)
		support.material_override = _material(Color("#171c20"), 0.92, 0.24)
		add_child(support)

	spark_particles = GPUParticles3D.new()
	spark_particles.name = "ImpactSparks"
	spark_particles.amount = 90
	spark_particles.lifetime = 0.85
	spark_particles.one_shot = true
	spark_particles.explosiveness = 0.95
	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.25, 1.0)
	process.spread = 52.0
	process.initial_velocity_min = 3.0
	process.initial_velocity_max = 8.0
	process.gravity = Vector3(0.0, -8.0, 0.0)
	process.color = Color("#ffad2e")
	spark_particles.process_material = process
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.025, 0.025, 0.22)
	spark_mesh.material = _emissive_material(Color("#ffb32c"), 7.0)
	spark_particles.draw_pass_1 = spark_mesh
	spark_particles.position.z = 0.42
	add_child(spark_particles)


func hit(_point: Vector3) -> void:
	if is_destroyed:
		return
	is_destroyed = true
	for child in get_children():
		if child is CollisionShape3D:
			child.set_deferred("disabled", true)
	spark_particles.emitting = true
	destroyed.emit()
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.set_parallel(true)
	tween.tween_property(self, "rotation:x", deg_to_rad(-82.0), 0.72)
	tween.tween_property(self, "position:y", position.y - 1.15, 0.72)
	tween.tween_property(self, "scale", Vector3(1.1, 0.85, 1.1), 0.45)


func _material(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material


func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var material := _material(color, 0.45, 0.28)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material

