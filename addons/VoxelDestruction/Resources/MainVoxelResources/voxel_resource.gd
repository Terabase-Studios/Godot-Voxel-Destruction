@tool
@icon("voxel_resource.svg")
extends VoxelResourceBase
class_name VoxelResource
## Contains voxel data for the use of a [VoxelObject] along with a debri pool.
@export var colors: PackedColorArray ## Colors used for voxels
@export var color_index: PackedByteArray ## Voxel color index in colors
@export var health: PackedByteArray ## Current life of voxels
@export var positions: PackedVector3Array ## Voxel positions array
@export var positions_dict: Dictionary[Vector3i, int] ## Voxel positions dictionary
@export var vox_chunk_indices: PackedVector3Array ## Stores what chunk a voxel belongs to
@export var chunks: Dictionary[Vector3, PackedVector3Array] ## Stores intact voxel locations within chunks
@export var visible_voxels: PackedVector3Array

## @deprecated: This function is not available for this Resource
func buffer(property, auto_debuffer: bool = true):
	return

## @deprecated: This function is not available for this Resource
func debuffer(property):
	return

## @deprecated: This function is not available for this Resource
func buffer_all():
	return

## @deprecated: This function is not available for this Resource
func debuffer_all():
	return

func _clear():
	colors.clear()
	color_index.clear()
	health.clear()
	positions.clear()
	positions_dict.clear()
	vox_chunk_indices.clear()
	chunks.clear()
	visible_voxels.clear()
	super()
