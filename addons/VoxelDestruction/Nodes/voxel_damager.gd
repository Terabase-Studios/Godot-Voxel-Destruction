@icon("voxel_damager.svg")
extends Area3D
class_name VoxelDamager
## Call [method VoxelDamager.hit] to damage all voxels within the area. 
##
## Add a BoxShape3D and to a collision node. Will set the range to the smallist axis. [br]
## The damager inherits the [Area3D] node and suffers from the same limitations.

## whether to not damage group or to only damage group
@export_enum("Ignore", "Blacklist", "Whitelist") var group_mode = 0
## Group to blacklist or whitelist
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
var collision_node: CollisionShape3D


func _ready() -> void:
	VoxelServer.voxel_damagers.append(self)
	for child in get_children(true):
		if child is CollisionShape3D:
			collision_node = child
			break
	if not collision_node:
		push_error("Voxeldamager has no collision node")
	var collision_shape = collision_node.shape
	if collision_shape is not BoxShape3D:
		push_warning("VoxelDamager collision shape must be BoxShape3D")
	var size = collision_shape.size
	range = float(min(size.x, min(size.y, size.z)))/2
	damage_curve = convert_curve_to_squared(damage_curve)
	power_curve = convert_curve_to_squared(power_curve)

## Damages all voxel objects in radius
func hit() -> void:
	var hit_objects = []
	var VoxelObjectNode = null
	global_pos = global_position
	var task_id = WorkerThreadPool.add_task(
		_hit_thread.bind(collision_node, get_overlapping_bodies()),
		false, "VoxelDamager Calculation"
	)


func _hit_thread(collision_shape: CollisionShape3D, overlapping_bodies) -> void:
	var box_shape = collision_shape.shape as BoxShape3D
	var size = box_shape.size
	var _position = global_pos - (size * 0.5)
	var aabb = AABB(_position, size)
	for body in overlapping_bodies:
		if "VoxelDebri" in body.name:
			if knock_back_debri and body.is_inside_tree():
				call_deferred("launch_debris", body)
			continue
		if body is StaticBody3D or body is RigidBody3D:
			var parent = body.get_parent()
			if parent is VoxelObject:
				if parent.invulnerable or parent._disabled:
					continue
				if group_mode == 1:
					if group in parent.get_groups():
						continue
				elif group_mode == 2:
					if group not in parent.get_groups():
						continue
				var voxel_positions = PackedVector3Array()
				var global_voxel_positions = PackedVector3Array()
				var voxel_count: int = 0
				var voxel_resource: VoxelResource= parent.voxel_resource

				# Scale the transform to match the size of each voxel
				var object_global_transform = parent.global_transform
				var scaled_basis = object_global_transform.basis.scaled(voxel_resource.vox_size)
				var voxel_transform := Transform3D(scaled_basis, object_global_transform.origin)
				
				for voxel_pos: Vector3 in voxel_resource.positions.keys():
					# Center voxel in its grid cell
					var local_voxel_centered = voxel_pos + Vector3(0.5, 0.5, 0.5) - voxel_resource.size/Vector3(2, 2, 2)
					
					# Convert to global space using full transform
					var voxel_global_pos = voxel_transform * local_voxel_centered
					
					if aabb.has_point(voxel_global_pos):
						voxel_count += 1
						voxel_positions.append(voxel_pos)
						global_voxel_positions.append(voxel_global_pos)
				parent.call_deferred("_damage_voxels", self, voxel_count, voxel_positions, global_voxel_positions)


func launch_debris(debri: Node3D):
	var global_pos = debri.global_position
	var decay = global_pos.distance_squared_to(global_pos) / range
	var power = float(base_power * power_curve.sample(decay))
	var launch_vector = global_pos - global_pos
	var velocity = launch_vector.normalized() * power
	debri.call_deferred("apply_impulse", velocity*debri.scale)


func convert_curve_to_squared(curve: Curve) -> Curve:
	if not curve:
		push_error("No curve provided!")
		return

	var new_curve := Curve.new()

	for i in range(curve.get_point_count()):
		var x: float = curve.get_point_position(i).x
		var y: float = curve.get_point_position(i).y
		var left_tangent: float = curve.get_point_left_tangent(i)
		var right_tangent: float = curve.get_point_right_tangent(i)

		# Map X to squared value
		var new_x = x * x  # Squared mapping

		# Add new point to the new curve
		new_curve.add_point(Vector2(new_x, y), left_tangent, right_tangent)
	
	return new_curve


func _exit_tree() -> void:
	VoxelServer.voxel_damagers.erase(self)
