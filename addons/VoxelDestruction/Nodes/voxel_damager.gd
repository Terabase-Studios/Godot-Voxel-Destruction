@icon("voxel_damager.svg")
extends Area3D
class_name VoxelDamager
## Call [method VoxelDamager.hit] to damage all voxels within the area. 
##
## Add a BoxShape3D and to a collision node. Will set the range to the smallist axis. [br]
## The damager inherits the [Area3D] node and suffers from the same limitations.

## Whether or not to blacklist the specified group or whitelist the group instead.
@export_enum("Ignore", "Blacklist", "Whitelist") var group_mode = 0
## Group to blacklist or whitelist.
@export var group: String
@export_subgroup("Damage")
## Damage at damager origin
@export var base_damage: float
## Damage decay from left (Origin) to right (Collision edge)
@export var damage_curve: Curve
@export_subgroup("Power")
## Launch power of debris at damager origin.
@export var base_power: int
## Power decay from left (Origin) to right (Collision edge)
@export var power_curve: Curve
## Knock back rigid body debris.
@export var knock_back_debri = false
var range: float
## Stores global position since [member VoxelDamager.hit] was called.
@onready var global_pos = global_position


func _ready() -> void:
	VoxelServer.voxel_damagers.append(self)
	var collision_shape = get_child(0).shape
	if collision_shape is not BoxShape3D:
		push_warning("VoxelDamager collision shape must be BoxShape3D")
	var size = collision_shape.size
	range = float(min(size.x, min(size.y, size.z)))/2


func hit():
	var hit_objects = []
	var VoxelObjectNode = null
	global_pos = global_position
	var aabb = get_area_aabb(self)
	for body in get_overlapping_bodies():
		if body is StaticBody3D or body is RigidBody3D:
			var parent = body.get_parent()
			if parent is VoxelObject:
				if parent.invulnerable:
					continue
				if group_mode == 1:
					if group in parent.get_groups():
						continue
				elif group_mode == 2:
					if group not in parent.get_groups():
						continue
				var voxels = get_voxels_in_aabb(aabb, parent)
				parent.damage_voxels(self, voxels[0], voxels[1], voxels[2])
				if parent not in hit_objects:
					hit_objects.append(parent)
		elif "VoxelDebri" in body.name and knock_back_debri:
			if is_instance_valid(body):
				var decay = global_position.distance_to(body.global_position) / range
				var power = float(base_power * power_curve.sample(decay))
				var launch_vector = body.global_position - global_position
				var velocity = launch_vector.normalized() * power
				body.apply_impulse(velocity*body.scale)
	return hit_objects


func get_area_aabb(area: Area3D) -> AABB:
	var collision_shape = area.get_child(0) as CollisionShape3D
	if collision_shape and collision_shape.shape is BoxShape3D:
		var box_shape = collision_shape.shape as BoxShape3D
		var size = box_shape.size
		var _position = collision_shape.global_position - (size * 0.5)
		return AABB(_position, size)
	return AABB()


func get_voxels_in_aabb(aabb: AABB, object: VoxelObject) -> Array:
	var voxel_positions = PackedVector3Array()
	var global_voxel_positions = PackedVector3Array()
	var voxel_count: int = 0
	var voxel_resource: VoxelResourceBase = object.voxel_resource
	voxel_resource.buffer("positions_dict")
	for voxel_pos: Vector3 in voxel_resource.positions_dict.keys():
		var voxel_global_pos = voxel_pos*voxel_resource.vox_size + object.global_position # Convert voxel index to world space
		if aabb.has_point(voxel_global_pos):
			var voxid = voxel_resource.positions_dict.get(Vector3i(voxel_pos), -1)
			if voxid != -1:
				voxel_count += 1
				voxel_positions.append(voxel_pos)
				global_voxel_positions.append(voxel_global_pos)
	return [voxel_count, voxel_positions, global_voxel_positions]


func _exit_tree() -> void:
	VoxelServer.voxel_damagers.erase(self)
