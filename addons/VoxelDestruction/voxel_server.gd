extends Node
class_name voxel_server
## Keeps track of data used in monitors and culling

## Array of [VoxelObject]s
var voxel_objects: Array[VoxelObject]
## Array of [VoxelDamager]s
var voxel_damagers: Array[VoxelDamager]
## Amount of intact voxels
var total_active_voxels: int
## Amount of shapes used in [VoxelObject]s
var shape_count: int

@onready var raycast: RayCast3D
var _previous_camera_node: Camera3D
var camera_node: Camera3D

func _ready():
#region Add folded lines
	Performance.add_custom_monitor("Voxel Destruction/Voxel Objects", get_voxel_object_count)
	Performance.add_custom_monitor("Voxel Destruction/Active Voxels", get_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Visible Voxels", get_visible_voxel_count)
	Performance.add_custom_monitor("Voxel Destruction/Shape Count", get_shape_count)
	Performance.add_custom_monitor("Voxel Destruction/LOD Hidden Voxels", get_lod_hidden_voxels)
#endregion


func _physics_process(delta: float) -> void:
	if not is_instance_valid(raycast):
		raycast = RayCast3D.new()
		raycast.name = "VD ADDON CULLING RAY CAST"
		raycast.set_collision_mask_value(1, false)
		raycast.set_collision_mask_value(11, true)
	
	camera_node = get_viewport().get_camera_3d()
	if not camera_node:
		return

	if camera_node != _previous_camera_node:
		if _previous_camera_node:
			raycast.reparent(_previous_camera_node)
		else:
			camera_node.add_child(raycast)
		_previous_camera_node = camera_node
		raycast.position = Vector3.ZERO
		raycast.rotation = Vector3.ZERO
	
	var corners: Array = [
		Vector3(0, 0, 0),
		Vector3(1, 0, 0),
		Vector3(0, 1, 0),
		Vector3(0, 0, 1),
		Vector3(1, 1, 0),
		Vector3(1, 0, 1),
		Vector3(0, 1, 1),
		Vector3(1, 1, 1),
	]
	
	for object in voxel_objects:
		if not object._culling_body:
			continue

		var object_origin = object.global_position
		var half_size = object.voxel_resource.size * object.voxel_resource.vox_size * 0.5
		var visible := false

		# 1) Ray to center
		raycast.target_position = raycast.to_local(object_origin)
		raycast.force_raycast_update()

		if raycast.get_collider() == object._culling_body:
			object.visible = true
			continue

		# 2) Rays to corners
		for corner in corners: # corners should be [-1, +1] based
			var target = object_origin + corner * half_size
			raycast.target_position = raycast.to_local(target)
			raycast.force_raycast_update()

			if raycast.get_collider() == object._culling_body:
				visible = true
				break

		if visible:
			object.visible = true
			continue

		object.visible = visible




#region Profilers
## Returns [member voxel_server.voxel_objects] size
func get_voxel_object_count():    
	return voxel_objects.size()

## Returns [member voxel_server.total_active_voxels]
func get_voxel_count():
	return total_active_voxels

## Returns [VoxelObject]s [member MultiMesh.visible_instance_count]
func get_visible_voxel_count():
	var visible_voxel_count = 0
	for object in voxel_objects:
		if not object.visible:
			continue
		visible_voxel_count += object.multimesh.visible_instance_count
	return visible_voxel_count

## Returns [member voxel_server.shape_count]
func get_shape_count():
	return shape_count

## Returns Voxels hidden by [VoxelLODAddon] that would otherwise be visible
func get_lod_hidden_voxels():
	var hidden_voxels: int = 0
	for object in voxel_objects:
		if object.lod_addon:
			hidden_voxels += object.lod_addon.hidden_voxels
	return hidden_voxels
#endregion
