extends CharacterBody3D

const COMBAT_VISUAL_FEEDBACK = preload("res://characters/shared/combat_visual_feedback.gd")

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera_3d: Camera3D = $CameraPivot/Camera3D
@onready var dodge_sfx: AudioStreamPlayer3D = $DodgeSFX
@onready var footstep_sfx: AudioStreamPlayer3D = $FootstepSFX
@onready var damaged_sfx: AudioStreamPlayer3D = $DamagedSFX
@onready var visual_model: Node3D = $RatRig
@onready var rat_rig_animation_player: AnimationPlayer = get_node_or_null("RatRig/AnimationPlayer") as AnimationPlayer
@onready var attack_area: Area3D = $AttackArea
@onready var star: Node3D = get_node_or_null("Star") as Node3D

# Camera tuning
@export var mouse_sensitivity: float = 0.002
@export var controller_look_sensitivity: float = 2.0
@export var min_look_angle_deg: float = -60.0
@export var max_look_angle_deg: float = 20.0
@export var lock_on_range: float = 30.0
@export var lock_on_height_offset: float = -2.0
@export var lock_rotation_speed: float = 10.0
@export var lock_camera_look_speed: float = 8.0
@export var lock_switch_stick_threshold: float = 0.7
@export var lock_switch_release_threshold: float = 0.35
@export var lock_switch_mouse_threshold: float = 120.0

# Movement tuning
@export var speed: float = 6.0
@export var player_model_rotation_speed: float = 10.0
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Dodge tuning
@export var dodge_speed: float = 14.0
@export var dodge_duration: float = 0.20
@export var dodge_cooldown: float = 0.60

# Attack tuning
@export var attack_windup_duration: float = 0.4
@export var attack_duration: float = 0.2
@export var attack_cooldown: float = 0.4
@export var attack_damage: float = 2.0

# Stamina tuning
@export var stamina_max: float = 100.0
@export var stamina_attack_cost: float = 25.0
@export var stamina_dodge_cost: float = 25.0
@export var stamina_parry_cost: float = 10.0
@export var stamina_regen_delay: float = 1.0
@export var stamina_regen_rate: float = 50.0

# Parry tuning
@export var parry_duration: float = 1.0

# Damage feedback
@export_group("Damage Feedback")
@export var hit_flash_duration: float = 0.2
@export var hit_flash_color: Color = Color(1.0, 0.18, 0.18, 1.0)

# Startup safety window to avoid scene-transition input/physics carryover.
@export_group("Startup")
@export var startup_physics_freeze_duration: float = 0.12
@export var startup_action_block_duration: float = 0.2

# Runtime state
var camera_offset: Vector3
var stamina: float = 100.0
var stamina_time_since_consume: float = 0.0
var is_dodging: bool = false
var dodge_timer: float = 0.0
var dodge_cooldown_timer: float = 0.0
var dodge_direction: Vector3 = Vector3.ZERO
var is_attacking: bool = false
var is_attack_winding_up: bool = false
var attack_windup_timer: float = 0.0
var attack_timer: float = 0.0
var attack_cooldown_timer: float = 0.0
var is_parrying: bool = false
var parry_timer: float = 0.0
var hit_bodies: Array[Node] = []
var lock_target: Node3D = null
var is_locked_on: bool = false
var lock_switch_axis_ready: bool = true
var lock_switch_mouse_accum_x: float = 0.0
var footstep_timer: float = 0.0
var was_walking: bool = false
var star_rotation_speed: float = 6.0
var combat_visual_feedback

var is_hit: bool = false
var hit_timer: float = 0.0
@export var stun_duration: float = 1.0
@export var death_delay: float = 3.0

# Health
var health: float = 5.0
var is_dead: bool = false
var death_timer: float = 0.0
var death_ui_shown: bool = false
var startup_physics_freeze_timer: float = 0.0
var startup_action_block_timer: float = 0.0


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera_offset = camera_pivot.position
	camera_pivot.top_level = true
	startup_physics_freeze_timer = max(startup_physics_freeze_duration, 0.0)
	startup_action_block_timer = max(startup_action_block_duration, startup_physics_freeze_timer)
	stamina = stamina_max
	combat_visual_feedback = COMBAT_VISUAL_FEEDBACK.new(self, visual_model, star)
	combat_visual_feedback.configure_hit_flash(hit_flash_duration, hit_flash_color)
	combat_visual_feedback.configure_star_rotation_speed(star_rotation_speed)
	combat_visual_feedback.hide_star()
	Input.flush_buffered_events()
	_play_rig_animation("Idle")


func _input(event: InputEvent) -> void:
	if is_dead:
		return
	if _is_startup_actions_blocked():
		return
	if event is InputEventMouseMotion:
		if is_parrying:
			return
		var motion_event: InputEventMouseMotion = event
		if is_locked_on:
			_process_lock_switch_mouse(motion_event.relative.x)
		else:
			_apply_look_input(Vector2(motion_event.relative.x, motion_event.relative.y), mouse_sensitivity)


func _physics_process(delta: float) -> void:
	if is_dead:
		_update_death(delta)
		_lock_rotation_constraints()
		return

	if startup_action_block_timer > 0.0:
		startup_action_block_timer = max(startup_action_block_timer - delta, 0.0)

	if startup_physics_freeze_timer > 0.0:
		startup_physics_freeze_timer = max(startup_physics_freeze_timer - delta, 0.0)
		velocity = Vector3.ZERO
		_update_camera_follow()
		_lock_rotation_constraints()
		return

	_update_timers(delta)
	_handle_lock_on_toggle()
	_validate_lock_target()
	_update_camera_follow()
	_process_controller_look(delta)
	_try_start_parry()

	var direction: Vector3 = _get_move_direction()

	_try_start_attack()
	_update_attack(delta)
	_try_start_dodge(direction)
	_update_horizontal_velocity(direction, delta)
	_update_lock_on_orientation(delta)
	_update_rig_animation(direction)

	_apply_gravity(delta)
	_lock_rotation_constraints()
	move_and_slide()
	_update_footsteps(direction, delta)


func _update_death(delta: float) -> void:
	velocity = Vector3.ZERO
	if not death_ui_shown:
		death_timer -= delta
		if death_timer <= 0.0:
			death_ui_shown = true
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			var ui: Node = _find_ui_node()
			if ui != null and ui.has_method("show_game_over"):
				ui.show_game_over()


func _find_ui_node() -> Node:
	var current_scene: Node = get_tree().current_scene
	if current_scene == null:
		return null

	var direct_ui: Node = current_scene.get_node_or_null("UI")
	if direct_ui != null:
		return direct_ui

	return current_scene.find_child("UI", true, false)


func _play_rig_animation(animation_name: StringName) -> void:
	if rat_rig_animation_player == null:
		return
	if rat_rig_animation_player.current_animation == animation_name and rat_rig_animation_player.is_playing():
		return
	if rat_rig_animation_player.has_animation(animation_name):
		rat_rig_animation_player.play(animation_name)


func _update_rig_animation(direction: Vector3) -> void:
	if is_attack_winding_up or is_attacking:
		_play_rig_animation("Attack")
		return
	if is_dodging:
		_play_rig_animation("Roll")
		return
	if is_parrying:
		_play_rig_animation("Parry")
		return
	if is_hit:
		_play_rig_animation("Stun")
		return

	var is_walking: bool = direction != Vector3.ZERO and is_on_floor()
	if is_walking:
		_play_rig_animation("Walk")
	else:
		_play_rig_animation("Idle")


func _update_timers(delta: float) -> void:
	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			is_parrying = false
			parry_timer = 0.0
			visual_model.scale = Vector3(0.6, 0.6, 0.6)
			print("[Parry] Window ended.")

	if dodge_cooldown_timer > 0.0:
		dodge_cooldown_timer -= delta
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	# Stamina regen: start after `stamina_regen_delay` seconds since last consume.
	stamina_time_since_consume += delta
	if stamina_time_since_consume >= stamina_regen_delay and stamina < stamina_max:
		stamina = min(stamina + stamina_regen_rate * delta, stamina_max)


func _update_camera_follow() -> void:
	camera_pivot.global_position = global_position + camera_offset


func _is_startup_actions_blocked() -> bool:
	return startup_action_block_timer > 0.0


func _handle_lock_on_toggle() -> void:
	if _is_startup_actions_blocked():
		return
	if not Input.is_action_just_pressed("lock_on"):
		return

	if is_locked_on:
		_clear_lock_target()
		return

	_set_lock_target(find_lock_target())


func _validate_lock_target() -> void:
	if is_locked_on and not _is_lock_target_valid():
		var next_target: Node3D = find_lock_target()
		if next_target != null:
			_set_lock_target(next_target)
		else:
			_clear_lock_target()


func _set_lock_target(target: Node3D) -> void:
	lock_target = target
	is_locked_on = target != null
	lock_switch_mouse_accum_x = 0.0
	lock_switch_axis_ready = true


func _clear_lock_target() -> void:
	lock_target = null
	is_locked_on = false
	lock_switch_mouse_accum_x = 0.0
	lock_switch_axis_ready = true


func _update_lock_on_orientation(delta: float) -> void:
	if is_parrying:
		return
	if not _has_lock_target():
		return

	var target_pos: Vector3 = lock_target.global_position + Vector3(0.0, lock_on_height_offset, 0.0)
	var lock_direction: Vector3 = target_pos - global_position
	lock_direction.y = 0.0
	if lock_direction.length_squared() <= 0.000001:
		return

	var target_rotation: float = atan2(lock_direction.x, lock_direction.z)
	rotation.y = lerp_angle(rotation.y, target_rotation, lock_rotation_speed * delta)

	# Smooth camera orientation toward target to avoid lock-on snap.
	var current_transform: Transform3D = camera_pivot.global_transform
	var desired_transform: Transform3D = current_transform.looking_at(target_pos, Vector3.UP)
	var blend: float = clamp(lock_camera_look_speed * delta, 0.0, 1.0)
	current_transform.basis = current_transform.basis.orthonormalized().slerp(desired_transform.basis.orthonormalized(), blend)
	camera_pivot.global_transform = current_transform


func _has_lock_target() -> bool:
	return is_locked_on and _is_lock_target_valid()


func _is_lock_target_valid() -> bool:
	if not is_instance_valid(lock_target):
		return false

	if lock_target.has_method("is_targetable"):
		return lock_target.is_targetable()

	return true


func has_lock_target() -> bool:
	return _has_lock_target()


func get_lock_target() -> Node3D:
	if _has_lock_target():
		return lock_target
	return null


func find_lock_target() -> Node3D:
	var enemies: Array = get_tree().get_nodes_in_group("enemy")

	var closest: Node3D = null
	var closest_dist: float = INF

	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue

		var enemy: Node3D = e
		if enemy.has_method("is_targetable") and not enemy.is_targetable():
			continue

		var dist: float = global_position.distance_to(enemy.global_position)

		if dist < closest_dist and dist <= lock_on_range:
			closest = enemy
			closest_dist = dist

	return closest


func _process_lock_switch_axis(look_x: float) -> void:
	if not _has_lock_target():
		return

	if not lock_switch_axis_ready:
		if abs(look_x) <= lock_switch_release_threshold:
			lock_switch_axis_ready = true
		return

	if look_x >= lock_switch_stick_threshold:
		_try_switch_lock_target(1.0)
		lock_switch_axis_ready = false
	elif look_x <= -lock_switch_stick_threshold:
		_try_switch_lock_target(-1.0)
		lock_switch_axis_ready = false


func _process_lock_switch_mouse(mouse_delta_x: float) -> void:
	if not _has_lock_target():
		return

	lock_switch_mouse_accum_x += mouse_delta_x

	if lock_switch_mouse_accum_x >= lock_switch_mouse_threshold:
		_try_switch_lock_target(1.0)
		lock_switch_mouse_accum_x = 0.0
	elif lock_switch_mouse_accum_x <= -lock_switch_mouse_threshold:
		_try_switch_lock_target(-1.0)
		lock_switch_mouse_accum_x = 0.0


func _try_switch_lock_target(direction_sign: float) -> void:
	if not _has_lock_target():
		return

	var next_target: Node3D = _find_lock_target_in_screen_direction(direction_sign)
	if next_target != null:
		_set_lock_target(next_target)


func _find_lock_target_in_screen_direction(direction_sign: float) -> Node3D:
	if not _has_lock_target() or direction_sign == 0.0:
		return null

	var current_x: float = _get_target_screen_x(lock_target)
	if is_inf(current_x):
		return null

	var enemies: Array = get_tree().get_nodes_in_group("enemy")
	var best_target: Node3D = null
	var best_screen_delta: float = INF
	var best_world_dist: float = INF

	for e in enemies:
		if not is_instance_valid(e) or not (e is Node3D):
			continue

		var enemy: Node3D = e
		if enemy.has_method("is_targetable") and not enemy.is_targetable():
			continue

		if enemy == lock_target:
			continue

		var world_dist: float = global_position.distance_to(enemy.global_position)
		if world_dist > lock_on_range:
			continue

		var candidate_x: float = _get_target_screen_x(enemy)
		if is_inf(candidate_x):
			continue

		var screen_delta: float = candidate_x - current_x
		if direction_sign > 0.0 and screen_delta <= 0.0:
			continue
		if direction_sign < 0.0 and screen_delta >= 0.0:
			continue

		var abs_delta: float = abs(screen_delta)
		if abs_delta < best_screen_delta or (is_equal_approx(abs_delta, best_screen_delta) and world_dist < best_world_dist):
			best_target = enemy
			best_screen_delta = abs_delta
			best_world_dist = world_dist

	return best_target


func _get_target_screen_x(target: Node3D) -> float:
	if camera_3d == null:
		return INF

	var target_pos: Vector3 = target.global_position + Vector3(0.0, lock_on_height_offset, 0.0)
	if camera_3d.is_position_behind(target_pos):
		return INF

	return camera_3d.unproject_position(target_pos).x


func _process_controller_look(delta: float) -> void:
	if is_parrying:
		return
	var look_input: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if is_locked_on:
		_process_lock_switch_axis(look_input.x)
	elif look_input != Vector2.ZERO:
		_apply_look_input(look_input, controller_look_sensitivity * delta)


func _apply_look_input(look_input: Vector2, sensitivity: float) -> void:
	camera_pivot.rotate_y(-look_input.x * sensitivity)
	camera_pivot.rotation.x -= look_input.y * sensitivity
	camera_pivot.rotation.x = clamp(
		camera_pivot.rotation.x,
		deg_to_rad(min_look_angle_deg),
		deg_to_rad(max_look_angle_deg)
	)


func _get_move_direction() -> Vector3:
	if is_parrying:
		return Vector3.ZERO

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO

	if _has_lock_target():
		var lock_forward: Vector3 = _get_lock_forward_direction()
		var lock_right: Vector3 = lock_forward.cross(Vector3.UP).normalized()
		var lock_move: Vector3 = lock_right * input_dir.x + lock_forward * -input_dir.y
		return lock_move.normalized()

	var cam_basis: Basis = camera_pivot.global_transform.basis
	var free_move: Vector3 = cam_basis * Vector3(input_dir.x, 0.0, input_dir.y)
	free_move.y = 0.0
	return free_move.normalized()


func _get_lock_forward_direction() -> Vector3:
	if not _has_lock_target():
		return -global_transform.basis.z

	var to_target: Vector3 = lock_target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.000001:
		return -global_transform.basis.z

	return to_target.normalized()


func _try_start_attack() -> void:
	if is_dead:
		return
	if _is_startup_actions_blocked():
		return
	if is_hit or is_parrying:
		return
	if Input.is_action_just_pressed("attack") and attack_cooldown_timer <= 0.0 and not is_attacking and not is_attack_winding_up:
		# Require enough stamina to perform attack.
		if stamina < stamina_attack_cost:
			print("[Attack] Not enough stamina. Required:", stamina_attack_cost, "Current:", stamina)
			return
		stamina = max(stamina - stamina_attack_cost, 0.0)
		stamina_time_since_consume = 0.0
		hit_bodies.clear()
		is_attack_winding_up = true
		attack_windup_timer = attack_windup_duration
		attack_cooldown_timer = attack_cooldown
		# Visual-only feedback: scale model, not the collision body.
		visual_model.scale = Vector3(0.8, 0.4, 0.8)


func _try_start_parry() -> void:
	if is_dead:
		return
	if _is_startup_actions_blocked():
		return
	if is_hit or is_parrying:
		return
	if not Input.is_action_just_pressed("parry"):
		return

	if stamina < stamina_parry_cost:
		print("[Parry] Not enough stamina. Required:", stamina_parry_cost, "Current:", stamina)
		return

	if is_attacking or is_attack_winding_up:
		print("[Parry] Canceling active attack for parry.")
	if is_dodging:
		print("[Parry] Canceling active dodge for parry.")

	stamina = max(stamina - stamina_parry_cost, 0.0)
	stamina_time_since_consume = 0.0
	is_attack_winding_up = false
	attack_windup_timer = 0.0
	is_attacking = false
	attack_area.monitoring = false
	#visual_model.scale = Vector3(1, 0.8, 0.2)
	hit_bodies.clear()
	is_dodging = false
	is_parrying = true
	parry_timer = parry_duration
	velocity.x = 0.0
	velocity.z = 0.0
	print("[Parry] Started. Window:", parry_duration, "seconds. Stamina:", stamina)


func _update_attack(delta: float) -> void:
	if is_attack_winding_up:
		attack_windup_timer -= delta
		if attack_windup_timer <= 0.0:
			is_attack_winding_up = false
			is_attacking = true
			attack_timer = attack_duration
			attack_area.monitoring = true

	if is_attacking:
		attack_timer -= delta
		if attack_timer <= 0.0:
			visual_model.scale = Vector3(0.6, 0.6, 0.6)
			is_attacking = false
			attack_area.monitoring = false


func _try_start_dodge(direction: Vector3) -> void:
	if is_dead:
		return
	if _is_startup_actions_blocked():
		return
	if is_hit or is_parrying:
		return
	if Input.is_action_just_pressed("dodge") and dodge_cooldown_timer <= 0.0 and not is_dodging and not is_attack_winding_up and not is_attacking:
		# Require enough stamina to dodge.
		if stamina < stamina_dodge_cost:
			print("[Dodge] Not enough stamina. Required:", stamina_dodge_cost, "Current:", stamina)
			return
		stamina = max(stamina - stamina_dodge_cost, 0.0)
		stamina_time_since_consume = 0.0
		is_dodging = true
		dodge_timer = dodge_duration
		dodge_cooldown_timer = dodge_cooldown
		dodge_sfx.play()

		dodge_direction = direction
		if dodge_direction == Vector3.ZERO:
			dodge_direction = _get_idle_dodge_direction()


func _get_idle_dodge_direction() -> Vector3:
	if _has_lock_target():
		return -_get_lock_forward_direction()
	return (camera_pivot.global_transform.basis * Vector3.BACK).normalized()


func _update_horizontal_velocity(direction: Vector3, delta: float) -> void:
	if is_hit:
		if combat_visual_feedback != null:
			combat_visual_feedback.show_and_spin_star(delta)

		hit_timer -= delta
		if is_on_floor():
			velocity.x = move_toward(velocity.x, 0, speed * 2 * delta)
			velocity.z = move_toward(velocity.z, 0, speed * 2 * delta)
		
		if hit_timer <= 0.0:
			is_hit = false
			if combat_visual_feedback != null:
				combat_visual_feedback.hide_star()
	elif is_parrying:
		velocity.x = 0.0
		velocity.z = 0.0
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

		if not _has_lock_target():
			var target_angle: float = atan2(direction.x, direction.z)
			rotation.y = lerp_angle(rotation.y, target_angle, player_model_rotation_speed * delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0


func _update_footsteps(direction: Vector3, delta: float) -> void:
	var is_walking: bool = direction != Vector3.ZERO and is_on_floor() and not is_dodging and not is_hit and not is_parrying

	if not is_walking:
		was_walking = false
		footstep_timer = 0.0
		footstep_sfx.stop()
		return

	if not was_walking:
		_play_random_footstep()
		was_walking = true
		return

	footstep_timer -= delta
	if footstep_timer <= 0.0:
		_play_random_footstep()


func _play_random_footstep() -> void:
	footstep_sfx.play()
	footstep_timer = randf_range(0.5, 0.7)


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
		body.take_damage(attack_damage, self)


func _trigger_hit_flash() -> void:
	if combat_visual_feedback != null:
		combat_visual_feedback.trigger_hit_flash()


func _die() -> void:
	if is_dead:
		return

	is_dead = true
	death_timer = death_delay
	death_ui_shown = false
	is_hit = false
	is_parrying = false
	is_dodging = false
	is_attacking = false
	is_attack_winding_up = false
	attack_area.monitoring = false
	if combat_visual_feedback != null:
		combat_visual_feedback.hide_star()
	visual_model.scale = Vector3(0.6, 0.6, 0.6)
	velocity = Vector3.ZERO
	var scene_root: Node = get_tree().current_scene
	if scene_root != null:
		var bgm: AudioStreamPlayer = scene_root.get_node_or_null("BGM") as AudioStreamPlayer
		if bgm != null:
			bgm.stop()
		var defeat_music: AudioStreamPlayer = scene_root.get_node_or_null("DefeatMusic") as AudioStreamPlayer
		if defeat_music != null:
			defeat_music.play()
	_play_rig_animation("Death")
	print("Player died")


func _face_attack_side_toward(target: Node3D) -> void:
	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	if to_target.length_squared() <= 0.000001:
		return

	# AttackArea sits on local +Z, so this yaw points the striking side toward target.
	rotation.y = atan2(to_target.x, to_target.z)
	print("[Parry] Facing attacker:", target.name)


# Take damage from enemy
func take_damage(amount, source) -> void:
	if is_dead:
		return

	# Check the source of damage
	if source == null or source == self or not source.is_in_group("enemy"):
		return

	if is_parrying:
		print("[Parry] SUCCESS. Blocked", amount, "damage from", source.name)
		print("[Parry] Remaining parry window:", max(parry_timer, 0.0), "seconds")
		if source is Node3D:
			_face_attack_side_toward(source as Node3D)
		else:
			print("[Parry] Could not face attacker because source is not Node3D.")

		if source.has_method("apply_parry_stun"):
			source.apply_parry_stun()
		else:
			print("[Parry] Attacker has no apply_parry_stun() method:", source.name)

		# Exit parry state on successful deflect
		is_parrying = false
		parry_timer = 0.0
		visual_model.scale = Vector3(0.6, 0.6, 0.6)
		print("[Parry] Player exited parry after successful deflect.")
		return

	health -= amount
	if health <= 0:
		_die()
		return

	_trigger_hit_flash()
	damaged_sfx.play()
	print("Player hit! Health:", health)
	
	is_attacking = false
	is_attack_winding_up = false
	attack_windup_timer = 0.0
	attack_area.monitoring = false
	visual_model.scale = Vector3(0.6, 0.6, 0.6)
	is_dodging = false
	is_hit = true
	hit_timer = stun_duration
	velocity = (global_position - source.global_position).normalized() * 10.0
	velocity.y = 1.5
	
