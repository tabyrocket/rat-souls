extends Node

signal score_changed(new_score: int)

@export var points_per_enemy_kill: int = 1
@export var score_label_path: NodePath = NodePath("../UI/ColorRect/ScoreLabel")

var score: int = 0
var score_label: Label = null


func _ready() -> void:
	add_to_group("game_manager")
	score_label = get_node_or_null(score_label_path) as Label
	_update_score_label()
	emit_signal("score_changed", score)
	_connect_existing_enemies()

	if not get_tree().node_added.is_connected(_on_tree_node_added):
		get_tree().node_added.connect(_on_tree_node_added)


func _connect_existing_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemy"):
		_connect_enemy_if_supported(enemy)


func _on_tree_node_added(node: Node) -> void:
	if node.is_in_group("enemy"):
		_connect_enemy_if_supported(node)


func _connect_enemy_if_supported(enemy: Node) -> void:
	if not enemy.has_signal("defeated"):
		return

	var on_enemy_defeated: Callable = Callable(self, "_on_enemy_defeated")
	if enemy.is_connected("defeated", on_enemy_defeated):
		return

	enemy.connect("defeated", on_enemy_defeated)


func _on_enemy_defeated(_enemy: Node) -> void:
	score += points_per_enemy_kill
	_update_score_label()
	emit_signal("score_changed", score)


func _update_score_label() -> void:
	if score_label == null:
		return
	score_label.text = str(score)


func get_score() -> int:
	return score
