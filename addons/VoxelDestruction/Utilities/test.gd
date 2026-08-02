@tool
extends Node2D
enum TEST_TYPE {
	PROGRESS,
	CACHE_CLEAN
}

@export_enum("Progress Popup", "Cache Cleanup") var test_type = 0
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
