@icon("voxel_damager.svg")
extends Area3D
class_name VoxelDamager
## Call [method VoxelDamager.hit] to damage all voxels within the area. 
##
## Add a BoxShape3D and to a collision node. Will set the _range to the smallist axis. [br]
## The damager inherits the [Area3D] node and suffers from the same limitations.

## Whether to not damage a specific node group or to only damage that node group
@export_enum("Ignore", "Blacklist", "Whitelist") var group_mode = 0
## Group to blacklist or whitelist
@export var group: String
## Delays a physics tick before starting hit to allow get_overlapping_bodies() to update.[br]
## Can help when hits do not seem to register on [VoxelObject]s after position change.
@export var tick_aligned: bool = false
@export_subgroup("Damage")
## Damage at damager origin
@export var base_damage: float = 30.0
## Damage decay from left (Origin) to right (Collision edge)
@export var damage_curve: Curve
@export_subgroup("Power")
## Launch power of debris at damager origin.
@export var base_power: int = 10
## Power decay from left (Origin) to right (Collision edge)
@export var power_curve: Curve = Curve.new()
## Knock back rigid body debris.
@export var knock_back_debri = false
var _range: float
## Stores global position since [member VoxelDamager.hit] was called.
@onready var _voxel_server = get_node("/root/VoxelServer")

var _killed = false # Triggers if incorrectly configured and disables this node

func _ready() -> void:
	if not _voxel_server and not Engine.is_editor_hint():
		push_error("VoxelServer Autoload not found! Please (re)enable the addon")
		_voxel_server = voxel_server.new()
	_voxel_server.voxel_damagers.append(self)
	var collision_shape = get_child(0).shape
	if collision_shape is not BoxShape3D:
		push_error("[VD ADDON] VoxelDamager collision shape must be BoxShape3D")
		_killed = true
		return
	var size = collision_shape.size
	_range = float(min(size.x, min(size.y, size.z)))/2
	if not damage_curve:
		push_warning("[VD ADDON] VoxelDamager has no DamageCurve, no damage will be applied!")
		damage_curve = Curve.new()
	if not power_curve:
		power_curve = Curve.new()
	damage_curve = _convert_curve_to_squared(damage_curve)
	power_curve = _convert_curve_to_squared(power_curve)

## Damages all voxel objects in radius
func hit():
	if _killed:
		return
	if tick_aligned:
		await get_tree().physics_frame
	# Maintain same postition and transform throughout damage calculation
	var starting_global_position = global_position
	# Ditto for VoxelObjects
	var voxel_object_transform = {}
	for body in get_overlapping_bodies():
		if body is StaticBody3D or body is RigidBody3D:
			var parent = body.get_parent()
			if parent is VoxelObject:
				voxel_object_transform[body] = {
					"global_transform": parent.global_transform,
					"parent": parent
				}
			else:
				# No need for global_transform at the moment
				voxel_object_transform[body] = {
					"global_transform": null,
					"parent": parent
				}
	var hit_objects = []
	var VoxelObjectNode = null
	var aabb = Array()
	aabb.resize(1)
	var task_id = WorkerThreadPool.add_task(
		_get_area_aabb.bind(aabb, get_child(0), starting_global_position),
		false, "VoxelDamager AABB Calculation"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame  # Allow UI to update
	aabb = aabb[0]
	for body in get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if "VoxelDebri" in body.name:
			if knock_back_debri and body.is_inside_tree():
				var global_pos = body.global_position
				var decay = starting_global_position.distance_to(global_pos) / _range
				var power = float(base_power * power_curve.sample(decay))
				var launch_vector = global_pos - starting_global_position
				var velocity = launch_vector.normalized() * power
				body.apply_impulse(velocity*body.scale)
		elif body is StaticBody3D or body is RigidBody3D:
			var voxel_object_transform_body = voxel_object_transform.get(body, false)
			if not voxel_object_transform_body:
				continue
			var parent = voxel_object_transform_body["parent"]
			if parent is VoxelObject:
				if parent.invulnerable or parent._disabled:
					continue
				if group_mode == 1:
					if group in parent.get_groups():
						continue
				elif group_mode == 2:
					if group not in parent.get_groups():
						continue
				var result = [0]
				# Use the transform at the time hit was called
				parent.voxel_resource.buffer("positions_dict")
				task_id = WorkerThreadPool.add_task(func():
					result[0] = VoxelUtilities.get_voxels_in_aabb(
						aabb,
						parent.voxel_resource.vox_size,
						parent.voxel_resource.positions_dict,
						voxel_object_transform_body["global_transform"]
					)
				)
				while not WorkerThreadPool.is_task_completed(task_id):
					await get_tree().process_frame  # Allow UI to update
				var voxels = result[0]
				parent._damage_voxels(self, voxels[0], voxels[1], voxels[2], starting_global_position)
				if parent not in hit_objects:
					hit_objects.append(parent)
	return hit_objects


# WORKER THREAD FUNC
func _get_area_aabb(aabb, collision_shape: CollisionShape3D, hit_position: Vector3)-> void:
	var box_shape = collision_shape.shape as BoxShape3D
	var size = box_shape.size
	var _position = hit_position - (size * 0.5)
	aabb[0] = AABB(_position, size)


func _convert_curve_to_squared(curve: Curve) -> Curve:
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
	_voxel_server.voxel_damagers.erase(self)
