extends MarginContainer

var object: Object

func _init(obj: Object, text:String):
	object = obj
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var button := Button.new()
	add_child(button)
	button.size_flags_horizontal = SIZE_EXPAND_FILL
	if obj is VoxelUpdater:
		text = text.replace("Generate", "Update")
	button.button_down.connect(object._on_button_pressed.bind(text))
	button.text = text
