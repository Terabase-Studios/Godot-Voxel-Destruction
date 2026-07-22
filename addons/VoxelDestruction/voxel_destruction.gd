@tool
extends EditorPlugin
class_name VoxelDestructionGodot

var vox_importer

func _enter_tree() -> void:
	create_settings()
	add_autoload_singleton("VoxelServer", "voxel_server.gd")
	vox_importer= preload("vox_importer.gd").new()
	add_import_plugin(vox_importer, true)
	add_custom_type("VoxelObject", "Gridmap", preload("Nodes/voxel_object.gd"), preload("Nodes/voxel_object.svg"))
	add_custom_type("VoxelDamager", "Area3D", preload("Nodes/voxel_damager.gd"), preload("Nodes/voxel_damager.svg"))
	add_custom_type("VoxelMarker", "Marker3D", preload("Nodes/voxel_marker.gd"), preload("Nodes/voxel_marker.svg"))
	_clean_cache()


func _exit_tree() -> void:
	remove_custom_type("VoxelObject")
	remove_custom_type("VoxelDamager")
	remove_custom_type("VoxelMarker")
	remove_import_plugin(vox_importer)
	remove_autoload_singleton("VoxelServer")
	_unregister_settings()
	vox_importer = null


func create_settings():
	var EditorSettingsDescription = preload("editor_settings_description.gd")

# ==================================================================================================
	var property = "voxel_destruction/performance/queue_attacks"
	var value = false
	var description = """@experimental: This has not been tested for performance gains and may potentially [b]Decrease performance[/b]. [br]
Queue attacks so one attack is being processed at a time with a small cooldown inbetween. [br]
This has a chance to increase performace when multiple attacks damage the [VoxelObject] in a short period."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	var property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/performance/collision_preload_percent"
	value = 0.0
	description = """@experimental: Changing this value may cause unintended behavior.
The amount of [CollisionShape3D]s to preload for collision generation. [br]
Increase this value to potentially reduce studdering but may use excessive memory."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.0,1.0,0.1"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/performance/collision_nodes_updated_per_physics_frame"
	value = 50
	description = """The max amount of collision shapes to add/remove per VoxelObject per Physics Frame.[br]
	Increase this value to make hits more responsive or decrease this value to potentially reduce any studder."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "1,50,1,hide_control,or_greater"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/debris/default_type"
	value = 2
	description = """Type of debris generated [br]
[b]None[/b]: No debris will be generated [br]
[b]Multimesh[/b]: Debri has limited physics and no collision [br]
[b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]"""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "None,Multimesh,Rigid Bodies"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/debris/multimesh/batch_size"
	value = 100
	description = """Maximum amount of multimesh debris to spawn each physics frame."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,60,1,hide_control,or_greater"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/debris/rigid_body/batch_size"
	value = 10
	description = """Maximum amount of Rigid Body debris to spawn each physics frame."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,60,1,hide_control,or_greater"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/resources/compact/buffer_lifetime"
	value = 10
	description = """Time since last buffered before a variable is automatically debuffered. [br]
In other words, the amount of time before [CompactVoxelResource] recompresses data.
"""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0,60,1,hide_control,or_greater"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/other/flood_fill_default"
	value = 1
	description = """@experimental: This property is unstable.
Handle detached voxels [br]
[b]Disabled[/b]: Do not handle detached voxels [br]
[b]Destroy[/b]: Detached voxels are destroyed[br]
[b]Rigid body[/b]: Detached voxels fall as rigid bodies[br]
[b]Voxel Object[/b]: Detached voxels become their own VoxelObject[br]
"""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "Disabled,Destroy,Rigid Body,Voxel Object"
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/benchmarks/VoxelObject/benchmark_ready"
	value = false
	description = """Print benchmark timings for VoxelObject._ready() setup steps to the console."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/benchmarks/VoxelObject/benchmark_damage"
	value = false
	description = """Print benchmark timings for voxel damage calculation and application to the console."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/benchmarks/VoxelObject/benchmark_flood_fill"
	value = false
	description = """Print benchmark timings for structural flood-fill detachment to the console."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/benchmarks/VoxelObject/benchmark_collision"
	value = false
	description = """Print benchmark timings for collision shape regeneration to the console."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/benchmarks/VoxelObject/benchmark_debris"
	value = false
	description = """Print benchmark timings for debris batch creation to the console."""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

	ProjectSettings.save()


func _unregister_settings():
	ProjectSettings.clear("voxel_destruction/performance/queue_attacks")
	ProjectSettings.clear("voxel_destruction/performance/collision_preload_percent")
	ProjectSettings.clear("voxel_destruction/performance/collision_nodes_updated_per_physics_frame")
	ProjectSettings.clear("voxel_destruction/debris/default_type")
	ProjectSettings.clear("voxel_destruction/debris/default_weight")
	ProjectSettings.clear("voxel_destruction/debris/default_density")
	ProjectSettings.clear("voxel_destruction/debris/default_lifetime")
	ProjectSettings.clear("voxel_destruction/debris/maximum_debris")
	ProjectSettings.clear("voxel_destruction/debris/multimesh/batch_size")
	ProjectSettings.clear("voxel_destruction/debris/rigid_body/batch_size")
	ProjectSettings.clear("voxel_destruction/physics/default_density")
	ProjectSettings.clear("voxel_destruction/resources/compact/buffer_lifetime")
	ProjectSettings.clear("voxel_destruction/other/flood_fill_default")
	ProjectSettings.clear("voxel_destruction/benchmarks/VoxelObject/benchmark_ready")
	ProjectSettings.clear("voxel_destruction/benchmarks/VoxelObject/benchmark_damage")
	ProjectSettings.clear("voxel_destruction/benchmarks/VoxelObject/benchmark_flood_fill")
	ProjectSettings.clear("voxel_destruction/benchmarks/VoxelObject/benchmark_collision")
	ProjectSettings.clear("voxel_destruction/benchmarks/VoxelObject/benchmark_debris")


func _clean_cache() -> void:
	var cache_dir := "res://addons/VoxelDestruction/User/"
	_clean_cache_recursive(cache_dir)


func _clean_cache_recursive(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("[VD ADDON] Failed to open cache directory: %s" % dir_path)
		return

	dir.list_dir_begin()

	while true:
		var file_name := dir.get_next()
		if file_name == "":
			break

		if file_name == "." or file_name == "..":
			continue

		var full_path := dir_path.path_join(file_name)

		if dir.current_is_dir():
			_clean_cache_recursive(full_path)
		elif file_name.ends_with(".tres"):
			if not is_file_referenced(full_path):
				var err := DirAccess.remove_absolute(full_path)
				if err != OK:
					push_error("[VD ADDON] Failed to delete unused cache file: %s (err %d)" % [full_path, err])
				else:
					print("[VD ADDON] Deleted unused cache file: ", full_path)

	dir.list_dir_end()


func is_file_referenced(file_path: String) -> bool:
	var root_dir := "res://"
	return _search_directory(root_dir, file_path)

func _search_directory(dir_path: String, search_target: String) -> bool:
	var dir = DirAccess.open(dir_path)

	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if dir.current_is_dir():
				if file_name != ".godot" and file_name != ".git" and file_name != "User": # Skip system folders
					if _search_directory(dir_path.path_join(file_name), search_target):
						return true
			elif file_name.ends_with(".tscn") or file_name.ends_with(".tres"):
				var full_path = dir_path.path_join(file_name)
				if _file_contains_string(full_path, search_target):
					print("Found in: ", full_path)
					return true
			file_name = dir.get_next()
	return false

func _file_contains_string(tscn_path: String, target: String) -> bool:
	var file = FileAccess.open(tscn_path, FileAccess.READ)
	if file:
		while file.get_position() < file.get_length():
			var line = file.get_line()
			if line.contains(target):
				return true
	return false
