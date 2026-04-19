extends Node

@export var enemy_scene: PackedScene = preload("res://characters/enemies/cat_enemy.tscn")
@export var player_path: NodePath = NodePath("../Player")
@export var game_manager_path: NodePath = NodePath("../GameManager")
@export var spawn_parent_path: NodePath = NodePath("..")

@export_group("Spawn Position")
@export var spawn_radius: float = 20.0
@export var spawn_height_offset: float = -0.75

@export_group("Mutation Scaling")
@export var mutation_min: float = 0.5
@export var mutation_max_base: float = 1.2
@export var mutation_max_per_score: float = 0.1

@export_group("Enemy Cap Scaling")
@export var enemy_cap_base: int = 5
@export var enemy_cap_per_score: float = 0.1

@export_group("Spawn Timing")
@export var min_spawn_interval: float = 0.8
@export var max_spawn_interval: float = 3.0

var player: Node3D = null
var game_manager: Node = null
var spawn_parent: Node = null
var score: int = 0
var spawn_timer: float = 0.0

var rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	_resolve_references()
	_connect_game_manager()
	_sync_score_from_game_manager()
	spawn_timer = _get_spawn_delay_for(_get_alive_enemy_count(), _get_current_enemy_cap())


func _process(delta: float) -> void:
	_resolve_references()
	_connect_game_manager()
	_sync_score_from_game_manager()

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

	if not is_instance_valid(game_manager):
		game_manager = get_node_or_null(game_manager_path)


func _connect_game_manager() -> void:
	if not is_instance_valid(game_manager):
		return
	if not game_manager.has_signal("score_changed"):
		return

	var on_score_changed: Callable = Callable(self, "_on_score_changed")
	if game_manager.is_connected("score_changed", on_score_changed):
		return

	game_manager.connect("score_changed", on_score_changed)


func _sync_score_from_game_manager() -> void:
	if not is_instance_valid(game_manager):
		return
	if not game_manager.has_method("get_score"):
		return

	var value: Variant = game_manager.call("get_score")
	if value is int:
		var new_score: int = value
		if new_score != score:
			_on_score_changed(new_score)


func _on_score_changed(new_score: int) -> void:
	score = max(0, new_score)


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
	var scaled_cap: int = enemy_cap_base + int(floor(float(score) * enemy_cap_per_score))
	return max(1, scaled_cap)


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

	var mutation_max: float = mutation_max_base + (float(score) * mutation_max_per_score)
	var clamped_mutation_max: float = max(mutation_min, mutation_max)
	enemy_instance.set("mutation", rng.randf_range(mutation_min, clamped_mutation_max))

	spawn_parent.add_child(enemy_instance)
	if enemy_instance is Node3D:
		(enemy_instance as Node3D).global_position = spawn_position

	return true
