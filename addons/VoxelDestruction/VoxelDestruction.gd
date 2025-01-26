@tool
extends EditorPlugin
class_name VoxelDestructionGodot

const SINGLETON_NAME: String = "VoxelManager"
const SINGLETON_PATH: String = "res://addons/VoxelDestruction/VoxelManager.gd"

var generate_plugin
var update_plugin
var popupList = []

func _enter_tree() -> void:
	_add_singleton()
	add_custom_type("VoxelBase", "Node3D", preload("Nodes/VoxelBase.gd"), preload("Icons/VoxelBase.svg"))
	add_custom_type("VoxelComponent", "Node3D", preload("Nodes/VoxelComponent.gd"), preload("Icons/VoxelComponent.svg"))
	add_custom_type("VoxelGenerator", "Node3D", preload("Nodes/VoxelGenerator.gd"), preload("Icons/VoxelGenerator.svg"))
	add_custom_type("VoxelUpdater", "Node3D", preload("Nodes/VoxelUpdater.gd"), preload("Icons/VoxelUpdater.svg"))
	add_custom_type("VoxelDamager", "Node3D", preload("Nodes/VoxelDamager.gd"), preload("Icons/VoxelBase.svg"))
	add_custom_type("VoxelMultiplayerSynchronizer", "Node3D", preload("Nodes/VoxelMultiplayerSynchronizer.gd"), preload("Icons/VoxelMultiplayerSynchronizer.svg"))
	add_custom_type("VoxelShield", "Node3D", preload("Nodes/VoxelShield.gd"), preload("Icons/VoxelShield.svg"))
	add_custom_type("VoxelCollection", "Node3D", preload("Nodes/VoxelCollection.gd"), preload("Icons/VoxelCollection.svg"))
	add_custom_type("VoxelObject", "Node3D", preload("Nodes/VoxelObject.gd"), preload("Icons/VoxelObject.svg"))
	add_custom_type("Voxel", "Node3D", preload("Nodes/Voxel.gd"), preload("Icons/Voxel.svg"))
	if Engine.is_editor_hint():
		generate_plugin = preload("Editor Widgets/GenerateButtonPlugin.gd").new()
		add_inspector_plugin(generate_plugin)

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	_remove_singleton()
	remove_custom_type("VoxelBase")
	remove_custom_type("VoxelComponent")
	remove_custom_type("VoxelGenerator")
	remove_custom_type("VoxelUpdater")
	remove_custom_type("VoxelDamager")
	remove_custom_type("VoxelMultiplayerSynchronizer")
	remove_custom_type("VoxelShield")
	remove_custom_type("VoxelCollection")
	remove_custom_type("VoxelObject")
	remove_custom_type("Voxel")
	remove_inspector_plugin(generate_plugin)
	for i in popupList:
		remove_control_from_docks(i)


func _add_singleton() -> void:
	if not ProjectSettings.has_setting("autoload/" + SINGLETON_NAME):
		add_autoload_singleton(SINGLETON_NAME, SINGLETON_PATH)


func _remove_singleton() -> void:
	if ProjectSettings.has_setting("autoload/" + SINGLETON_NAME):
		remove_autoload_singleton(SINGLETON_NAME)


func add_popup(popup):
	add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_BL, popup)
	popupList.append(popup)
