extends Node
class_name voxel_server
## Keeps track of data used in monitors

## Array of [VoxelObject]s
var voxel_objects: Array
## Array of [VoxelDamager]s
var voxel_damagers: Array
## Amount of intact voxels
var total_active_voxels: int
## Ammount of shapes used in [VoxelObject]s
var shape_count: int


func _ready():
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Shape Count", get_shape_count)


## Returns [member voxel_server.voxel_objects] size
func get_voxel_object_count():    
	return voxel_objects.size()

## Returns [member voxel_server.total_active_voxels]
func get_voxel_count():
	return total_active_voxels

## Returns [member voxel_server.shape_count]
func get_shape_count():
	return shape_count
