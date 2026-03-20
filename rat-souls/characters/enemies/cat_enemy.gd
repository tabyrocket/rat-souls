extends CharacterBody3D

# Settings
@export var health: int = 5
@export var speed: float = 3.0
@export var attack_range: float = 2.0
@export var attack_damage: int = 1
@export var attack_windup: float = 0.6
@export var attack_duration: float = 0.2
@export var attack_cooldown: float = 1.0
@export var stun_duration: float = 1.0

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { CHASE, ATTACK, COOLDOWN, HIT }

# Runtime state
var state: State = State.CHASE
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var hit_timer: float = 0.0
var hit_bodies: Array[Node] = []

# References
@onready var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
@onready var attack_area: Area3D = $AttackArea
@onready var visual_model: MeshInstance3D = $MeshInstance3D
@onready var damaged_sfx: AudioStreamPlayer3D = $DamagedSFX


func _physics_process(delta: float) -> void:
	if not _has_valid_player():
		_refresh_player_reference()
		if not _has_valid_player():
			return

	_apply_gravity(delta)

	var to_player_flat: Vector3 = _get_to_player_flat()
	var distance_to_player: float = to_player_flat.length()
	var direction_to_player: Vector3 = Vector3.ZERO
	if distance_to_player > 0.001:
		direction_to_player = to_player_flat.normalized()

	match state:
		State.HIT:
			_state_hit(delta)
		State.CHASE:
			_state_chase(direction_to_player, distance_to_player)
		State.ATTACK:
			_state_attack(delta)
		State.COOLDOWN:
			_state_cooldown(delta)

	move_and_slide()


func _state_hit(delta: float) -> void:
	hit_timer -= delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, speed * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, speed * 2.0 * delta)

	if hit_timer <= 0.0:
		state = State.CHASE


func _state_chase(direction_to_player: Vector3, distance_to_player: float) -> void:
	if distance_to_player > attack_range:
		velocity.x = direction_to_player.x * speed
		velocity.z = direction_to_player.z * speed
	else:
		_enter_attack_state()

	_face_player_horizontally(distance_to_player)


func _state_attack(delta: float) -> void:
	attack_timer -= delta

	if attack_timer > attack_duration:
		visual_model.scale = Vector3(1.2, 0.8, 1.2)
	else:
		attack_area.monitoring = true
		_apply_attack_hits()

	if attack_timer <= 0.0:
		_finish_attack_and_enter_cooldown()


func _state_cooldown(delta: float) -> void:
	cooldown_timer -= delta
	if cooldown_timer <= 0.0:
		state = State.CHASE


func _enter_attack_state() -> void:
	state = State.ATTACK
	attack_timer = attack_windup
	velocity.x = 0.0
	velocity.z = 0.0


func _finish_attack_and_enter_cooldown() -> void:
	attack_area.monitoring = false
	visual_model.scale = Vector3.ONE
	state = State.COOLDOWN
	cooldown_timer = attack_cooldown
	hit_bodies.clear()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _face_player_horizontally(distance_to_player: float) -> void:
	if distance_to_player <= 0.001 or not _has_valid_player():
		return

	var look_target: Vector3 = player.global_transform.origin
	look_target.y = global_transform.origin.y
	look_at(look_target, Vector3.UP)


func _get_to_player_flat() -> Vector3:
	var to_player: Vector3 = player.global_transform.origin - global_transform.origin
	return Vector3(to_player.x, 0.0, to_player.z)


func _has_valid_player() -> bool:
	return is_instance_valid(player)


func _refresh_player_reference() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D


func take_damage(amount, source) -> void:
	if source == null or source == self or not source.is_in_group("player"):
		return

	health -= amount
	damaged_sfx.play()
	print("Cat hit! Health:", health)

	if health <= 0:
		queue_free()
		return

	attack_area.monitoring = false
	visual_model.scale = Vector3.ONE
	hit_bodies.clear()
	state = State.HIT
	hit_timer = stun_duration
	velocity = (global_position - source.global_position).normalized() * 12.0
	velocity.y = 2.0


func _on_attack_area_body_entered(body: Node) -> void:
	if body.has_method("take_damage") and not body in hit_bodies:
		hit_bodies.append(body)
		body.take_damage(attack_damage, self)


func _apply_attack_hits() -> void:
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage") and not body in hit_bodies:
			hit_bodies.append(body)
			body.take_damage(attack_damage, self)
