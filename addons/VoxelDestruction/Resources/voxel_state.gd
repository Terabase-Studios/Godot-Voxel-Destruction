extends Resource
class_name VoxelState

@export var voxel_mesh: MultiMesh ## New Mesh
@export var colors: PackedColorArray ## Colors used for voxels, overrides colors if dithered
@export var color_index: PackedByteArray ## Voxel color index in colors, overrides colors if dithered
