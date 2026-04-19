extends CharacterBody3D

const DAMAGE_NUMBER_FONT = preload("res://assets/fonts/Micro5-Regular.ttf")

# Settings
@export var mutation: float = 1.0
const BASE_SCALE: Vector3 = Vector3(0.4, 0.4, 0.4)
const WINDUP_SCALE: Vector3 = Vector3(0.6, 0.2, 0.6)
@export var health: float = 5.0
@export var speed: float = 3.0
@export var attack_range: float = 2.0
@export var attack_damage: float = 1.0
@export var attack_windup: float = 0.6
@export var attack_duration: float = 0.2
@export var attack_cooldown: float = 1.0
@export var stun_duration: float = 1.0
@export var parry_stun_duration: float = 5.0
@export var stunned_damage_multiplier: float = 2.0
@export var separation_weight: float = 2.4
@export var hard_separation_distance: float = 2.0
@export var chase_variation_interval_min: float = 0.45
@export var chase_variation_interval_max: float = 1.1
@export var chase_lateral_strength: float = 0.45
@export var chase_jitter_strength: float = 0.25
@export var separation_boundary_band: float = 0.35
@export var separation_release_padding: float = 0.2
@export var separation_boundary_strafe_strength: float = 0.7
@export var separation_strafe_interval: float = 0.5
@export var separation_smoothing_speed: float = 10.0
@export var damage_number_height: float = 1.45
@export var damage_number_float_distance: float = 0.55
@export var damage_number_lifetime: float = 0.8
@export var damage_number_side_drift: float = 0.12
@export var hit_flash_duration: float = 0.2
@export var hit_flash_color: Color = Color(1.0, 0.18, 0.18, 1.0)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { CHASE, ATTACK, COOLDOWN, HIT, STUNNED }

# Runtime state
var state: State = State.CHASE
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var hit_timer: float = 0.0
var parry_stun_timer: float = 0.0
var hit_bodies: Array[Node] = []
var chase_variation_timer: float = 0.0
var chase_lateral_sign: float = 1.0
var chase_jitter_direction: Vector3 = Vector3.ZERO
var boundary_strafe_active: bool = false
var boundary_strafe_sign: float = 1.0
var boundary_strafe_timer: float = 0.0
var smoothed_separation: Vector3 = Vector3.ZERO
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var star_rotation_speed: float = 6.0
var hit_flash_material: StandardMaterial3D
var cat_mesh_instances: Array[MeshInstance3D] = []
var hit_flash_request_id: int = 0

# References
@onready var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
@onready var attack_area: Area3D = $AttackArea
@onready var separation_area: Area3D = $SeparationArea
@onready var visual_model: Node3D = $CatMesh
@onready var damaged_sfx: AudioStreamPlayer3D = $DamagedSFX
@onready var gong_sfx: AudioStreamPlayer3D = $GongSFX
@onready var star: Node3D = get_node_or_null("Star") as Node3D


func _ready() -> void:
	rng.seed = int(Time.get_ticks_usec()) + get_instance_id()
	_refresh_chase_variation()
	_cache_visual_mesh_instances()
	_setup_hit_flash_material()

	# Apply mutation to visual model scale and to health
	if is_instance_valid(visual_model):
		visual_model.scale = BASE_SCALE * mutation
	# Keep health as a float so fractional HP is preserved after mutation
	health = max(1.0, float(health) * mutation)

	# If this enemy has a child health bar, update its max/value to the
	# mutated health so the bar reflects the post-mutation HP immediately.
	var hb: Node = get_node_or_null("EnemyHealthBar")
	if hb != null:
		if hb.has_method("_apply_health_immediately"):
			hb.health_max = float(health)
			hb.shown_health = float(health)
			hb.max_value = float(health)
			hb.value = float(health)
		else:
			hb.max_value = float(health)
			hb.value = float(health)

	if is_instance_valid(star):
		star.visible = false


func _cache_visual_mesh_instances() -> void:
	cat_mesh_instances.clear()
	if not is_instance_valid(visual_model):
		return

	for node in visual_model.find_children("*", "MeshInstance3D", true, false):
		if node is MeshInstance3D:
			cat_mesh_instances.append(node as MeshInstance3D)


func _setup_hit_flash_material() -> void:
	hit_flash_material = StandardMaterial3D.new()
	hit_flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hit_flash_material.albedo_color = hit_flash_color
	hit_flash_material.disable_receive_shadows = true


func _trigger_hit_flash() -> void:
	if cat_mesh_instances.is_empty() or hit_flash_duration <= 0.0:
		return

	hit_flash_request_id += 1
	var request_id: int = hit_flash_request_id

	for mesh_instance in cat_mesh_instances:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = hit_flash_material

	await get_tree().create_timer(hit_flash_duration).timeout
	if request_id != hit_flash_request_id:
		return

	for mesh_instance in cat_mesh_instances:
		if is_instance_valid(mesh_instance):
			mesh_instance.material_overlay = null


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
		State.STUNNED:
			_state_stunned(delta)
		State.CHASE:
			_state_chase(delta, direction_to_player, distance_to_player)
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


func _state_stunned(delta: float) -> void:
	parry_stun_timer -= delta
	velocity.x = 0.0
	velocity.z = 0.0

	if is_instance_valid(star):
		star.visible = true
		star.rotate_y(star_rotation_speed * delta)

	if parry_stun_timer <= 0.0:
		if is_instance_valid(star):
			star.visible = false
			star.rotation = Vector3.ZERO
		_reset_attack_runtime_state()
		parry_stun_timer = 0.0
		state = State.CHASE
		print("Cat recovered from parry stun.")


func _state_chase(delta: float, direction_to_player: Vector3, distance_to_player: float) -> void:
	if distance_to_player > attack_range:
		var chase_direction: Vector3 = _get_chase_direction(delta, direction_to_player)
		velocity.x = chase_direction.x * speed
		velocity.z = chase_direction.z * speed
	else:
		_enter_attack_state()

	_face_player_horizontally(distance_to_player)


func _state_attack(delta: float) -> void:
	attack_timer -= delta

	if attack_timer > attack_duration:
		attack_area.monitoring = false
		visual_model.scale = WINDUP_SCALE * mutation
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
	_reset_attack_runtime_state(false)
	state = State.ATTACK
	attack_timer = attack_windup
	velocity.x = 0.0
	velocity.z = 0.0
	print("Cat attack started. Windup:", attack_windup, "Active window:", attack_duration)


func _finish_attack_and_enter_cooldown() -> void:
	attack_area.monitoring = false
	visual_model.scale = BASE_SCALE * mutation
	attack_timer = 0.0
	state = State.COOLDOWN
	cooldown_timer = attack_cooldown
	hit_bodies.clear()
	print("Cat attack finished. Entering cooldown:", attack_cooldown)


func _reset_attack_runtime_state(reset_cooldown: bool = true) -> void:
	attack_area.set_deferred("monitoring", false)
	visual_model.scale = BASE_SCALE * mutation
	attack_timer = 0.0
	hit_bodies.clear()
	if reset_cooldown:
		cooldown_timer = 0.0
	print("Cat attack runtime reset. reset_cooldown:", reset_cooldown)


func _is_attack_hit_window_active() -> bool:
	return state == State.ATTACK and attack_area.monitoring and attack_timer > 0.0 and attack_timer <= attack_duration


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


func _get_chase_direction(delta: float, direction_to_player: Vector3) -> Vector3:
	if direction_to_player == Vector3.ZERO:
		return Vector3.ZERO

	chase_variation_timer -= delta
	if chase_variation_timer <= 0.0:
		_refresh_chase_variation()

	var lateral: Vector3 = Vector3(-direction_to_player.z, 0.0, direction_to_player.x)
	var varied_direction: Vector3 = direction_to_player
	varied_direction += lateral * chase_lateral_sign * chase_lateral_strength
	varied_direction += chase_jitter_direction * chase_jitter_strength
	varied_direction = _apply_strict_separation_block(varied_direction)

	var separation_direction: Vector3 = _get_separation_direction(delta, varied_direction)
	if separation_direction != Vector3.ZERO:
		varied_direction += separation_direction * separation_weight

	return varied_direction.normalized()


func _refresh_chase_variation() -> void:
	chase_variation_timer = rng.randf_range(chase_variation_interval_min, chase_variation_interval_max)
	chase_lateral_sign = -1.0 if rng.randf() < 0.5 else 1.0

	var random_angle: float = rng.randf_range(-PI, PI)
	chase_jitter_direction = Vector3(cos(random_angle), 0.0, sin(random_angle))


func _get_separation_direction(delta: float, current_direction: Vector3) -> Vector3:
	var push_direction: Vector3 = Vector3.ZERO
	var closest_distance: float = INF
	var boundary_distance: float = hard_separation_distance + separation_boundary_band

	for body in separation_area.get_overlapping_bodies():
		if body == self or not body.is_in_group("enemy"):
			continue

		if not (body is Node3D):
			continue

		var offset: Vector3 = global_position - body.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001:
			continue
		closest_distance = min(closest_distance, distance)

		var away: Vector3 = offset / distance

		var pressure: float = max(boundary_distance - distance, 0.0) / max(boundary_distance, 0.001)
		push_direction += away * pressure

	if closest_distance < boundary_distance:
		if not boundary_strafe_active:
			boundary_strafe_active = true
			boundary_strafe_sign = -1.0 if rng.randf() < 0.5 else 1.0
			boundary_strafe_timer = separation_strafe_interval
	else:
		if closest_distance > boundary_distance + separation_release_padding:
			boundary_strafe_active = false

	if boundary_strafe_active:
		boundary_strafe_timer -= delta
		if boundary_strafe_timer <= 0.0:
			boundary_strafe_sign *= -1.0
			boundary_strafe_timer = separation_strafe_interval

		var boundary_lateral: Vector3 = Vector3(-current_direction.z, 0.0, current_direction.x)
		if boundary_lateral.length_squared() > 0.000001:
			push_direction += boundary_lateral.normalized() * boundary_strafe_sign * separation_boundary_strafe_strength

	var target_push: Vector3 = Vector3.ZERO
	if push_direction != Vector3.ZERO:
		target_push = push_direction.normalized()

	smoothed_separation = smoothed_separation.move_toward(target_push, separation_smoothing_speed * delta)

	if smoothed_separation == Vector3.ZERO:
		return Vector3.ZERO

	return smoothed_separation


func _apply_strict_separation_block(current_direction: Vector3) -> Vector3:
	var blocked_direction: Vector3 = current_direction

	for body in separation_area.get_overlapping_bodies():
		if body == self or not body.is_in_group("enemy"):
			continue

		if not (body is Node3D):
			continue

		var offset: Vector3 = global_position - body.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001 or distance >= hard_separation_distance:
			continue

		var toward_other: Vector3 = -offset / distance
		var into_other: float = blocked_direction.dot(toward_other)
		if into_other > 0.0:
			blocked_direction -= toward_other * into_other

	return blocked_direction


func _has_valid_player() -> bool:
	return is_instance_valid(player)


func _refresh_player_reference() -> void:
	player = get_tree().get_first_node_in_group("player") as Node3D


func _show_damage_number(amount: float) -> void:
	# Round to nearest integer for display, and skip zero/negative results.
	var display_amount: int = int(round(float(amount)))
	if display_amount <= 0:
		return
	if not is_inside_tree():
		return

	var damage_label: Label3D = Label3D.new()
	damage_label.text = str(display_amount)
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	damage_label.fixed_size = true
	damage_label.no_depth_test = true
	damage_label.font = DAMAGE_NUMBER_FONT
	damage_label.pixel_size = 0.003
	damage_label.font_size = 60
	damage_label.outline_size = 12
	damage_label.outline_modulate = Color(0.05, 0.05, 0.09, 0.95)
	damage_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if display_amount >= 2:
		damage_label.outline_size = 10
	damage_label.top_level = true
	damage_label.scale = Vector3.ONE * (0.54 if display_amount >= 2 else 0.44)

	var parent_for_label: Node = get_parent()
	if parent_for_label == null:
		parent_for_label = get_tree().current_scene
	if parent_for_label == null:
		parent_for_label = self
	parent_for_label.add_child(damage_label)

	var spawn_position: Vector3 = global_position + Vector3(
		rng.randf_range(-0.24, 0.24),
		damage_number_height + rng.randf_range(0.0, 0.12),
		rng.randf_range(-0.16, 0.16)
	)
	damage_label.global_position = spawn_position

	var tween: Tween = damage_label.create_tween()
	var step_count: int = 3
	var step_time: float = damage_number_lifetime / float(step_count)
	var step_height: float = damage_number_float_distance / float(step_count)
	var step_x: float = rng.randf_range(-damage_number_side_drift, damage_number_side_drift) / float(step_count)

	tween.tween_property(
		damage_label,
		"scale",
		Vector3.ONE * (0.62 if display_amount >= 2 else 0.5),
		0.05
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(
		damage_label,
		"modulate:a",
		0.0,
		damage_number_lifetime * 0.55
	).set_delay(damage_number_lifetime * 0.45).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		damage_label,
		"outline_modulate:a",
		0.0,
		damage_number_lifetime * 0.55
	).set_delay(damage_number_lifetime * 0.45).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)

	tween.tween_property(
		damage_label,
		"global_position:y",
		damage_label.global_position.y + step_height,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		damage_label,
		"global_position:x",
		damage_label.global_position.x + step_x,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.tween_property(
		damage_label,
		"global_position:y",
		damage_label.global_position.y + step_height * 2.0,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		damage_label,
		"global_position:x",
		damage_label.global_position.x + step_x * 2.0,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.tween_property(
		damage_label,
		"global_position:y",
		damage_label.global_position.y + step_height * 3.0,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(
		damage_label,
		"global_position:x",
		damage_label.global_position.x + step_x * 3.0,
		step_time
	).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN)
	tween.finished.connect(damage_label.queue_free)


func take_damage(amount, source) -> void:
	if source == null or source == self or not source.is_in_group("player"):
		return

	var damage_multiplier: float = 1.0
	if state == State.STUNNED:
		damage_multiplier = stunned_damage_multiplier
		print("Cat is stunned. Applying damage multiplier:", stunned_damage_multiplier)
	# Use floating-point damage so fractional damage is preserved.
	var final_damage: float = max(0.0, float(amount) * damage_multiplier)
	health -= final_damage
	_show_damage_number(final_damage)
	_trigger_hit_flash()

	damaged_sfx.play()
	print("Cat hit! Base damage:", amount, "Final damage:", final_damage, "Health:", health)

	if health <= 0:
		queue_free()
		return

	if state == State.STUNNED:
		print("Cat was stunned and took damage; exiting stunned state.")
		if is_instance_valid(star):
			star.visible = false
			star.rotation = Vector3.ZERO
		parry_stun_timer = 0.0
		# Wake up from parry-stun and apply normal hit response
		_reset_attack_runtime_state()
		state = State.HIT
		hit_timer = stun_duration
		velocity = (global_position - source.global_position).normalized() * 12.0
		velocity.y = 2.0
		return

	_reset_attack_runtime_state()
	state = State.HIT
	hit_timer = stun_duration
	velocity = (global_position - source.global_position).normalized() * 12.0
	velocity.y = 2.0


func apply_parry_stun(duration: float = -1.0) -> void:
	var resolved_duration: float = parry_stun_duration if duration < 0.0 else duration
	if resolved_duration <= 0.0:
		return

	# Reset any running attack runtime state and apply a small knockback away from the player.
	_reset_attack_runtime_state()
	var knockback_force: float = 12.0 / 5.0
	var dir: Vector3 = Vector3.ZERO
	if _has_valid_player():
		dir = (global_position - player.global_position).normalized()
	# fallback direction if player not found
	if dir.length_squared() <= 0.000001:
		dir = (global_transform.basis.z).normalized()
	velocity = dir * knockback_force
	velocity.y = 1.0
	state = State.STUNNED
	gong_sfx.play()
	parry_stun_timer = resolved_duration
	if is_instance_valid(star):
		star.rotation = Vector3.ZERO
		star.visible = true
	print("Cat parry-stunned for", parry_stun_timer, "seconds. Knockback:", velocity)


func _get_scaled_attack_damage() -> float:
	# Return a floating-point attack damage scaled by mutation.
	# Allow fractional damage (don't round to int).
	return max(0.0, float(attack_damage) * mutation)


func _on_attack_area_body_entered(body: Node) -> void:
	if not _is_attack_hit_window_active():
		return
	if body.has_method("take_damage") and not body in hit_bodies:
		hit_bodies.append(body)
		var dmg: float = _get_scaled_attack_damage()
		body.take_damage(dmg, self)


func _apply_attack_hits() -> void:
	if not _is_attack_hit_window_active():
		return
	var dmg: float = _get_scaled_attack_damage()
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage") and not body in hit_bodies:
			hit_bodies.append(body)
			body.take_damage(dmg, self)
