@tool
@icon("voxel_resource.svg")
extends Resource
class_name VoxelResource
## Contains VoxelData for the use of a VoxelObject along with a debri pool.
@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, multiply voxel postion by this and add VoxelObject node global position for global voxel position
@export var size: Vector3 ## Estimated size of voxel object as a whole
@export var origin: Vector3i ## Center voxel, used for detecting detached voxel chunks
@export var starting_shapes: Array ## Array of shapes used at VoxelObject start
@export var compression: float ## Size reduction of data compression
@export var colors: PackedColorArray ## Colors used for voxels
@export var color_index: PackedByteArray ## Voxel color index in colors
@export var health: PackedByteArray ## Current life of voxels
@export var positions: PackedVector3Array ## Voxel positions array
@export var valid_positions: PackedVector3Array ## Intact voxel positions array
@export var positions_dict: Dictionary[Vector3i, int] ## Voxel positions dictionary
@export var valid_positions_dict: Dictionary[Vector3i, int] ## Intact voxel positions dictionary
@export var vox_chunk_indices: PackedVector3Array## What chunk a voxel belongs to
@export var chunks: Dictionary[Vector3, PackedVector3Array] ## Stores chunk locations with intact voxel locations

## Pool of debri nodes
var debri_pool = Array()


## This function is not available for this Resource
func buffer(property, auto_debuffer: bool = true):
	return

## This function is not available for this Resource
func debuffer(property):
	return

## This function is not available for this Resource
func buffer_all():
	return

## ## This function is not available for this Resource
func debuffer_all():
	return


## Creates debris and saves them to debri_pool
func pool_rigid_bodies(vox_amount) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debri_pool.append(debri)


## Returns a debri from the debri_pool
func get_debri() -> RigidBody3D:
	if debri_pool.size() > 0:
		return debri_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
