@icon("voxel_resource_base.svg")
extends Resource
class_name VoxelResourceBase
## Contains Basic VoxelData along with a debri pool
##
## @deprecated: Use [VoxelResource] instead.
@export var vox_count: int ## Number of voxels stored in the resource
@export var vox_size: Vector3 ## Scale of voxels, multiply voxel postion by this and add VoxelObject node global position for global voxel position
@export var size: Vector3 ## Estimated size of voxel object as a whole
@export var origin: Vector3i ## Center voxel, used for detecting detached voxel chunks
@export var starting_shapes: Array ## Array of shapes used at VoxelObject start
@export var materials: Dictionary[Color, Color] ## Stores material data such as metalic and emmisives. Cleared at runtime for memory usage.

## Pool of debris nodes
var debris_pool: Array[RigidBody3D]
## Pool of collision nodes
var collision_pool: Array[CollisionShape3D]

var _cleared = false

## Creates debris and saves them to [member debri_pool]
func pool_rigid_bodies(vox_amount: int) -> void:
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debris_pool.append(debri)


## Returns a debri from the [member debri_pool]
func get_debri() -> RigidBody3D:
	if debris_pool.size() > 0:
		return debris_pool.pop_back()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri


## Adds a debri to the [member debri_pool]
func return_debri(debri) -> void:
	if _cleared:
		if is_instance_valid(debri):
			debri.queue_free()
		return
	debris_pool.append(debri)


## Creates [CollisionShape3D]s with a [BoxShape3D] and saves them to [member collision_pool]
func pool_collision_nodes(vox_amount: int) -> void:
	for i in range(0, vox_amount):
		var collision_node := CollisionShape3D.new()
		var collision_shape := BoxShape3D.new()
		collision_node.shape = collision_shape
		collision_pool.append(collision_node)


## Returns a [CollisionShape3D] with a [BoxShape3D] from the [member collision_pool]
func get_collision_node() -> CollisionShape3D:
	if collision_pool.size() > 0:
		return collision_pool.pop_back()
	var collision_node := CollisionShape3D.new()
	var collision_shape := BoxShape3D.new()
	collision_node.shape = collision_shape
	return collision_node


## Adds a [CollisionShape3D] with a [BoxShape3D] to the [member collision_pool]
func return_collision_node(node: CollisionShape3D) -> void:
	if _cleared:
		if is_instance_valid(node):
			node.queue_free()
		return
	collision_pool.append(node)


func _clear() -> void:
	_cleared = true
	starting_shapes.clear()
	materials.clear()

	for node in collision_pool:
		if is_instance_valid(node):
			node.queue_free()
	collision_pool.clear()

	for node in debris_pool:
		if is_instance_valid(node):
			node.queue_free()
	debris_pool.clear()
