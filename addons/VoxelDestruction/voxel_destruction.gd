@tool
extends EditorPlugin
class_name VoxelDestructionGodot

var vox_importer

func _enter_tree() -> void:
	vox_importer= preload("vox_importer.gd").new()
	add_import_plugin(vox_importer, true)
	add_custom_type("VoxelObject", "Gridmap", preload("Nodes/voxel_object.gd"), preload("Nodes/voxel_object.svg"))
	add_custom_type("VoxelDamager", "Area3D", preload("Nodes/voxel_damager.gd"), preload("Nodes/voxel_damager.svg"))
	add_autoload_singleton("VoxelServer", "voxel_server.gd")


func _exit_tree() -> void:
	remove_custom_type("VoxelObject")
	remove_custom_type("VoxelDamager")
	remove_import_plugin(vox_importer)
	remove_autoload_singleton("VoxelServer")
	vox_importer = null
