@tool
@icon("voxel_lod_setting.svg")
extends Resource
class_name VoxelLODSetting
## Used in [VoxelLODAddon] to define an LOD. [br]
## The [VoxelObject] must be (Re)populated for LOD changes to take affect.

## The amount to compress the [VoxelMultiMesh].
@export_range(1.1, 5.0, 0.1) var lod_factor: float = 1.5
## The range at which to activate this lod. [br] 
## The [VoxelLODSetting] with the highest [b]activation_range[/b] is checked/applied first.
@export var activation_range: int = 0:
	set(value):
		activation_range = value
		activation_range_squared = value * value

## Temporarly set the [VoxelObject]'s [VoxelMultiMesh] to this LOD. [br]
## Only one [VoxelLODSetting] can be previewed per [VoxelLODAddon].
@export var preview: bool = false: 
	set(value):
		preview = value
		if value:
			preview_enabled.emit()
		else:
			preview_disabled.emit()

## Shows the percent of voxels trimmed for this LOD. Modifying this has no effect.
@export var voxel_reduction: float

## Used by [VoxelLODAddon] for faster distance checks.
var activation_range_squared: int

## Emmited when [member preview] is enabled.
signal preview_enabled
## Emmited when [member preview] is disabled.
signal preview_disabled
