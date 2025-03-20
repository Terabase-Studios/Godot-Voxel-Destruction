@tool
@icon("compact_voxel_resource.svg")
extends Resource
class_name CompactVoxelResource
## Contains VoxelData for the use of a VoxelObject along with a debri pool. Stores scalable voxel data in a compressed binary array.
##
## Whenever a large array or dictionary is retrieved or set and a compressed/decompressed DUPLICATE is returned.
## These variables can be buffered allowing them to be accessed and modified as a normal variable with little performance loss
##
## @experimental
const BUFFER_LIFETIME = 1 ## Time since last buffered befor a variable is automaticly debuffered.
const COMPRESSION_MODE = 2 ## Argument passed to compress()/decompress()

@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, multiply voxel postion by this and add VoxelObject node global position for global voxel position
@export var size: Vector3 ## Estimated size of voxel object as a whole
@export var origin: Vector3i ## Center voxel, used for detecting detached voxel chunks
@export var starting_shapes: Array ## Array of shapes used at VoxelObject start
@export var compression: float ## Size reduction of data compression
## Stores compressed voxel data
@export var _data := {
	"colors": null, 
	"color_index": null, "health": null,
	"positions": null, "valid_positions": null,
	"positions_dict": null, "valid_positions_dict": null,
  "vox_chunk_indices": null, "chunks": null
}
## Uncompressed size in bytes of _data for faster decompression
@export var _property_size := {
	"colors": 0, "color_index": 0, "health": 0,
	"positions": 0, "valid_positions": 0,
	"positions_dict": 0, "valid_positions_dict": 0,
  "vox_chunk_indices": 0, "chunks": 0
}

## Colors used for voxels
var colors:
	get: return _get("colors")
	set(value): _set("colors", value) 
## Voxel color index in colors
var color_index:
	get: return _get("color_index")
	set(value): _set("color_index", value)
## Current life of voxels
var health:
	get: return _get("health")
	set(value): _set("health", value)
## Voxel positions array
var positions:
	get: return _get("positions")
	set(value): _set("positions", value)
## Intact voxel positions array
var valid_positions:
	get: return _get("valid_positions")
	set(value): _set("valid_positions", value)
## Voxel positions dictionary
var positions_dict:
	get: return _get("positions_dict")
	set(value): _set("positions_dict", value)
## Intact voxel positions dictionary
var valid_positions_dict:
	get: return _get("valid_positions_dict")
	set(value): _set("valid_positions_dict", value)
## What chunk a voxel belongs to
var vox_chunk_indices:
	get: return _get("vox_chunk_indices")
	set(value): _set("vox_chunk_indices", value)
## Stores chunk locations with intact voxel locations
var chunks:
	get: return _get("chunks")
	set(value): _set("chunks", value)

## Stores variables that are buffered in an uncompressed state
var data_buffer = Dictionary()
## Number of times a variable has been buffered within the BUFFER_LIFETIME
var buffer_life = Dictionary()
## Pool of debri nodes
var debri_pool = Array()


## Retrieves values from _data and returns them in the intended decompressed format [br]
## or returns data from data_buffer
func _get(property: StringName) -> Variant:
	# Prevents decompressing missing data
	if property in _data:
		var result
		# Prevents decompressing data if it is in the buffer
		if property not in data_buffer:
			var compressed_bytes = _data[property]
			# Prevents decompressing non existant data
			if compressed_bytes != null and compressed_bytes.size() > 0:
				var decompressed_bytes = compressed_bytes.decompress(_property_size[property], COMPRESSION_MODE)
				result = bytes_to_var(decompressed_bytes)
				# Properly type variable if bytes_to_var() returns incorrect type
				if property in ["color_index", "health"]:
					return PackedByteArray(result)
				elif property in ["colors"]:
					return PackedColorArray(result)
				elif property in ["positions", "valid_positions", "vox_chunk_indices"]:
					return PackedVector3Array(result)
				elif property in ["positions_dict", "valid_positions_dict"]:
					var dictionary: Dictionary[Vector3i, int] = result
					return (dictionary)
				elif property in ["chunks"]:
					var dictionary: Dictionary[Vector3, PackedVector3Array] = result
					return (dictionary)
		else:
			return data_buffer[property]
	# Prevents errors from scripts relying on data types.
	if property in ["color_index", "health"]:
		return PackedByteArray()
	elif property in ["colors"]:
		return PackedColorArray()
	elif property in ["positions", "valid_positions"]:
		return PackedVector3Array()
	elif property in ["positions_dict", "valid_positions_dict"]:
		var dictionary: Dictionary[Vector3i, int] = {}
		return (dictionary)
	return null


## Sets values in _data after compression or sets data in data_buffer
func _set(property: StringName, value: Variant) -> bool:
	if property in _property_size:
		# Prevents compressing data if it is in the buffer
		if property not in data_buffer:
			var bytes = var_to_bytes(value)
			var compressed_bytes
			compressed_bytes = bytes.compress(COMPRESSION_MODE)
			_property_size[property] = bytes.size()
			_data[property] = compressed_bytes
		else:
			data_buffer[property] = value
		return true
	return false


## Adds property to data_buffer if found in _data. [br]
## can optionaly prevent debuffering for BUFFER_LIFTIME 
func buffer(property, auto_debuffer: bool = true):
	if property not in _data:
		push_warning("Cannot Buffer "+property+": Is not a compressed variable")
		return
	data_buffer[property] = _get(property)
	if auto_debuffer:
		if buffer_life.has(property):
			buffer_life[property] += 1
		else:
			buffer_life[property] = 1
		await Engine.get_main_loop().create_timer(BUFFER_LIFETIME).timeout
		buffer_life[property] -= 1
		if buffer_life[property] == 0 and property in data_buffer:
			debuffer(property)


## Removes a property from data_buffer and sets the value in _data. [br]
## Ignores BUFFER_LIFTIME
func debuffer(property):
	if property not in data_buffer:
		push_warning("Cannot Debuffer "+property+": Does not exist")
		return
	## Saves last value in buffer to _data to prevent data loss
	var buffer = data_buffer[property]
	data_buffer[property] = null
	data_buffer.erase(property)
	_set(property, buffer)


## Calls buffer on all properties in _data
func buffer_all():
	for property in _data.keys():
		buffer(property)


## Calls debuffer on all properties in _data
func debuffer_all():
	for property in data_buffer.keys():
		debuffer(property)


## Creates debris and saves them to debri_pool
func pool_rigid_bodies(vox_amount) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debri_pool.append(debri)


## Returns a debri from the debri_pool
func get_debri() -> RigidBody3D:
	if debri_pool.size() > 0:
		return debri_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
