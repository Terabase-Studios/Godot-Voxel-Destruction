@tool
extends Resource
class_name VoxelLODSetting

@export_range(1.1, 5.0, 0.1) var lod_factor: float = 1.5
@export var activation_range: int = 0:
	set(value):
		activation_range = value
		activation_range_squared = value * value
@export var preview: bool = false: 
	set(value):
		preview = value
		if value:
			preview_enabled.emit()
		else:
			preview_disabled.emit()
@export var voxel_reduction: float

var activation_range_squared: int

signal preview_enabled
signal preview_disabled
