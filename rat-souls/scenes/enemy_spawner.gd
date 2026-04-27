extends Node

@export var enemy_scene: PackedScene = preload("res://characters/enemies/cat_enemy.tscn")
@export var player_path: NodePath = NodePath("../Player")
@export var spawn_parent_path: NodePath = NodePath("..")

@export_group("Spawn Position")
@export var spawn_radius: float = 20.0
@export var spawn_height_offset: float = -0.75

const MUTATION_MIN: float = 0.1
const MUTATION_MAX: float = 4.0
const MUTATION_FAVORED_MIN: float = 0.25
const MUTATION_FAVORED_MAX: float = 1.2
const MUTATION_FAVORED_WEIGHT: float = 0.8

@export_group("Enemy Cap")
@export var enemy_cap_base: int = 5

@export_group("Spawn Timing")
@export var min_spawn_interval: float = 0.8
@export var max_spawn_interval: float = 3.0

var player: Node3D = null
var spawn_parent: Node = null
var spawn_timer: float = 0.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_resolve_references()
	spawn_timer = _get_spawn_delay_for(_get_alive_enemy_count(), _get_current_enemy_cap())


func _process(delta: float) -> void:
	_resolve_references()

	if enemy_scene == null or player == null or spawn_parent == null:
		return

	var alive_count: int = _get_alive_enemy_count()
	var cap: int = _get_current_enemy_cap()
	var target_delay: float = _get_spawn_delay_for(alive_count, cap)

	if alive_count >= cap:
		spawn_timer = target_delay
		return

	if alive_count == 0:
		if _spawn_enemy():
			spawn_timer = _get_spawn_delay_for(_get_alive_enemy_count(), _get_current_enemy_cap())
		else:
			spawn_timer = min_spawn_interval
		return

	spawn_timer = clamp(spawn_timer, 0.0, target_delay)
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return

	if _spawn_enemy():
		spawn_timer = _get_spawn_delay_for(_get_alive_enemy_count(), _get_current_enemy_cap())
	else:
		spawn_timer = min_spawn_interval


func _resolve_references() -> void:
	if not is_instance_valid(player):
		player = get_node_or_null(player_path) as Node3D
		if player == null:
			player = get_tree().get_first_node_in_group("player") as Node3D

	if not is_instance_valid(spawn_parent):
		spawn_parent = get_node_or_null(spawn_parent_path)
		if spawn_parent == null:
			spawn_parent = get_tree().current_scene


func _get_alive_enemy_count() -> int:
	var count: int = 0
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if not (enemy is Node):
			continue

		var enemy_node: Node = enemy
		if enemy_node.is_queued_for_deletion():
			continue
		count += 1
	return count


func _get_current_enemy_cap() -> int:
	return max(1, enemy_cap_base)


func _get_spawn_delay_for(alive_count: int, cap: int) -> float:
	if alive_count <= 0:
		return 0.0

	var safe_cap: int = max(1, cap)
	var fullness: float = clamp(float(alive_count) / float(safe_cap), 0.0, 1.0)
	var lower: float = min(min_spawn_interval, max_spawn_interval)
	var upper: float = max(min_spawn_interval, max_spawn_interval)
	return lerp(lower, upper, fullness)


func _spawn_enemy() -> bool:
	if enemy_scene == null or player == null or spawn_parent == null:
		return false

	var enemy_instance: Node = enemy_scene.instantiate()
	if enemy_instance == null:
		return false

	var angle_radians: float = rng.randf_range(0.0, TAU)
	var radius: float = max(0.0, spawn_radius)
	var offset: Vector3 = Vector3(cos(angle_radians), 0.0, sin(angle_radians)) * radius
	var spawn_position: Vector3 = player.global_position + offset
	spawn_position.y += spawn_height_offset

	enemy_instance.set("mutation", _roll_mutation())

	spawn_parent.add_child(enemy_instance)
	if enemy_instance is Node3D:
		(enemy_instance as Node3D).global_position = spawn_position

	return true


func _roll_mutation() -> float:
	if rng.randf() < MUTATION_FAVORED_WEIGHT:
		return rng.randf_range(MUTATION_FAVORED_MIN, MUTATION_FAVORED_MAX)

	if rng.randf() < 0.5:
		return rng.randf_range(MUTATION_MIN, MUTATION_FAVORED_MIN)

	return rng.randf_range(MUTATION_FAVORED_MAX, MUTATION_MAX)
