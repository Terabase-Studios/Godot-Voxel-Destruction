@tool
extends PopupPanel
class_name VoxelProgressWindow

@export var text := "": 
	set(value):
		%Label.text = value
		text = value
@export var progress := 0.0: 
	set(value):
		%ProgressBar.value = value
		progress = value
@export var sub_text := "": 
	set(value):
		%SubLabel.text = value
		sub_text = value


## Uses `await get_tree().process_frame` to allow popup redraw.
func redraw() -> void:
	await get_tree().process_frame
	return
