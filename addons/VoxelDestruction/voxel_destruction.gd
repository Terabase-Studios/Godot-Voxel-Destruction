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
	ProjectSettings.clear("voxel_destruction/physics/default_density")
	ProjectSettings.clear("voxel_destruction/resources/compact/buffer_lifetime")


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
