@tool
extends VoxelGenerator
class_name VoxelUpdater

@export_storage var ChildCount = 0

func _process(delta: float) -> void:
	if GeneratePopup == null:
		for child in get_children():
			child.queue_free()
		self.name = "Voxel Updater"


func _on_button_pressed(text: String) -> void:
	if text.to_upper() == "UPDATE VOXEL":
		self.name = get_parent().name
		updating = true
		print('--------------------')
		if DirAccess.open(SaveDirectory) == null:
			print_rich("[color=red]Invalid Directory[/color]")
			return

		var i = 0
		for child in get_parent().resource.meshes:
			if i <= ChildCount:
				add_child(child.instantiate())
			i += 1

		SaveSceneDirectory = SaveDirectory

		if GeneratePopup != null:
			GeneratePopup.queue_free()
		else:
			GeneratePopup = preload("res://addons/VoxelDestruction/Pop-Ups/GeneratePopup.tscn").instantiate()
			GeneratePopup.name = self.name
			GeneratePopup.voxelGenerator = self
			GeneratePopup.voxelCount = self.get_child_count()
			GeneratePopup.objectName = self.name
			GeneratePopup.saveDirectory = SaveSceneDirectory + self.name + '.vox'
			GeneratePopup.failsafe = Failsafe
			VoxelDestructionGodot.new().add_popup(GeneratePopup)
