@tool
@icon("voxel_resource.svg")
extends Resource
class_name VoxelResource


@export var vox_count: int
@export var vox_size: Vector3
@export var size: Vector3
@export var origin: Vector3i


@export var _data := {
	"colors": PackedColorArray(), 
	"color_index": PackedByteArray(), "health": PackedByteArray(),
	"positions": PackedVector3Array(), "valid_positions": PackedVector3Array(),
	"positions_dict": Dictionary(), "valid_positions_dict": Dictionary()
}:
	get: return _data
	set(value): _data = value

@export var _property_size := {
	"colors": 0, "color_index": 0, "health": 0,
	"positions": 0, "valid_positions": 0,
	"positions_dict": 0, "valid_positions_dict": 0
}

var data_buffer = Dictionary()


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

var debri_pool = []

## Retrieves decompressed values and returns them in the intended format ##
func _get(property: StringName):
	if property in _data:
		var result
		if property not in data_buffer:
			var compressed_bytes = _data[property]
			if compressed_bytes.size() > 0:
				var decompressed_bytes = compressed_bytes.decompress(_property_size[property], 1)
				result = bytes_to_var(decompressed_bytes)
				if property in ["color_index", "health"]:
					return PackedByteArray(result)
				elif property in ["colors"]:
					return PackedColorArray(result)
				elif property in ["positions", "valid_positions"]:
					return PackedVector3Array(result)
				elif property in ["positions_dict", "valid_positions_dict"]:
					var dictionary: Dictionary[Vector3i, int] = result
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
			var compressed_bytes = bytes.compress(1)
			_property_size[property] = bytes.size()
			_data[property] = compressed_bytes
		else:
			data_buffer[property] = value
		return true
	return false

## Controls data in buffer ##
func buffer(property):
	if property in _data:
		data_buffer[property] = _get(property)

func debuffer(property):
	if property in data_buffer:
		var buffer = data_buffer[property]
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
