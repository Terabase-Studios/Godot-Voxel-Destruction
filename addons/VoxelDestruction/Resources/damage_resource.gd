@icon("debri_resource.svg")
extends Resource
class_name DamageResource

@export var health: PackedByteArray
@export var positions: PackedVector3Array
@export var positions_dict: Dictionary[Vector3i, int]
var debri_pool = []

# Debri handling
func pool_rigid_bodies(vox_amount):
	for i in range(0, vox_amount):
		var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
		debri.hide()
		debri_pool.append(debri)


func get_debri():
	if debri_pool.size() > 0:
		return debri_pool.pop_front()
	var debri = preload("res://addons/VoxelDestruction/Scenes/debri.tscn").instantiate()
	debri.hide()
	return debri
