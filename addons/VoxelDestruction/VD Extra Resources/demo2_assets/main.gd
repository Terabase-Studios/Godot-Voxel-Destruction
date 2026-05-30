extends Node3D

# ----------------------------------------------------------------
# Raycast shooter for Godot Voxel Destruction
#
# Left Click  — fire a raycast from the camera to the mouse position.
#               If it hits a VoxelObject, moves the VoxelDamager to
#               the hit point and calls hit().
# ----------------------------------------------------------------

@onready var camera: Camera3D = $Camera3D
@onready var damager: Area3D = $VoxelDamager

# How far the raycast reaches
const RAY_LENGTH := 1000.0
var queue = null

func _ready() -> void:
	get_viewport().gui_release_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			queue = event.position


func _physics_process(delta: float) -> void:
	if queue:
		_shoot_at(queue)
		queue = null


func _shoot_at(mouse_pos: Vector2) -> void:
	var space_state := get_world_3d().direct_space_state

	# Build ray from camera through mouse position
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var ray_end := ray_origin + ray_dir * RAY_LENGTH

	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collide_with_areas = false
	query.collide_with_bodies = true

	var result := space_state.intersect_ray(query)

	if result.is_empty():
		return

	# Check if the hit body belongs to a VoxelObject
	var hit_body := result.collider as Node
	if not hit_body:
		return

	var parent := hit_body.get_parent()
	if not parent or not parent.get_script():
		return

	var script_path: String = parent.get_script().resource_path
	if "voxel_object" not in script_path:
		return

	# Move damager to the hit point and fire
	damager.global_position = result.position
	print("Hitting VoxelObject at: ", result.position)
	damager.hit()
