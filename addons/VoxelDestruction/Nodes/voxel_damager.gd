@icon("voxel_damager.svg")
extends Area3D
class_name VoxelDamager

@export_enum("Ignore", "Blacklist", "Whitelist") var group_mode = 0
@export var group: String
@export_subgroup("Damage")
@export var base_damage: float
@export var damage_curve: Curve
@export_subgroup("Power")
@export var base_power: int
@export var power_curve: Curve
@export var knock_back_debri = false
var range: int
@onready var global_pos = global_position


func _ready() -> void:
	VoxelServer.voxel_damagers.append(self)
	var collision_shape = get_child(0).shape
	if collision_shape is not BoxShape3D:
		push_warning("VoxelDamager collision shape must be BoxShape3D")
	var size = collision_shape.size
	range = min(size.x, min(size.y, size.z))


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
		var size = box_shape.size * 2
		var position = collision_shape.global_position - (size * 0.5)
		return AABB(position, size)
	return AABB()


func get_voxels_in_aabb(aabb: AABB, object: VoxelObject) -> Array:
	var voxel_positions = PackedVector3Array()
	var global_voxel_positions = PackedVector3Array()
	var voxel_count: int = 0
	var voxel_resource: VoxelResourceBase = object.voxel_resource
	voxel_resource.buffer("valid_positions_dict")
	for voxel_pos: Vector3 in voxel_resource.valid_positions_dict.keys():
		var voxel_global_pos = voxel_pos*voxel_resource.vox_size + object.global_position # Convert voxel index to world space
		if aabb.has_point(voxel_global_pos):
			var voxid = voxel_resource.valid_positions_dict.get(Vector3i(voxel_pos), -1)
			if voxid != -1:
				voxel_count += 1
				voxel_positions.append(voxel_pos)
				global_voxel_positions.append(voxel_global_pos)
	return [voxel_count, voxel_positions, global_voxel_positions]


func _exit_tree() -> void:
	VoxelServer.voxel_damagers.erase(self)
