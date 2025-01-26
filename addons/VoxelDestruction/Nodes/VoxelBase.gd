@tool
extends Node3D
class_name VoxelBase


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not Engine.is_editor_hint():
		queue_free()
