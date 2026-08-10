@tool
extends Node2D
enum TEST_TYPE {
	PROGRESS,
	CACHE_CLEAN,
	GDEXT,
	GDEXT_SETUP
}

@export_enum("Progress Popup", "Cache Cleanup", "GD Extention", "GD Extension Setup") var test_type = 0
@export_tool_button("Run Test") var test_func = test

func test():
	if test_type == TEST_TYPE.PROGRESS:
		var popup = await VoxelDestructionGodot.create_process("Testing", "0%")
		for i in range(100):
			i = float(i)
			await get_tree().create_timer(.02).timeout
			popup.progress = i/100.0
			popup.sub_text = str(i/100.0) + "%"
			await popup.redraw()
			
		popup.queue_free()
	elif test_type == TEST_TYPE.GDEXT:
		# Check if Godot registered the class in ClassDB
		if not ClassDB.class_exists("VoxelNative"):
			push_error("Its super broken")
			return
	elif test_type == TEST_TYPE.GDEXT_SETUP:
		var node_to_test = GDextensionSetup.new()
		add_child(node_to_test)
		node_to_test.setup()
		#node_to_test.queue_free()
