@tool
@icon("voxel_resource.svg")
extends VoxelResourceBase
class_name VoxelResource
## Contains VoxelData for the use of a VoxelObject along with a debri pool.
@export var colors: PackedColorArray ## Colors used for voxels
@export var color_index: PackedByteArray ## Voxel color index in colors
@export var health: PackedByteArray ## Current life of voxels
@export var positions: PackedVector3Array ## Voxel positions array
@export var valid_positions: PackedVector3Array ## Intact voxel positions array
@export var positions_dict: Dictionary[Vector3i, int] ## Voxel positions dictionary
@export var valid_positions_dict: Dictionary[Vector3i, int] ## Intact voxel positions dictionary
@export var vox_chunk_indices: PackedVector3Array ## What chunk a voxel belongs to
@export var chunks: Dictionary[Vector3, PackedVector3Array] ## Stores chunk locations with intact voxel locations


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
