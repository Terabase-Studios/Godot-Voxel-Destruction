@tool
extends VoxelBase
class_name Voxel

@export_storage var ArmorID: int
@export_storage var MaxHealth: float
@export_storage var Verticies: PackedVector3Array

@onready var VoxelObjectNode = get_parent().get_parent()
@onready var CollectionNode = get_parent()
@onready var Collision = get_child(1).get_child(0)

var destroyed = false
var Health: float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func damageVoxel(damage, power, origin):
	if ArmorID != -1:
		damage /= CollectionNode.DefenceOverrides[CollectionNode.DefenceOverrides.keys()[ArmorID]]
	if not destroyed:
		if VoxelObjectNode.Shielded:
			return
		Health = clamp(Health-damage, 0, MaxHealth)
		CollectionNode.Health -= damage
		var mesh = get_child(0)
		visible = true
		if Health == 0:
			get_child(0).visible = false
			destroy(power, origin)
		else:
			mesh.transparency = Health/MaxHealth

func destroy(power, origin):
	destroyed = true
	Collision.set_deferred("disabled", true)
	VoxelObjectNode.removedVerticies.append_array(Verticies)
	VoxelObjectNode.call_deferred("remove_voxel_part")

	var debri = preload("res://addons/VoxelDestruction/Resources/debri.tscn").instantiate()
	add_child(debri)
	debri.name = "VoxelDebri"
	debri.get_child(0).shape.size = VoxelObjectNode.scale
	debri.get_child(1).mesh.size = VoxelObjectNode.scale
	debri.top_level = true
	debri.freeze = false

	var LaunchVector = global_position - origin
	var velocity = LaunchVector.normalized() * power
	debri.apply_impulse(velocity)
	debri.get_child(2).play("Shrink")
	await debri.get_child(2).animation_finished
	debri.call_deferred("queue_free")
	
