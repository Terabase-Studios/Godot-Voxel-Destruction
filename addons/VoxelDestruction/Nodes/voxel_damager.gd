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

func hit():
	var VoxelObjectNode = null
	global_pos = global_position
	if not get_overlapping_bodies().is_empty():
		for body in get_overlapping_bodies():
			if body.get_parent() is VoxelObject:
				if "VoxelDebri" in body.name and knock_back_debri:
					if is_instance_valid(body):
						var decay = global_position.distance_to(body.global_position) / range
						var power = float(base_power * power_curve.sample(decay))
						var launch_vector = body.global_position - global_position
						var velocity = launch_vector.normalized() * power
						body.apply_impulse(velocity*body.scale )
				elif body is StaticBody3D:
					if group_mode == 1:
						if group in body.get_parent().get_groups():
							continue
					elif group_mode == 2:
						if group not in body.get_parent().get_groups():
							continue
					body.get_parent().call_deferred("_damage_voxel", body, self)
