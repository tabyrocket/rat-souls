extends CharacterBody3D

var health: int = 3

func take_damage(amount: int) -> void:
	health -= amount
	print("Cat hit! Health:", health)

	# Despawn once health is depleted.
	if health <= 0:
		queue_free()
