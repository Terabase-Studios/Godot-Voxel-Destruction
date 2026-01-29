@tool
@icon("compact_voxel_resource.svg")
extends VoxelResourceBase
class_name CompactVoxelResource
## Contains VoxelData for the use of a VoxelObject along with a debri pool. Stores scalable voxel data in a compressed binary array. [br]
## This can cause stuttering when voxel data is decompressed
##
## Whenever a large array or dictionary is retrieved or set a compressed/decompressed DUPLICATE is returned.
## These variables can be buffered allowing them to be accessed and modified as a normal variable with little performance loss
##
## @experimental
const BUFFER_LIFETIME = 10 ## Time since last buffered before a variable is automatically debuffered.
const COMPRESSION_MODE = 2 ## Argument passed to compress()/decompress()

## Size reduction of data compression
@export var compression: float 
## Stores compressed voxel data
@export var _data := {
	"colors": null, 
	"color_index": null, "health": null,
	"positions": null, "positions_dict": null,
	"vox_chunk_indices": null, "chunks": null,
	"visible_voxels": null
	
}
## Uncompressed size in bytes of _data for faster decompression
@export var _property_size := {
	"colors": 0, "color_index": 0, "health": 0,
	"positions": 0, "positions_dict": 0,
	"vox_chunk_indices": 0, "chunks": 0,
	"visible_voxels": 0
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
## Voxel positions dictionary
var positions_dict:
	get: return _get("positions_dict")
	set(value): _set("positions_dict", value)
## What chunk a voxel belongs to
var vox_chunk_indices:
	get: return _get("vox_chunk_indices")
	set(value): _set("vox_chunk_indices", value)
## Stores chunk locations with intact voxel locations
var chunks:
	get: return _get("chunks")
	set(value): _set("chunks", value)
## Stores what voxels should be visible
var visible_voxels:
	get: return _get("visible_voxels")
	set(value): _set("visible_voxels", value)

## Stores variables that are buffered in an uncompressed state
var data_buffer = Dictionary()
## Number of times a variable has been buffered within the BUFFER_LIFETIME
var buffer_life = Dictionary()



## Retrieves values from _data and returns them in the intended decompressed format [br]
## or returns data from data_buffer
func _get(property: StringName, ignore_buffer_error: bool = false) -> Variant:
	# Prevents decompressing missing data
	if property in _data:
		var result
		# Prevents decompressing data if it is in the buffer
		if property not in data_buffer:
			var compressed_bytes = _data[property]
			# Prevents decompressing non existant data
			if compressed_bytes != null and compressed_bytes.size() > 0:
				if not ignore_buffer_error and not Engine.is_editor_hint():
					push_warning("Accessing unbuffered variable \""+str(property)+"\"! This can severly reduce performance. Please Report with expanded error information.")
				var decompressed_bytes = compressed_bytes.decompress(_property_size[property], COMPRESSION_MODE)
				result = bytes_to_var(decompressed_bytes)
				# Properly type variable if bytes_to_var() returns incorrect type
				if property in ["color_index", "health"]:
					return PackedByteArray(result)
				elif property in ["colors"]:
					return PackedColorArray(result)
				elif property in ["positions", "vox_chunk_indices", "visible_voxels"]:
					return PackedVector3Array(result)
				elif property in ["positions_dict"]:
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
	elif property in ["positions", "vox_chunk_indices", "visible_voxels"]:
		return PackedVector3Array()
	elif property in ["positions_dict"]:
		var dictionary: Dictionary[Vector3i, int] = {}
		return (dictionary)
	return null


## Sets values in _data after compression or sets data in data_buffer
func _set(property: StringName, value: Variant) -> bool:
	# Return if value null
	if value == null:
		return false
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
func buffer(property, auto_debuffer: bool = true, lifetime = BUFFER_LIFETIME):
	if property not in _data:
		push_warning("Cannot Buffer \""+str(property)+"\": Property is not a compressed variable")
		return
	data_buffer[property] = _get(property, true)
	if auto_debuffer:
		if buffer_life.has(property):
			buffer_life[property] += 1
		else:
			buffer_life[property] = 1
		await Engine.get_main_loop().create_timer(lifetime).timeout
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


func _clear():
	debuffer_all()
	_data.clear()
	_property_size.clear()
	super()
