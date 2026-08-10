@icon("voxel_resource_base.svg")
extends Resource
class_name VoxelResourceBase
## Contains Basic VoxelData along with a debri pool
##
## @deprecated: Use [VoxelResource] instead.
@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, used to calculate voxel global position.
@export var size: Vector3 ## Estimated size of voxel object as a whole
@export var origin: Vector3i ## Center voxel, used for detecting detached voxel chunks
@export var starting_shapes: Array ## Array of shapes used at VoxelObject start
@export var materials: Dictionary[Color, Color] ## Stores material data such as metalic and emmisives. Cleared at runtime for memory usage.

var _cleared = false


func _clear() -> void:
	_cleared = true
	starting_shapes.clear()
	materials.clear()
