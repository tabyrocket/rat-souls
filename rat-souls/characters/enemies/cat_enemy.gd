extends CharacterBody3D

signal defeated(enemy: Node)

const DAMAGE_NUMBER_FONT = preload("res://assets/fonts/Micro5-Regular.ttf")
const COMBAT_VISUAL_FEEDBACK = preload("res://characters/shared/combat_visual_feedback.gd")

# Base combat settings
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

@export_group("Orbit Movement")
@export var orbit_radius: float = 3.0
@export var orbit_radius_jitter: float = 0.9
@export var orbit_pull_strength: float = 1.35
@export var orbit_tangent_strength: float = 1.5
@export var orbit_spin_speed: float = 1.25
@export var orbit_approach_band: float = 1.0
@export var approach_pull_strength: float = 1.15
@export var retreat_push_strength: float = 1.25
@export var approach_speed_multiplier: float = 1.25
@export var flank_speed_multiplier: float = 1.0
@export var cooldown_speed_multiplier: float = 0.82
@export var slot_update_interval_min: float = 0.35
@export var slot_update_interval_max: float = 0.75
@export var strafe_flip_interval_min: float = 1.2
@export var strafe_flip_interval_max: float = 2.4
@export var strafe_flip_chance: float = 0.3
@export var post_attack_strafe_boost_time: float = 0.75
@export var post_attack_strafe_boost: float = 0.75

@export_group("Crowd Avoidance")
@export var separation_detection_radius: float = 4.3
@export var separation_soft_radius: float = 2.2
@export var separation_hard_radius: float = 1.25
@export var separation_soft_strength: float = 3.0
@export var separation_hard_strength: float = 5.8
@export var spacing_angle_deg: float = 22.0
@export var spacing_strength: float = 1.25
@export var crowd_smoothing_speed: float = 13.0

@export_group("Pack Attack")
@export var max_simultaneous_attackers: int = 2
@export var dynamic_attackers_per_extra: int = 4
@export var max_attackers_cap: int = 6
@export var attack_claim_duration: float = 1.7
@export var attack_start_padding: float = 0.85
@export var attack_lunge_speed: float = 9.0
@export var attack_lunge_damping: float = 18.0

@export_group("Damage Feedback")
@export var damage_number_height: float = 1.45
@export var damage_number_float_distance: float = 0.55
@export var damage_number_lifetime: float = 0.8
@export var damage_number_side_drift: float = 0.12
@export var hit_flash_duration: float = 0.2
@export var hit_flash_color: Color = Color(1.0, 0.18, 0.18, 1.0)

var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

enum State { ORBIT, ATTACK, COOLDOWN, HIT, STUNNED }

# Shared state for all cat instances.
static var _pack_members: Dictionary = {}
static var _attack_claims: Dictionary = {}

# Runtime state
var state: State = State.ORBIT
var attack_timer: float = 0.0
var cooldown_timer: float = 0.0
var hit_timer: float = 0.0
var parry_stun_timer: float = 0.0
var post_attack_strafe_timer: float = 0.0
var hit_bodies: Array[Node] = []

var smoothed_crowd_force: Vector3 = Vector3.ZERO
var orbit_slot_timer: float = 0.0
var strafe_flip_timer: float = 0.0
var strafe_sign: float = 1.0
var orbit_phase_offset: float = 0.0
var orbit_radius_offset: float = 0.0
var slot_angle: float = 0.0
var local_neighbor_count: int = 0

var attack_lunge_applied: bool = false
var attack_lunge_velocity: Vector3 = Vector3.ZERO
var registry_maintenance_timer: float = 0.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var star_rotation_speed: float = 6.0
var combat_visual_feedback
var is_defeated: bool = false

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
	_register_pack_member()
	_cleanup_static_pack()
	_configure_separation_sensor()
	_initialize_orbit_profile()
	combat_visual_feedback = COMBAT_VISUAL_FEEDBACK.new(self, visual_model, star)
	combat_visual_feedback.configure_hit_flash(hit_flash_duration, hit_flash_color)
	combat_visual_feedback.configure_star_rotation_speed(star_rotation_speed)
	combat_visual_feedback.hide_star()

	if is_instance_valid(visual_model):
		visual_model.scale = BASE_SCALE * mutation

	health = max(1.0, float(health) * mutation)

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

func _exit_tree() -> void:
	_release_attack_claim()
	_unregister_pack_member()


func _physics_process(delta: float) -> void:
	if not _has_valid_player():
		_refresh_player_reference()
		if not _has_valid_player():
			return

	if global_position.y < -30.0:
		queue_free()
		return

	registry_maintenance_timer -= delta
	if registry_maintenance_timer <= 0.0:
		_cleanup_static_pack()
		registry_maintenance_timer = 0.5

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
		State.ORBIT:
			_state_orbit(delta, direction_to_player, distance_to_player)
		State.ATTACK:
			_state_attack(delta)
		State.COOLDOWN:
			_state_cooldown(delta, direction_to_player, distance_to_player)

	move_and_slide()


func _state_hit(delta: float) -> void:
	hit_timer -= delta
	if is_on_floor():
		velocity.x = move_toward(velocity.x, 0.0, _get_effective_speed() * 2.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, _get_effective_speed() * 2.0 * delta)

	if hit_timer <= 0.0:
		state = State.ORBIT


func _state_stunned(delta: float) -> void:
	parry_stun_timer -= delta
	velocity.x = 0.0
	velocity.z = 0.0

	if combat_visual_feedback != null:
		combat_visual_feedback.show_and_spin_star(delta)

	if parry_stun_timer <= 0.0:
		if combat_visual_feedback != null:
			combat_visual_feedback.hide_star()
		_reset_attack_runtime_state()
		parry_stun_timer = 0.0
		state = State.ORBIT


func _state_orbit(delta: float, direction_to_player: Vector3, distance_to_player: float) -> void:
	_update_orbit_behavior_timers(delta, distance_to_player)

	if _should_start_attack(distance_to_player):
		_enter_attack_state()
		return

	if direction_to_player == Vector3.ZERO:
		velocity.x = move_toward(velocity.x, 0.0, _get_effective_speed() * delta)
		velocity.z = move_toward(velocity.z, 0.0, _get_effective_speed() * delta)
		return

	var move_direction: Vector3 = _compute_orbit_move_direction(delta, direction_to_player, distance_to_player)
	var target_speed: float = _get_effective_speed() * flank_speed_multiplier
	if distance_to_player > _get_target_orbit_radius() + orbit_approach_band:
		target_speed = _get_effective_speed() * approach_speed_multiplier

	velocity.x = move_direction.x * target_speed
	velocity.z = move_direction.z * target_speed
	_face_move_direction(move_direction, distance_to_player)


func _state_attack(delta: float) -> void:
	attack_timer -= delta
	_face_player_horizontally(_get_to_player_flat().length())

	if attack_timer > attack_duration:
		attack_area.monitoring = false
		visual_model.scale = WINDUP_SCALE * mutation
		velocity.x = move_toward(velocity.x, 0.0, attack_lunge_damping * delta)
		velocity.z = move_toward(velocity.z, 0.0, attack_lunge_damping * delta)
	else:
		attack_area.monitoring = true
		visual_model.scale = BASE_SCALE * mutation
		if not attack_lunge_applied:
			attack_lunge_applied = true
			attack_lunge_velocity = _get_attack_lunge_vector() * attack_lunge_speed

		velocity.x = move_toward(velocity.x, attack_lunge_velocity.x, attack_lunge_damping * delta)
		velocity.z = move_toward(velocity.z, attack_lunge_velocity.z, attack_lunge_damping * delta)
		_apply_attack_hits()

	if attack_timer <= 0.0:
		_finish_attack_and_enter_cooldown()


func _state_cooldown(delta: float, direction_to_player: Vector3, distance_to_player: float) -> void:
	cooldown_timer -= delta
	post_attack_strafe_timer = max(0.0, post_attack_strafe_timer - delta)
	_update_orbit_behavior_timers(delta, distance_to_player)

	if direction_to_player != Vector3.ZERO:
		var move_direction: Vector3 = _compute_orbit_move_direction(delta, direction_to_player, distance_to_player)
		velocity.x = move_direction.x * _get_effective_speed() * cooldown_speed_multiplier
		velocity.z = move_direction.z * _get_effective_speed() * cooldown_speed_multiplier
		_face_move_direction(move_direction, distance_to_player)
	else:
		velocity.x = move_toward(velocity.x, 0.0, _get_effective_speed() * delta)
		velocity.z = move_toward(velocity.z, 0.0, _get_effective_speed() * delta)

	if cooldown_timer <= 0.0:
		state = State.ORBIT


func _compute_orbit_move_direction(delta: float, direction_to_player: Vector3, distance_to_player: float) -> Vector3:
	if direction_to_player == Vector3.ZERO:
		return Vector3.ZERO

	var player_position: Vector3 = player.global_position
	var target_radius: float = _get_target_orbit_radius()
	var time_seconds: float = float(Time.get_ticks_msec()) / 1000.0
	var dynamic_angle: float = slot_angle + strafe_sign * orbit_spin_speed * time_seconds
	var orbit_point: Vector3 = player_position + Vector3(cos(dynamic_angle), 0.0, sin(dynamic_angle)) * target_radius

	var to_orbit: Vector3 = orbit_point - global_position
	to_orbit.y = 0.0

	var radial_from_player: Vector3 = global_position - player_position
	radial_from_player.y = 0.0
	var tangent: Vector3 = Vector3.ZERO
	if radial_from_player.length_squared() > 0.000001:
		tangent = Vector3(-radial_from_player.z, 0.0, radial_from_player.x).normalized() * strafe_sign
	else:
		tangent = Vector3(-direction_to_player.z, 0.0, direction_to_player.x).normalized() * strafe_sign

	var desired: Vector3 = Vector3.ZERO
	if to_orbit.length_squared() > 0.000001:
		desired += to_orbit.normalized() * orbit_pull_strength

	desired += tangent * orbit_tangent_strength

	if distance_to_player > target_radius + orbit_approach_band:
		desired += direction_to_player * approach_pull_strength
	elif distance_to_player < max(attack_range * 0.75, target_radius - 0.9):
		desired -= direction_to_player * retreat_push_strength

	if post_attack_strafe_timer > 0.0:
		desired += tangent * post_attack_strafe_boost

	desired += _get_crowd_force(delta, distance_to_player)

	if desired.length_squared() <= 0.000001:
		return direction_to_player

	return desired.normalized()


func _update_orbit_behavior_timers(delta: float, distance_to_player: float) -> void:
	strafe_flip_timer -= delta
	if strafe_flip_timer <= 0.0:
		if rng.randf() < strafe_flip_chance:
			strafe_sign *= -1.0
		strafe_flip_timer = rng.randf_range(strafe_flip_interval_min, strafe_flip_interval_max)

	orbit_slot_timer -= delta
	if orbit_slot_timer <= 0.0:
		_recalculate_orbit_slot(distance_to_player)
		orbit_slot_timer = rng.randf_range(slot_update_interval_min, slot_update_interval_max)


func _initialize_orbit_profile() -> void:
	strafe_sign = -1.0 if rng.randf() < 0.5 else 1.0
	orbit_phase_offset = rng.randf_range(-PI, PI)
	orbit_radius_offset = rng.randf_range(-orbit_radius_jitter, orbit_radius_jitter)
	slot_angle = orbit_phase_offset
	strafe_flip_timer = rng.randf_range(strafe_flip_interval_min, strafe_flip_interval_max)
	orbit_slot_timer = 0.0


func _recalculate_orbit_slot(distance_to_player: float) -> void:
	if not _has_valid_player():
		return

	var player_position: Vector3 = player.global_position
	var inclusion_radius: float = max(separation_detection_radius * 2.0, orbit_radius * 2.6 + 1.0)
	var nearby_enemies: Array[Node3D] = []

	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D):
			continue

		var enemy_node: Node3D = enemy as Node3D
		if not is_instance_valid(enemy_node) or enemy_node.is_queued_for_deletion():
			continue

		if enemy_node.global_position.distance_to(player_position) <= inclusion_radius:
			nearby_enemies.append(enemy_node)

	nearby_enemies.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.get_instance_id() < b.get_instance_id()
	)

	var slot_count: int = max(1, nearby_enemies.size())
	var slot_index: int = 0
	for i in range(nearby_enemies.size()):
		if nearby_enemies[i] == self:
			slot_index = i
			break

	var base_angle: float = TAU * float(slot_index) / float(slot_count)
	if distance_to_player > orbit_radius * 1.8:
		base_angle = lerp_angle(base_angle, base_angle + strafe_sign * 0.4, 0.25)

	slot_angle = base_angle + orbit_phase_offset


func _get_target_orbit_radius() -> float:
	var density_bonus: float = float(local_neighbor_count) * 0.09
	var resolved_radius: float = orbit_radius + orbit_radius_offset + density_bonus
	return max(attack_range + 0.65, resolved_radius)


func _get_crowd_force(delta: float, distance_to_player: float) -> Vector3:
	var soft_radius: float = max(separation_soft_radius, separation_hard_radius + 0.2)
	var repulsion_force: Vector3 = Vector3.ZERO
	var spacing_force: Vector3 = Vector3.ZERO
	local_neighbor_count = 0

	var self_angle: float = 0.0
	var radial_from_player: Vector3 = Vector3.ZERO
	var tangent_for_spacing: Vector3 = Vector3.ZERO

	if _has_valid_player():
		radial_from_player = global_position - player.global_position
		radial_from_player.y = 0.0
		if radial_from_player.length_squared() > 0.000001:
			tangent_for_spacing = Vector3(-radial_from_player.z, 0.0, radial_from_player.x).normalized()
			self_angle = atan2(radial_from_player.z, radial_from_player.x)

	for body in separation_area.get_overlapping_bodies():
		if body == self or not body.is_in_group("enemy"):
			continue

		if not (body is Node3D):
			continue

		var enemy_body: Node3D = body as Node3D
		var offset: Vector3 = global_position - enemy_body.global_position
		offset.y = 0.0
		var distance: float = offset.length()
		if distance <= 0.001:
			continue

		local_neighbor_count += 1

		var away: Vector3 = offset / distance
		if distance < soft_radius:
			var soft_ratio: float = max(soft_radius - distance, 0.0) / max(soft_radius, 0.001)
			repulsion_force += away * soft_ratio * soft_ratio * separation_soft_strength

		if distance < separation_hard_radius:
			var hard_ratio: float = max(separation_hard_radius - distance, 0.0) / max(separation_hard_radius, 0.001)
			repulsion_force += away * hard_ratio * hard_ratio * separation_hard_strength

		if _has_valid_player() and tangent_for_spacing != Vector3.ZERO and distance_to_player > 0.001:
			var enemy_radial: Vector3 = enemy_body.global_position - player.global_position
			enemy_radial.y = 0.0
			if enemy_radial.length_squared() > 0.000001:
				var enemy_angle: float = atan2(enemy_radial.z, enemy_radial.x)
				var angle_delta: float = wrapf(enemy_angle - self_angle, -PI, PI)
				var spacing_angle: float = deg_to_rad(spacing_angle_deg)
				if abs(angle_delta) < spacing_angle:
					var pressure: float = 1.0 - abs(angle_delta) / max(spacing_angle, 0.001)
					var spread_sign: float = -1.0 if angle_delta >= 0.0 else 1.0
					spacing_force += tangent_for_spacing * spread_sign * pressure * spacing_strength

	var target_force: Vector3 = repulsion_force + spacing_force
	if target_force.length_squared() > 0.000001:
		target_force = target_force.normalized()
	else:
		target_force = Vector3.ZERO

	smoothed_crowd_force = smoothed_crowd_force.move_toward(target_force, crowd_smoothing_speed * delta)
	return smoothed_crowd_force


func _should_start_attack(distance_to_player: float) -> bool:
	if cooldown_timer > 0.0:
		return false

	if distance_to_player > attack_range + attack_start_padding:
		return false

	if _has_attack_claim():
		return distance_to_player <= attack_range + 0.25

	return _try_claim_attack(distance_to_player)


func _enter_attack_state() -> void:
	if not _has_attack_claim() and not _try_claim_attack(_get_to_player_flat().length()):
		return

	_reset_attack_runtime_state(false, false)
	state = State.ATTACK
	attack_timer = max(attack_windup + attack_duration, attack_duration + 0.01)
	attack_lunge_applied = false
	attack_lunge_velocity = Vector3.ZERO
	velocity.x = 0.0
	velocity.z = 0.0


func _finish_attack_and_enter_cooldown() -> void:
	attack_area.monitoring = false
	visual_model.scale = BASE_SCALE * mutation
	attack_timer = 0.0
	attack_lunge_applied = false
	attack_lunge_velocity = Vector3.ZERO
	_release_attack_claim()
	state = State.COOLDOWN
	cooldown_timer = attack_cooldown
	post_attack_strafe_timer = post_attack_strafe_boost_time
	hit_bodies.clear()


func _reset_attack_runtime_state(reset_cooldown: bool = true, release_claim: bool = true) -> void:
	attack_area.set_deferred("monitoring", false)
	visual_model.scale = BASE_SCALE * mutation
	attack_timer = 0.0
	attack_lunge_applied = false
	attack_lunge_velocity = Vector3.ZERO
	hit_bodies.clear()
	if release_claim:
		_release_attack_claim()
	if reset_cooldown:
		cooldown_timer = 0.0


func _get_attack_lunge_vector() -> Vector3:
	var to_player_flat: Vector3 = _get_to_player_flat()
	if to_player_flat.length_squared() > 0.000001:
		return to_player_flat.normalized()

	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return forward.normalized()


func _is_attack_hit_window_active() -> bool:
	return state == State.ATTACK and attack_area.monitoring and attack_timer > 0.0 and attack_timer <= attack_duration


func _has_attack_claim() -> bool:
	var enemy_id: int = get_instance_id()
	if not _attack_claims.has(enemy_id):
		return false

	return int(_attack_claims.get(enemy_id, 0)) > Time.get_ticks_msec()


func _try_claim_attack(distance_to_player: float) -> bool:
	if distance_to_player > attack_range + attack_start_padding:
		return false

	var now_ms: int = Time.get_ticks_msec()
	_cleanup_static_pack(now_ms)

	if _has_attack_claim():
		return true

	if _attack_claims.size() >= _get_effective_max_attackers():
		return false

	var claim_seconds: float = max(attack_claim_duration, attack_windup + attack_duration + 0.1)
	_attack_claims[get_instance_id()] = now_ms + int(claim_seconds * 1000.0)
	return true


func _release_attack_claim() -> void:
	_attack_claims.erase(get_instance_id())


func _get_effective_max_attackers() -> int:
	var base_cap: int = max(1, max_simultaneous_attackers)
	var max_cap: int = max(base_cap, max_attackers_cap)
	var scale_step: int = max(1, dynamic_attackers_per_extra)

	if not _has_valid_player():
		return base_cap

	var nearby_count: int = 0
	var nearby_range: float = orbit_radius * 2.0 + attack_range
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node3D):
			continue

		var enemy_node: Node3D = enemy as Node3D
		if not is_instance_valid(enemy_node) or enemy_node.is_queued_for_deletion():
			continue

		if enemy_node.global_position.distance_to(player.global_position) <= nearby_range:
			nearby_count += 1

	var extra_attackers: int = int(floor(float(max(0, nearby_count - base_cap)) / float(scale_step)))
	return clamp(base_cap + extra_attackers, 1, max_cap)


func _register_pack_member() -> void:
	_pack_members[get_instance_id()] = weakref(self)


func _unregister_pack_member() -> void:
	var enemy_id: int = get_instance_id()
	_pack_members.erase(enemy_id)
	_attack_claims.erase(enemy_id)


func _cleanup_static_pack(now_ms: int = -1) -> void:
	var resolved_now: int = now_ms if now_ms >= 0 else Time.get_ticks_msec()

	for key in _pack_members.keys():
		var ref_value: Variant = _pack_members.get(key)
		if not (ref_value is WeakRef):
			_pack_members.erase(key)
			_attack_claims.erase(key)
			continue

		var enemy_ref: Object = (ref_value as WeakRef).get_ref()
		if enemy_ref == null or not is_instance_valid(enemy_ref):
			_pack_members.erase(key)
			_attack_claims.erase(key)

	for key in _attack_claims.keys():
		var expiry: int = int(_attack_claims.get(key, 0))
		if expiry <= resolved_now or not _pack_members.has(key):
			_attack_claims.erase(key)


func _configure_separation_sensor() -> void:
	var separation_shape_node: CollisionShape3D = separation_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if separation_shape_node == null or separation_shape_node.shape == null:
		return

	if separation_shape_node.shape is SphereShape3D:
		var sphere: SphereShape3D = separation_shape_node.shape as SphereShape3D
		sphere.radius = max(separation_detection_radius, separation_soft_radius + 0.4)


func _trigger_hit_flash() -> void:
	if combat_visual_feedback != null:
		combat_visual_feedback.trigger_hit_flash()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0


func _face_player_horizontally(distance_to_player: float) -> void:
	if distance_to_player <= 0.001 or not _has_valid_player():
		return

	var look_target: Vector3 = player.global_position
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)


func _face_move_direction(move_direction: Vector3, distance_to_player: float) -> void:
	if move_direction.length_squared() <= 0.000001:
		_face_player_horizontally(distance_to_player)
		return

	var look_target: Vector3 = global_position + move_direction
	look_target.y = global_position.y
	look_at(look_target, Vector3.UP)


func _get_to_player_flat() -> Vector3:
	var to_player: Vector3 = player.global_position - global_position
	return Vector3(to_player.x, 0.0, to_player.z)


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
	if is_defeated:
		return

	if source == null or source == self or not source.is_in_group("player"):
		return

	var damage_multiplier: float = 1.0
	if state == State.STUNNED:
		damage_multiplier = stunned_damage_multiplier

	var final_damage: float = max(0.0, float(amount) * damage_multiplier)
	health -= final_damage
	_show_damage_number(final_damage)
	_trigger_hit_flash()
	damaged_sfx.play()

	if health <= 0:
		is_defeated = true
		_release_attack_claim()
		emit_signal("defeated", self)
		queue_free()
		return

	if state == State.STUNNED:
		if combat_visual_feedback != null:
			combat_visual_feedback.hide_star()
		parry_stun_timer = 0.0
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

	_reset_attack_runtime_state()

	var knockback_force: float = 12.0 / 5.0
	var dir: Vector3 = Vector3.ZERO
	if _has_valid_player():
		dir = (global_position - player.global_position).normalized()
	if dir.length_squared() <= 0.000001:
		dir = global_transform.basis.z.normalized()

	velocity = dir * knockback_force
	velocity.y = 1.0
	state = State.STUNNED
	parry_stun_timer = resolved_duration
	gong_sfx.play()

	if combat_visual_feedback != null:
		combat_visual_feedback.show_star(true)


func _get_scaled_attack_damage() -> float:
	return max(0.0, float(attack_damage) * mutation)


func _get_effective_speed() -> float:
	# Higher mutation => lower effective speed. Protect against zero.
	var safe_mutation: float = max(0.0001, float(mutation))
	return float(speed) / safe_mutation


func _on_attack_area_body_entered(body: Node) -> void:
	if not _is_attack_hit_window_active():
		return

	if body.has_method("take_damage") and not body in hit_bodies:
		hit_bodies.append(body)
		body.take_damage(_get_scaled_attack_damage(), self)


func _apply_attack_hits() -> void:
	if not _is_attack_hit_window_active():
		return

	var dmg: float = _get_scaled_attack_damage()
	for body in attack_area.get_overlapping_bodies():
		if body.has_method("take_damage") and not body in hit_bodies:
			hit_bodies.append(body)
			body.take_damage(dmg, self)
