extends Resource
class_name SnippitProfiler

var _start_time = 0
func start():
	_start_time = Time.get_ticks_usec()

#func end():
	#var end_time = Time.get_ticks_usec()
	#var duration = (end_time - start_time) / 1000.0 # Duration in milliseconds
	#print("Snippit took: ", duration, "ms")
