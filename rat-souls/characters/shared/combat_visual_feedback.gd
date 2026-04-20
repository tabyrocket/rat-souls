extends RefCounted

var owner: Node = null
var visual_model: Node3D = null
var star: Node3D = null

var star_rotation_speed: float = 6.0
var hit_flash_duration: float = 0.2
var hit_flash_color: Color = Color(1.0, 0.18, 0.18, 1.0)

var hit_flash_material: StandardMaterial3D = null
var mesh_instances: Array[MeshInstance3D] = []
var hit_flash_request_id: int = 0


func _init(target_owner: Node, target_visual_model: Node3D, target_star: Node3D = null) -> void:
	owner = target_owner
	visual_model = target_visual_model
	star = target_star
	_cache_visual_mesh_instances()
	_setup_hit_flash_material()


func configure_hit_flash(duration: float, color: Color) -> void:
	hit_flash_duration = duration
	hit_flash_color = color
	if hit_flash_material != null:
		hit_flash_material.albedo_color = hit_flash_color


func configure_star_rotation_speed(speed: float) -> void:
	star_rotation_speed = speed


func refresh_visual_model(target_visual_model: Node3D) -> void:
	visual_model = target_visual_model
	_cache_visual_mesh_instances()


func set_star_node(target_star: Node3D) -> void:
	star = target_star


func hide_star() -> void:
	if is_instance_valid(star):
		star.visible = false
		star.rotation = Vector3.ZERO


func show_star(reset_rotation: bool = false) -> void:
	if not is_instance_valid(star):
		return

	if reset_rotation:
		star.rotation = Vector3.ZERO
	star.visible = true


func show_and_spin_star(delta: float) -> void:
	if not is_instance_valid(star):
		return

	star.visible = true
	star.rotate_y(star_rotation_speed * delta)


func trigger_hit_flash() -> void:
	if mesh_instances.is_empty() or hit_flash_duration <= 0.0:
		return
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		return

	hit_flash_request_id += 1
	var request_id: int = hit_flash_request_id

	for mesh_instance in mesh_instances:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = hit_flash_material

	await owner.get_tree().create_timer(hit_flash_duration).timeout
	if request_id != hit_flash_request_id:
		return

	for mesh_instance in mesh_instances:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = null


func _cache_visual_mesh_instances() -> void:
	mesh_instances.clear()
	if not is_instance_valid(visual_model):
		return

	for node in visual_model.find_children("*", "MeshInstance3D", true, false):
		if node is MeshInstance3D:
			mesh_instances.append(node as MeshInstance3D)


func _setup_hit_flash_material() -> void:
	hit_flash_material = StandardMaterial3D.new()
	hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_flash_material.albedo_color = hit_flash_color
	hit_flash_material.disable_receive_shadows = true
