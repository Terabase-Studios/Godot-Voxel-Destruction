@icon("voxel_state.svg")
extends Resource
class_name VoxelState

@export var version := 0.0 ## Used to automatically repopulate when the addon is updated
@export var unique_voxel_resource: VoxelResource ## Unique voxel resource to prevent two [VoxelObject]s using the same [VoxelResource]
#@export var voxel_mesh: MultiMesh ## New Mesh
@export var colors: PackedColorArray ## Colors used for voxels, overrides colors if dithered
@export var color_index: PackedByteArray ## Voxel color index in colors, overrides colors if dithered
