extends CharacterBody3D

@onready var camera_pivot = $CameraPivot

@export var mouse_sensitivity = 0.002
@export var controller_look_sensitivity: float = 2.0
@export var min_look_angle_deg: float = -60.0
@export var max_look_angle_deg: float = 20.0

var speed = 6.0
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera_pivot.rotation.x -= event.relative.y * mouse_sensitivity
		
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

func _physics_process(delta):
	var look_input = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look_input != Vector2.ZERO:
		rotate_y(-look_input.x * controller_look_sensitivity * delta)
		camera_pivot.rotation.x -= look_input.y * controller_look_sensitivity * delta
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, deg_to_rad(min_look_angle_deg), deg_to_rad(max_look_angle_deg))

	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_back")

	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		# Stop sliding
		velocity.x = 0
		velocity.z = 0

	# Apply gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0

	# Lock rotation
	rotation.x = 0
	rotation.z = 0

	move_and_slide()
