extends Node
class_name voxel_server

var voxel_objects: Array
var voxel_damagers: Array
var total_active_voxels: int
var voxel_memory: Dictionary[VoxelObject, int]
var monitoring = false

func add_monitors():
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", _get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", _get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Voxel Memory (MB)", _get_voxel_object_memory)
	Performance.add_custom_monitor("Voxel Destruction/Memory Per Voxel (B)", _get_voxel_memory)
	monitoring = true


func remove_monitors():
	if not monitoring:
		return
	Performance.remove_custom_monitor("Voxel Destruction/Voxel Objects")
	Performance.remove_custom_monitor("Voxel Destruction/Active Voxels")
	Performance.remove_custom_monitor("Voxel Destruction/Voxel Memory (MB)")
	Performance.remove_custom_monitor("Voxel Destruction/Memory Per Voxel (B)")
	monitoring = false


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

func set_object_memory(object: VoxelObject, processed = {}):
	if not monitoring:
		return
	var memory = _get_object_memory(object)
	voxel_memory[object] = memory
	return memory

func _get_object_memory(object: Object, processed = {}):
	if object in processed:
		return 0  # Avoid double-counting
	processed[object] = true
	var object_memory: int = 0
	for property in object.get_property_list():
		var property_name = property.name
		if object.has_method(property_name):  # Skip methods
			continue
		var value = object.get(property_name)
		if value != null:
			var memory = var_to_bytes_with_objects(value).size()
			if value is VoxelResourceBase:
				memory += var_to_bytes(value._data).size()
				memory += var_to_bytes(value.data_buffer).size()
			elif value is MultiMesh:
				var transform_memory = value.instance_count * 48
				var color_memory = 0
				if value.use_colors:
					color_memory = value.instance_count * 16
				var mesh_memory = 0
				if value.mesh:
					mesh_memory = var_to_bytes(value.mesh).size()

				memory += transform_memory + color_memory + mesh_memory + var_to_bytes(value).size()

			# Recursively account for nested objects or containers
			elif typeof(value) == TYPE_OBJECT and value is Object:
				memory += _get_object_memory(value, processed)
			elif typeof(value) == TYPE_ARRAY:
				for item in value:
					memory += var_to_bytes_with_objects(item).size()
			elif typeof(value) == TYPE_DICTIONARY:
				for key in value.keys():
					memory += var_to_bytes_with_objects(key).size()
					memory += var_to_bytes_with_objects(value[key]).size()
			object_memory += memory
	return object_memory
