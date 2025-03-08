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
@onready var global_pos = global_position
@onready var range: int = get_child(0).shape.radius
var target_objects = []

func _ready() -> void:
	connect("body_shape_entered", _on_body_shape_entered)
	connect("body_shape_exited", _on_body_shape_exited)
	VoxelServer.voxel_damagers.append(self)


func hit():
	var hit_objects = []
	var VoxelObjectNode = null
	global_pos = global_position
	for rid in target_objects:
		if VoxelServer.body_metadata.get(rid):
			var voxel_object = VoxelServer.get_body_object(rid)
			if group_mode == 1:
				if group in voxel_object.get_groups():
					continue
			elif group_mode == 2:
				if group not in voxel_object.get_groups():
					continue
			voxel_object.call_deferred("_damage_voxel", rid, self)
			if voxel_object not in hit_objects:
				hit_objects.append(voxel_object)
	for debri in get_overlapping_bodies():
		if "VoxelDebri" in debri.name and knock_back_debri:
			if is_instance_valid(debri):
				var decay = global_position.distance_to(debri.global_position) / range
				var power = float(base_power * power_curve.sample(decay))
				var launch_vector = debri.global_position - global_position
				var velocity = launch_vector.normalized() * power
				debri.apply_impulse(velocity*debri.scale)
	return hit_objects


func _on_body_shape_entered(body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int) -> void:
	if VoxelServer.body_metadata.has(body_rid):  # Check if we track it
		target_objects.append(body_rid)

func _on_body_shape_exited(body_rid: RID, body: Node3D, body_shape_index: int, local_shape_index: int) -> void:
	if VoxelServer.body_metadata.has(body_rid) and target_objects.has(body_rid):
		target_objects.remove_at(target_objects.find(body_rid))


func _exit_tree() -> void:
	VoxelServer.voxel_damagers.erase(self)
