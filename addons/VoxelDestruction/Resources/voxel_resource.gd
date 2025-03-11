@icon("voxel_resource.svg")
extends Resource
class_name VoxelResource

@export var vox_count: int
@export var vox_size: Vector3
@export var size: Vector3
@export var origin: Vector3i
@export var colors: PackedColorArray
@export var color_index: PackedByteArray
@export var health: PackedByteArray
@export var positions: PackedVector3Array
@export var valid_positions: PackedVector3Array
@export var positions_dict: Dictionary[Vector3i, int]
@export var valid_positions_dict: Dictionary[Vector3i, int]
@export var collision_buffer: Dictionary
var debri_pool = []

# Debri handling
func pool_rigid_bodies(vox_amount) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debri_pool.append(debri)


func get_debri() -> RigidBody3D:
	if debri_pool.size() > 0:
		return debri_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
