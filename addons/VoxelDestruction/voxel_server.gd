extends Node
class_name voxel_server

var body_metadata: Dictionary[RID, Array] = {}
var voxel_objects: Array
var voxel_damagers: Array

func get_body_object(rid):
	return voxel_objects[body_metadata[rid][0]]

func get_body_transform(rid):
	return body_metadata[rid][1]

func remove_body(rid):
	var server = PhysicsServer3D
	for i: VoxelDamager in voxel_damagers:
		i.target_objects.erase(rid)
	server.free_rid(server.body_get_shape(rid, 0))
	server.free_rid(rid)
	body_metadata.erase(rid)
