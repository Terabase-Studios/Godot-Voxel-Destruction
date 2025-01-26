@tool
extends VoxelBase
class_name VoxelDamager

@export var range: int
@export_category("Damage")
@export var BaseDamage: int
@export var ShieldDamage: int
@export var DamageCurve: Curve
@export_category("Power")
@export var BasePower: int
@export var PowerCurve: Curve

@onready var Area3DNode: Area3D = get_child(0)

var CollidingBodies = []

signal contact

func _ready() -> void:
	Area3DNode.body_entered.connect(body_entered)
	Area3DNode.body_exited.connect(body_exited)

func _get_configuration_warnings():
	var warnings = []

	if get_child(0) == null:
		warnings.append("Please add Area3D node as child with collision.")
	else:
		if not get_child(0) is Area3D:
			warnings.append("Please have first child be Area3D.")

	# Returning an empty array means "no warning".
	return warnings


func hit():
	var VoxelObjectNode = null
	for body in CollidingBodies:
		if body.name == "VoxelDebri":
			var decay = global_position.distance_to(body.global_position) / range
			var Power = float(BasePower * PowerCurve.sample(decay))
			var LaunchVector = body.global_position - global_position
			var velocity = LaunchVector.normalized() * Power
			body.apply_impulse(velocity*body.get_child(2).current_animation_position )
			continue
		body = body.get_parent()
		if body is VoxelShield:
			body.damage(ShieldDamage)
		elif body is Voxel:
			var decay = global_position.distance_to(body.global_position) / range
			var Damage = int(BaseDamage * DamageCurve.sample(decay))
			var Power = float(BasePower * PowerCurve.sample(decay))
			body.damageVoxel(Damage, Power, global_position)



func body_entered(body: Node3D) -> void:
	CollidingBodies.append(body)

func body_exited(body: Node3D) -> void:
	CollidingBodies.remove_at(CollidingBodies.find(body))
