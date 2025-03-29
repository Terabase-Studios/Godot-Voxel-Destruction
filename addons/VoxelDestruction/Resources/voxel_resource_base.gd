@icon("voxel_resource_base.svg")
extends Resource
class_name VoxelResourceBase
## Contains Basic VoxelData along with a debri pool
##
## @deprecated: Use [VoxelResource] instead.
@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, multiply voxel postion by this and add VoxelObject node global position for global voxel position
@export var size: Vector3 ## Estimated size of voxel object as a whole
@export var origin: Vector3i ## Center voxel, used for detecting detached voxel chunks
@export var starting_shapes: Array ## Array of shapes used at VoxelObject start

## Pool of debris nodes
var debris_pool: Array[RigidBody3D]

## Creates debris and saves them to debri_pool
func pool_rigid_bodies(vox_amount) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debris_pool.append(debri)


## Returns a debri from the debri_pool
func get_debri() -> RigidBody3D:
	if debris_pool.size() > 0:
		return debris_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
