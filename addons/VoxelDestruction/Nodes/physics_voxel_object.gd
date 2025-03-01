extends VoxelObject
class_name PhysicsVoxelObject

const property_blacklist = ["_semaphore", "_mutex", "_thread", "_exit_thread", "physics_object", "script"]

func assimilate(vox_object: VoxelObject):
	for property in vox_object.get_property_list():
		var property_name = property["name"]
		if property_name not in property_blacklist:
			set(property_name, vox_object.get(property_name))
	populate_mesh()
	vox_object.queue_free()


func _finish_object():
	var server = PhysicsServer3D
	var body = RigidBody3D.new()
	var body_rid = body.get_rid()
	body.freeze = true
	add_sibling(body)
	get_parent().remove_child(self)
	body.add_child(self, true, Node.INTERNAL_MODE_FRONT)
	for i in multimesh.instance_count:
		var shape_rid = server.box_shape_create()
		server.shape_set_data(shape_rid, size * 0.5)
		var shape_transform = Transform3D(Basis(), voxel_resource.positions[i] * size)
		server.body_add_shape(body_rid, shape_rid, shape_transform)
		_collision_shapes[shape_rid] = i
		voxel_resource.colors[i] = multimesh.get_instance_color(i)
	await get_tree().process_frame
	_thread.start(_flood_fill)



func _exit_tree():
	super()
	for rid in _collision_shapes.keys():
		PhysicsServer3D.free_rid(rid)
