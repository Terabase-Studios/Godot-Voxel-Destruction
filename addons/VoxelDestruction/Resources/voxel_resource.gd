@tool
@icon("voxel_resource.svg")
extends Resource
class_name VoxelResource

const BUFFER_LIFETIME = 1
const COMPRESSION_MODE = 2

@export var vox_count: int
@export var vox_size: Vector3
@export var size: Vector3
@export var origin: Vector3i
@export var starting_shapes: Array
@export var compression: float
@export var _data := {
	"colors": null, 
	"color_index": null, "health": null,
	"positions": null, "valid_positions": null,
	"positions_dict": null, "valid_positions_dict": null,
  "vox_chunk_indices": null, "chunks": null
}

@export var _property_size := {
	"colors": 0, "color_index": 0, "health": 0,
	"positions": 0, "valid_positions": 0,
	"positions_dict": 0, "valid_positions_dict": 0,
  "vox_chunk_indices": 0, "chunks": 0
}


## Public getters/setters (return different types) ##
var colors:
	get: return _get("colors")
	set(value): _set("colors", value) 

var color_index:
	get: return _get("color_index")
	set(value): _set("color_index", value)

var health:
	get: return _get("health")
	set(value): _set("health", value)

var positions:
	get: return _get("positions")
	set(value): _set("positions", value)

var valid_positions:
	get: return _get("valid_positions")
	set(value): _set("valid_positions", value)

var positions_dict:
	get: return _get("positions_dict")
	set(value): _set("positions_dict", value)

var valid_positions_dict:
	get: return _get("valid_positions_dict")
	set(value): _set("valid_positions_dict", value)

var vox_chunk_indices:
	get: return _get("vox_chunk_indices")
	set(value): _set("vox_chunk_indices", value)

var chunks:
	get: return _get("chunks")
	set(value): _set("chunks", value)

var data_buffer = Dictionary()
var buffer_life = Dictionary()
var debri_pool = Array()

signal data_changed


## Retrieves decompressed values and returns them in the intended format ##
func _get(property: StringName):
	if property in _data:
		var result
		if property not in data_buffer:
			var compressed_bytes = _data[property]
			if compressed_bytes != null and compressed_bytes.size() > 0:
				var decompressed_bytes
				decompressed_bytes = compressed_bytes.decompress(_property_size[property], COMPRESSION_MODE)
				result = bytes_to_var(decompressed_bytes)
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

## Stores values as compressed data ##
func _set(property: StringName, value: Variant) -> bool:
	if property in _property_size:
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

## Controls data in buffer ##
func buffer(property, auto_debuffer: bool = true):
	if property not in _data:
		push_warning("Cannot Buffer "+property+": Does not exist")
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


func debuffer(property):
	if property not in data_buffer:
		push_warning("Cannot Debuffer "+property+": Does not exist")
		return
	var buffer = data_buffer[property]
	data_buffer[property] = null
	data_buffer.erase(property)
	_set(property, buffer)

func buffer_all():
	for property in _data.keys():
		buffer(property)

func debuffer_all():
	for property in data_buffer.keys():
		debuffer(property)


## Pools debris ##
func pool_rigid_bodies(vox_amount) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debri_pool.append(debri)

## Retrieves pooled debri ##
func get_debri() -> RigidBody3D:
	if debri_pool.size() > 0:
		return debri_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
