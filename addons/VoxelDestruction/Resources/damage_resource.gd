@icon("debri_resource.svg")
extends Resource
class_name DamageResource

@export var health: PackedInt32Array
var debri_pool = []
var shared_mesh: BoxMesh
var shared_material: StandardMaterial3D
var shared_shape: BoxShape3D


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


func preload_darkening(object: VoxelObject, complexity: float):
	var colors = object.voxel_resource.colors.duplicate()
	var collision = BoxShape3D.new()
	collision.size = Vector3(1, 1, 1)
	colors.push_back(Color.BLACK)
	for base_color in colors:
		var i = -complexity
		for x in range(0, complexity*100):
			i += complexity
			var color = base_color.darkened(i)
			 
			# Add new color to library
			if color not in object.new_colors:
				# Define matierials/mesh/collision
				var material = StandardMaterial3D.new()
				material.albedo_color = color
				var mesh = BoxMesh.new()
				mesh.material = material
				
				# Add items to library
				var item_id = object.mesh_library.get_last_unused_item_id()
				
				object.mesh_library.create_item(item_id)  # Create an entry
				object.mesh_library.set_item_mesh(item_id, mesh)  # Assign the mesh
				object.mesh_library.set_item_shapes(item_id, [collision, Transform3D()])
				
				# Add new color
				object.new_colors[color] = item_id
