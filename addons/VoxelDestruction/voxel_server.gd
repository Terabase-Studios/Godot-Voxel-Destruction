extends Node
class_name voxel_server
## Keeps track of data used in monitors

## Array of [VoxelObject]s
var voxel_objects: Array[VoxelObject]
## Array of [VoxelDamager]s
var voxel_damagers: Array[VoxelDamager]
## Amount of intact voxels
var total_active_voxels: int
## Ammount of shapes used in [VoxelObject]s
var shape_count: int

func _ready():
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Visible Voxels", get_visible_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Shape Count", get_shape_count)
	Performance.add_custom_monitor("Voxel Destruction/LOD Hidden Voxels", get_lod_hidden_voxels)



## Returns [member voxel_server.voxel_objects] size
func get_voxel_object_count():    
	return voxel_objects.size()

## Returns [member voxel_server.total_active_voxels]
func get_voxel_count():
	return total_active_voxels

## Returns [VoxelObject]s [member MultiMesh.visible_instance_count]
func get_visible_voxel_count():
	var visible_voxel_count = 0
	for object in voxel_objects:
		visible_voxel_count += object.multimesh.visible_instance_count
	return visible_voxel_count

## Returns [member voxel_server.shape_count]
func get_shape_count():
	return shape_count

## Returns Voxels hidden by [VoxelLODAddon] that would otherwise be visible
func get_lod_hidden_voxels():
	var hidden_voxels: int = 0
	for object in voxel_objects:
		if object.lod_addon:
			hidden_voxels += object.lod_addon.hidden_voxels
	return hidden_voxels
