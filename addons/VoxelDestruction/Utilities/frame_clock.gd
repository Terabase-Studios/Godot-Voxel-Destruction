extends Node
class_name FrameClock

var frame_start_usec: int = 0

func _init() -> void:
	process_physics_priority = -9999

func _physics_process(_delta: float) -> void:
	frame_start_usec = Time.get_ticks_usec()
