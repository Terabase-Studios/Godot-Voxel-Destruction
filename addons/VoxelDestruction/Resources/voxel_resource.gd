@icon("voxel_resource.svg")
extends Resource
class_name VoxelResource

@export var vox_count: int
@export var vox_size: Vector3
@export var positions: PackedVector3Array
@export var positions_dict: Dictionary[Vector3i, int]
@export var colors: PackedColorArray
@export var color_index: PackedByteArray
@export var origin: Vector3i
@export var size: Vector3
