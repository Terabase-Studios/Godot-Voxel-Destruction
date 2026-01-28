#***************************#
# EditorSettingsDescription #
# By PiCode                 #
# v1.0                      #
#***************************#
## Set a description on project and editor settings.
## Useful for making custom settings for a plugin.
@tool
extends GDScript

static var _editor_descriptions:Dictionary[String,String] = {}
static var _project_descriptions:Dictionary[String,String] = {}

static var _editor_setting_inspector:Control
static var _project_setting_inspector:Control

static var _scene_tree:SceneTree

static func _static_init() -> void:
	## Editor settings
	var editor_settings_window = EditorInterface.get_base_control().find_children("","EditorSettingsDialog",true,false)[-1]
	var si = editor_settings_window.find_children("","SectionedInspector",true,false)[-1]
	_editor_setting_inspector = si.find_child("EditorInspector",true,false)
	var tree:Tree = si.find_child("Tree",true,false)
	tree.cell_selected.connect(_on_editor_inspector_changed)

	_scene_tree = editor_settings_window.get_tree()

	## Project settings
	var project_settings_window = EditorInterface.get_base_control().find_children("","ProjectSettingsEditor",true,false)[-1]
	var general = project_settings_window.find_children("General","",true,false)[-1]
	si = general.find_children("","SectionedInspector",true,false)[-1]
	_project_setting_inspector = si.find_child("EditorInspector",true,false)
	tree = si.find_child("Tree",true,false)
	tree.cell_selected.connect(_on_project_inspector_changed)
	_on_editor_inspector_changed()

static func _on_editor_inspector_changed() -> void:
	await _scene_tree.create_timer(.1).timeout
	for editor_property:Control in _editor_setting_inspector.find_children("","EditorProperty",true,false):
		var property_path = editor_property.tooltip_text.split("|")[-1]
		if _editor_descriptions.has(property_path):
			editor_property.child_entered_tree.connect(func(child:Node): if child.get_class() == "EditorHelpBitTooltip": _on_tooltip_popup(child,_editor_descriptions[property_path]))

static func _on_project_inspector_changed() -> void:
	await _scene_tree.create_timer(.1).timeout
	for editor_property:Control in _project_setting_inspector.find_children("","EditorProperty",true,false):
		var property_path = editor_property.tooltip_text.split("|")[-1]
		if _project_descriptions.has(property_path):
			editor_property.child_entered_tree.connect(func(child:Node): if child.get_class() == "EditorHelpBitTooltip": _on_tooltip_popup(child,_project_descriptions[property_path]))

static func _on_tooltip_popup(tooltip_node,new_tooltip_text:String) -> void:
	var rich_text_label = tooltip_node.get_child(-1).get_child(-1) as RichTextLabel
	await rich_text_label.ready
	rich_text_label.text = new_tooltip_text
	rich_text_label.bbcode_enabled = true

## Set a description for an editor setting.
static func set_editor_setting_desc(name:String,description:String) -> void:
	_editor_descriptions[name] = description

## Set a description for a project setting.
static func set_project_setting_desc(name:String,description:String) -> void:
	_project_descriptions[name] = description
