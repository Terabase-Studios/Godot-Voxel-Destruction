extends Camera3D

## Free-fly camera controller
## Movement: W/S = forward/back, A/D = left/right, Q/E = down/up
## Look: hold Right Mouse Button and drag to look around
## Speed: scroll wheel to adjust move speed

@export var move_speed: float = 5.0
@export var look_sensitivity: float = 0.2
@export var speed_scroll_step: float = 1.0
@export var min_speed: float = 0.5
@export var max_speed: float = 50.0

var _looking: bool = false


func _ready() -> void:
	# Make sure input isn't stolen by GUI
	get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	# Right mouse button toggles mouse capture for looking
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_looking = event.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE

		# Scroll wheel adjusts speed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			move_speed = clamp(move_speed + speed_scroll_step, min_speed, max_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			move_speed = clamp(move_speed - speed_scroll_step, min_speed, max_speed)

	# Mouse motion rotates camera while right mouse is held
	if event is InputEventMouseMotion and _looking:
		# Yaw (left/right) — rotate around global Y axis
		rotate_y(deg_to_rad(-event.relative.x * look_sensitivity))
		# Pitch (up/down) — rotate around local X axis, clamped
		var new_pitch = rotation.x + deg_to_rad(-event.relative.y * look_sensitivity)
		rotation.x = clamp(new_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))


func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO

	if Input.is_key_pressed(KEY_W):
		direction -= transform.basis.z  # forward
	if Input.is_key_pressed(KEY_S):
		direction += transform.basis.z  # back
	if Input.is_key_pressed(KEY_A):
		direction -= transform.basis.x  # left
	if Input.is_key_pressed(KEY_D):
		direction += transform.basis.x  # right
	if Input.is_key_pressed(KEY_Q):
		direction -= transform.basis.y  # down
	if Input.is_key_pressed(KEY_E):
		direction += transform.basis.y  # up

	if direction != Vector3.ZERO:
		position += direction.normalized() * move_speed * delta
