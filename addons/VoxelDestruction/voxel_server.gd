extends Node
class_name voxel_server

var voxel_objects: Array
var voxel_damagers: Array
var total_active_voxels: int
var voxel_memory: Dictionary[VoxelObject, int]

func _ready():
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", _get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", _get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Voxel Memory (MB)", _get_voxel_object_memory)
	Performance.add_custom_monitor("Voxel Destruction/Memory Per Voxel (B)", _get_voxel_memory)

func _get_voxel_object_count():    
	return voxel_objects.size()

func _get_voxel_count():
	return total_active_voxels

func _get_voxel_object_memory():
	var memory = 0
	for mem in voxel_memory.values():
		memory += mem
	return memory/1000000

func _get_voxel_memory():
	if total_active_voxels == 0:
		return 0
	var memory = 0
	for mem in voxel_memory.values():
		memory += mem
	return memory/total_active_voxels

func set_voxel_object_memory(object):
	var object_memory: int = 0
	for property in object.get_property_list():
		var property_name = property.name
		if object.has_method(property_name):  # Skip methods
			continue
		var value = object.get(property_name)
		if value != null:
			var memory = var_to_bytes_with_objects(value).size()
			object_memory += memory
	voxel_memory[object] = object_memory
