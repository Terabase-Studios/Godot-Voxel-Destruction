extends Node
class_name FrameClock

var process_frame_start_usec: int = 0
var physics_frame_start_usec: int = 0

func _init() -> void:
	process_physics_priority = -9999


func _process(_delta: float) -> void:
	process_frame_start_usec = Time.get_ticks_usec()


func _physics_process(_delta: float) -> void:
	physics_frame_start_usec = Time.get_ticks_usec()
