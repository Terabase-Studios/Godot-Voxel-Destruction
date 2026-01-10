@tool
extends Resource
class_name LODVoxelResource
## Contains voxel data for the use of a [VoxelLod].
@export var voxel_reduction: float
@export var colors: PackedColorArray ## Colors used for voxels
@export var color_index: PackedByteArray ## Voxel color index in colors
@export var positions: PackedVector3Array ## Voxel positions array
@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, multiply voxel postion by this and add VoxelObject node global position for global voxel position
