@tool
extends VoxelComponent
class_name VoxelCollection

@export_storage var DefenceOverrides = {}

var resource: Resource
var MaxHealth = 0
var Health = 0
var Loaded = false

signal loaded

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	if not Engine.is_editor_hint():
		await get_parent().ready
		resource = get_parent().resource
		VoxelManager.TotalVoxels += resource.voxels.size()
		for voxelscene in resource.voxels:
			var voxel = voxelscene.instantiate()
			add_child(voxel)
			voxel.Health = voxel.MaxHealth
			MaxHealth += voxel.MaxHealth
			VoxelManager.LoadedVoxels += 1
		Health = MaxHealth
		Loaded = true
		loaded.emit()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
