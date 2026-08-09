@tool
extends EditorPlugin
class_name VoxelDestructionGodot

const VOXEL_PROGRESS_WINDOW_SCENE := preload("res://addons/VoxelDestruction/Utilities/progress_window.tscn")

var vox_importer
var selectable_gizmo

func _enter_tree() -> void:
	_create_settings()
	add_autoload_singleton("VoxelServer", "voxel_server.gd")
	vox_importer = preload("vox_importer.gd").new()
	add_import_plugin(vox_importer, true)
	add_custom_type("VoxelObject", "Gridmap", preload("Nodes/voxel_object.gd"), preload("Nodes/voxel_object.svg"))
	add_custom_type("VoxelDamager", "Area3D", preload("Nodes/voxel_damager.gd"), preload("Nodes/voxel_damager.svg"))
	add_custom_type("VoxelMarker", "Marker3D", preload("Nodes/voxel_marker.gd"), preload("Nodes/voxel_marker.svg"))
	add_tool_menu_item("Clean Voxel Destruction Resources", func(): _clean_cache.bind(get_tree()).call_deferred())
	if not is_connected("scene_saved", _on_scene_save):
		connect("scene_saved", _on_scene_save)
	selectable_gizmo = VDSelectableGizmo.new()
	add_node_3d_gizmo_plugin(selectable_gizmo)


func _exit_tree() -> void:
	remove_custom_type("VoxelObject")
	remove_custom_type("VoxelDamager")
	remove_custom_type("VoxelMarker")
	remove_import_plugin(vox_importer)
	remove_autoload_singleton("VoxelServer")
	vox_importer = null
	if is_connected("scene_saved", _on_scene_save):
		disconnect("scene_saved", _on_scene_save)
	call_deferred("_unregister_settings")
	remove_node_3d_gizmo_plugin(selectable_gizmo)


func _on_scene_save(_scene):
	if randf() < 0.4:
		var clean_func = func(): _clean_cache.bind(get_tree(), true).call_deferred()
		clean_func.call()


## Creates and returns a controlable [VoxelProgressWindow]
static func create_process(text: String, sub_text: String, progress: float = 0.0) -> VoxelProgressWindow:
	var voxel_progress_window: VoxelProgressWindow = VOXEL_PROGRESS_WINDOW_SCENE.instantiate()
	voxel_progress_window.text = text
	voxel_progress_window.sub_text = sub_text
	voxel_progress_window.progress = progress
	EditorInterface.get_base_control().add_child(voxel_progress_window)
	await voxel_progress_window.redraw()
	return voxel_progress_window


#region Settings
func _create_settings():
	var EditorSettingsDescription = preload("editor_settings_description.gd")

# ==================================================================================================
	var property = "voxel_destruction/performance/rust_gdextention"
	var value = false
	var description = """@experimental: Stability and or ease of setup cannot be assured. [br]
However, this drastically increases the speed at which certain functions run!"""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	var property_info = {
		"name": property,
		"type": TYPE_BOOL,
	}
	ProjectSettings.add_property_info(property_info)
	ProjectSettings.set_initial_value(property, value)
	ProjectSettings.set_restart_if_changed(property, true)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

# ==================================================================================================
	property = "voxel_destruction/performance/default_collision_quality"
	value = 1
	description = """Controls the precision of generated collision shapes.
Higher values improve accuracy but may increase physics cost.
Default uses the project setting voxel_destruction/performance/default_collision_quality"""
	if not ProjectSettings.has_setting(property):
		ProjectSettings.set_setting(property, value)
	property_info = {
		"name": property,
		"type": TYPE_INT,
		"hint": PROPERTY_HINT_ENUM,
		"hint_string": "High,Medium,Low"
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
	property = "voxel_destruction/debris/default_type"
	value = 0
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
	ProjectSettings.set_as_basic(property, true)
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
	ProjectSettings.set_as_basic(property, true)
	EditorSettingsDescription.set_project_setting_desc(property, description)
# ==================================================================================================

	ProjectSettings.save()


func _unregister_settings():
	ProjectSettings.clear("voxel_destruction/performance/rust_gdextention")
	ProjectSettings.clear("voxel_destruction/performance/default_collision_quality")
	ProjectSettings.clear("voxel_destruction/performance/collision_preload_percent")
	ProjectSettings.clear("voxel_destruction/debris/default_type")
	ProjectSettings.clear("voxel_destruction/debris/default_weight")
	ProjectSettings.clear("voxel_destruction/debris/default_density")
	ProjectSettings.clear("voxel_destruction/debris/default_lifetime")
	ProjectSettings.clear("voxel_destruction/debris/maximum_debris")
	ProjectSettings.clear("voxel_destruction/physics/default_density")
	ProjectSettings.clear("voxel_destruction/resources/compact/buffer_lifetime")
	ProjectSettings.clear("voxel_destruction/other/flood_fill_default")
#endregion


#region User File Cleanup
static func _clean_cache(tree: SceneTree, deamon: bool = false) -> void:
	# Check for unsaved changes
	if not EditorInterface.get_unsaved_scenes().is_empty():
		if not deamon:
			var popup = await VoxelDestructionGodot.create_process("Failed to clean Addon Resources", "You have unsaved scenes", 1.0)
			push_warning("Cache cleanup aborted: You have unsaved scenes.")
			tree.create_timer(2.0).connect("timeout", popup.queue_free)
		return 

	var popup = await VoxelDestructionGodot.create_process("Cleaning Addon Resources", "Gathering References")
	var cache_dir := "res://addons/VoxelDestruction/User/"
	var cache_files: Array[String] = []
	_gather_cache_files(cache_dir, cache_files)
	if cache_files.is_empty():
		popup.queue_free()
		return

	popup.text = "Scanning References"
	popup.sub_text = "Indexing project files"
	await popup.redraw()
	var referenced_paths: Dictionary = {}
	_build_reference_index("res://", referenced_paths)

	popup.text = "Checking References"
	var deleted_files := 0
	for i in range(cache_files.size()):
		var uid_text := cache_files[i]
		var full_path := ResourceUID.get_id_path(ResourceUID.text_to_id(uid_text))
		popup.progress = float(i) / cache_files.size()
		popup.sub_text = "%s (%d/%d)" % [full_path.get_file(), i + 1, cache_files.size()]
		await popup.redraw()

		if not referenced_paths.has(uid_text):
			var err := DirAccess.remove_absolute(full_path)
			if err != OK:
				push_warning("[VD ADDON] Failed to delete unused cache file: %s (err %d)" % [full_path, err])
			else:
				deleted_files += 1

	popup.progress = 1.0
	popup.text = "Done!"
	popup.sub_text = "Deleted %d unused cache files" % deleted_files
	await popup.redraw()
	if deleted_files != 0 and not deamon:
		tree.create_timer(1.0).connect("timeout", popup.queue_free)
	else:
		popup.queue_free()

static func _gather_cache_files(dir_path: String, out_files: Array[String]) -> void:
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
			_gather_cache_files(full_path, out_files)
		elif file_name.ends_with(".tres"):
			var uid_text := ResourceUID.id_to_text(ResourceLoader.get_resource_uid(full_path))
			out_files.append(uid_text)
	dir.list_dir_end()

static func _build_reference_index(dir_path: String, referenced_paths: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if dir.current_is_dir():
			if file_name != ".godot" and file_name != ".git":
				_build_reference_index(dir_path.path_join(file_name), referenced_paths)
		elif file_name.ends_with(".tscn") or file_name.ends_with(".tres"):
			var full_path := dir_path.path_join(file_name)
			for dep in ResourceLoader.get_dependencies(full_path):
				var dep_path: String = dep.split("::")[0]
				referenced_paths[dep_path] = true
		file_name = dir.get_next()
	dir.list_dir_end()
#endregion
