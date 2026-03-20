extends CharacterBody3D

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var dodge_sfx: AudioStreamPlayer3D = $DodgeSFX
@onready var damaged_sfx: AudioStreamPlayer3D = $DamagedSFX
@onready var visual_model: MeshInstance3D = $MeshInstance3D
@onready var attack_area: Area3D = $AttackArea

# Camera tuning
@export var mouse_sensitivity: float = 0.002
@export var controller_look_sensitivity: float = 2.0
var min_look_angle_deg: float = -60.0
var max_look_angle_deg: float = 20.0

# Movement tuning
var speed: float = 6.0
var player_model_rotation_speed: float = 10.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Dodge tuning
@export var dodge_speed: float = 14.0
@export var dodge_duration: float = 0.20
@export var dodge_cooldown: float = 0.60

# Attack tuning
@export var attack_duration: float = 0.2
@export var attack_cooldown: float = 0.4

# Runtime state
var camera_offset: Vector3
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO
var is_attacking: bool = false
var attack_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var hit_bodies: Array = []

var is_hit: bool = false
var hit_timer: float = 0.0
@export var stun_duration: float = 1.0

# Health
var health = 5


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_offset = camera_pivot.position
	camera_pivot.top_level = true


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_apply_look_input(Vector2(event.relative.x, event.relative.y), mouse_sensitivity)


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_camera_follow()
	_process_controller_look(delta)

	var cam_basis: Basis = camera_pivot.global_transform.basis
	var direction: Vector3 = _get_move_direction(cam_basis)

	_try_start_attack()
	_update_attack(delta)
	_try_start_dodge(direction, cam_basis)
	_update_horizontal_velocity(direction, delta)

	_apply_gravity(delta)
	_lock_rotation_constraints()
	move_and_slide()


func _update_timers(delta: float) -> void:
	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta


func _update_camera_follow() -> void:
	camera_pivot.global_position = global_position + camera_offset


func _process_controller_look(delta: float) -> void:
	var look_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input != Vector2.ZERO:
		_apply_look_input(look_input, controller_look_sensitivity * delta)


func _apply_look_input(look_input: Vector2, sensitivity: float) -> void:
	camera_pivot.rotate_y(-look_input.x * sensitivity)
	camera_pivot.rotation.x -= look_input.y * sensitivity
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x,
		deg_to_rad(min_look_angle_deg),
		deg_to_rad(max_look_angle_deg)
	)


func _get_move_direction(cam_basis: Basis) -> Vector3:
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	direction.y = 0.0
	return direction.normalized()


func _try_start_attack() -> void:
	if is_hit:
		return
	if Input.is_action_just_pressed("attack") and attack_cooldown_timer <= 0.0 and not is_attacking:
		hit_bodies.clear()
		is_attacking = true
		attack_timer = attack_duration
		attack_cooldown_timer = attack_cooldown
		attack_area.monitoring = true
		# Visual-only feedback: scale model, not the collision body.
		visual_model.scale = Vector3(1.2, 0.8, 1.2)


func _update_attack(delta: float) -> void:
	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			visual_model.scale = Vector3.ONE
			is_attacking = false
			attack_area.monitoring = false


func _try_start_dodge(direction: Vector3, cam_basis: Basis) -> void:
	if is_hit:
		return
	if Input.is_action_just_pressed("dodge") and dodge_cooldown_timer <= 0.0 and not is_dodging:
		is_dodging = true
		dodge_timer = dodge_duration
		dodge_cooldown_timer = dodge_cooldown
		dodge_sfx.play()

		dodge_direction = direction
		if dodge_direction == Vector3.ZERO:
			# If idle, dodge backward relative to camera.
			dodge_direction = (cam_basis * Vector3.BACK).normalized()


func _update_horizontal_velocity(direction: Vector3, delta: float) -> void:
	if is_hit:
		hit_timer -= delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, speed * 2 * delta)
			velocity.z = move_toward(velocity.z, 0, speed * 2 * delta)
		
		if hit_timer <= 0.0:
			is_hit = false
	elif is_dodging:
		dodge_timer -= delta
		velocity.x = dodge_direction.x * dodge_speed
		velocity.z = dodge_direction.z * dodge_speed

		var look_target: Vector3 = global_position - dodge_direction
		if not global_position.is_equal_approx(look_target):
			look_at(look_target, Vector3.UP)

		if dodge_timer <= 0.0:
			is_dodging = false
	elif direction != Vector3.ZERO:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed

		var target_angle: float = atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, player_model_rotation_speed * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _lock_rotation_constraints() -> void:
	rotation.x = 0.0
	rotation.z = 0.0


func _on_attack_area_body_entered(body: Node3D) -> void:
	if is_attacking and body.has_method("take_damage") and not body in hit_bodies:
		hit_bodies.append(body)
		body.take_damage(1, self)


# Take damage from enemy
func take_damage(amount, source):
	# Check the source of damage
	if source == null or source == self or not source.is_in_group("enemy"):
		return
	health -= amount
	damaged_sfx.play()
	print("Player hit! Health:", health)
	
	is_attacking = false
	attack_area.monitoring = false
	visual_model.scale = Vector3.ONE
	is_dodging = false
	is_hit = true
	hit_timer = stun_duration
	velocity = (global_position - source.global_position).normalized() * 10.0
	velocity.y = 1.5
	
	if health <= 0:
		print("Player died")
