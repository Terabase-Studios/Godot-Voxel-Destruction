@tool
extends EditorPlugin
class_name VoxelDestructionGodot

var vox_importer

func _enter_tree() -> void:
	vox_importer= preload("vox_importer.gd").new()
	add_import_plugin(vox_importer, true)
	add_custom_type("VoxelObject", "Gridmap", preload("Nodes/voxel_object.gd"), preload("Nodes/voxel_object.svg"))
	add_custom_type("VoxelDamager", "Area3D", preload("Nodes/voxel_damager.gd"), preload("Nodes/voxel_damager.svg"))
	add_custom_type("VoxelMarker", "Marker3D", preload("Nodes/voxel_marker.gd"), preload("Nodes/voxel_marker.svg"))
	add_autoload_singleton("VoxelServer", "voxel_server.gd")
	_clean_cache()


func _exit_tree() -> void:
	remove_custom_type("VoxelObject")
	remove_custom_type("VoxelDamager")
	remove_custom_type("VoxelMarker")
	remove_import_plugin(vox_importer)
	remove_autoload_singleton("VoxelServer")
	vox_importer = null


func _clean_cache():
	var cache_dir := "res://addons/VoxelDestruction/Cache/"
	var log_path := cache_dir + "old_cache.txt"

	if not FileAccess.file_exists(log_path):
		return

	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		push_error("[VD ADDON] Failed to open old_cache.txt for reading")
		return

	var paths: Array[String] = []

	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		if line != "":
			paths.append(line)

	file.close()

	for path in paths:
		if FileAccess.file_exists(path):
			var err := DirAccess.remove_absolute(path)
			if err != OK:
				push_error("[VD ADDON] Failed to delete cache file: %s (err %d)"
					% [path, err])

	# Clear the log once processed
	file = FileAccess.open(log_path, FileAccess.WRITE)
	if file:
		file.close()
