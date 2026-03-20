extends CharacterBody3D

# Settings
@export var speed = 4.0
@export var attack_range = 2.0
@export var attack_damage = 1

@export var attack_windup = 0.6
@export var attack_duration = 0.2
@export var attack_cooldown = 1.0

var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

# Statew
enum State { CHASE, ATTACK, COOLDOWN, HIT }
var state = State.CHASE

var attack_timer = 0.0
var cooldown_timer = 0.0
var hit_timer = 0.0
@export var stun_duration = 1.0

# References
@onready var player = get_tree().get_first_node_in_group("player")
@onready var attack_area = $AttackArea
@onready var visual_model = $MeshInstance3D
@onready var damaged_sfx: AudioStreamPlayer3D = $DamagedSFX

var hit_bodies = []

# Health
var health = 10

func take_damage(amount, source):
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
	velocity.y = 2.0 # Little hop

# Main loop
func _physics_process(delta):

	if player == null:
		return

	# Gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	var to_player = player.global_transform.origin - global_transform.origin
	var to_player_flat = Vector3(to_player.x, 0, to_player.z)
	var distance = to_player_flat.length()
	var direction = Vector3.ZERO
	if distance > 0.001:
		direction = to_player_flat.normalized()

	match state:

		# HIT
		State.HIT:
			hit_timer -= delta
			if is_on_floor():
				velocity.x = move_toward(velocity.x, 0, speed * 2 * delta)
				velocity.z = move_toward(velocity.z, 0, speed * 2 * delta)
			
			if hit_timer <= 0:
				state = State.CHASE

		# CHASE
		State.CHASE:
			if distance > attack_range:
				velocity.x = direction.x * speed
				velocity.z = direction.z * speed
			else:
				# Enter attack
				state = State.ATTACK
				attack_timer = attack_windup
				velocity.x = 0
				velocity.z = 0

			# Face player on the horizontal plane only.
			if distance > 0.001:
				var look_target = player.global_transform.origin
				look_target.y = global_transform.origin.y
				look_at(look_target, Vector3.UP)

		# ATTACK (windup + strike)
		State.ATTACK:
			attack_timer -= delta

			# Telegraph phase
			if attack_timer > attack_duration:
				# Visual feedback
				visual_model.scale = Vector3(1.2, 0.8, 1.2)
			else:
				# Strike phase
				attack_area.monitoring = true
				_apply_attack_hits()

			if attack_timer <= 0:
				attack_area.monitoring = false
				visual_model.scale = Vector3.ONE

				state = State.COOLDOWN
				cooldown_timer = attack_cooldown
				hit_bodies.clear()

		# COOLDOWN
		State.COOLDOWN:
			cooldown_timer -= delta

			if cooldown_timer <= 0:
				state = State.CHASE

	move_and_slide()

# Hit detection
func _on_attack_area_body_entered(body):
	if body.has_method("take_damage") and not body in hit_bodies:
		hit_bodies.append(body)
		body.take_damage(attack_damage, self)


func _apply_attack_hits():
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage") and not body in hit_bodies:
			hit_bodies.append(body)
			body.take_damage(attack_damage, self)
