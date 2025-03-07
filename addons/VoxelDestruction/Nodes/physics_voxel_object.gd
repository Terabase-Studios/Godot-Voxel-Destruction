extends VoxelObject
class_name PhysicsVoxelObject

const property_blacklist = ["_semaphore", "_mutex", "_thread", "_exit_thread", "physics_object", "script"]
signal assimilated

func assimilate(vox_object: VoxelObject):
	for property in vox_object.get_property_list():
		var property_name = property["name"]
		if property_name not in property_blacklist:
			set(property_name, vox_object.get(property_name))
	self.name = "Physics" + vox_object.name
	populate_mesh()
	vox_object.queue_free()


func _finish_object():
	var server = PhysicsServer3D
	var main_body = RigidBody3D.new()
	var main_bodyRID = main_body.get_rid()
	var global_pos = global_position
	main_body.freeze = true
	main_body.name = name
	add_sibling(main_body)
	get_parent().remove_child(self)
	main_body.add_child(self, true, Node.INTERNAL_MODE_FRONT)
	for i in multimesh.instance_count:
		var bodyRID = server.body_create()
		var shapeRID = server.box_shape_create()
		var half_size = size / 2.0
		server.shape_set_data(shapeRID, half_size)  
		server.body_set_space(bodyRID, get_world_3d().space)
		server.body_set_collision_layer(bodyRID, 1)
		server.body_set_collision_mask(bodyRID, 1)
		server.body_add_collision_exception(bodyRID, main_bodyRID)
		server.body_add_shape(bodyRID, shapeRID, Transform3D(), false)
		var _transform = Transform3D(Basis(), (voxel_resource.positions[i] * size) + global_pos)
		server.body_set_state(bodyRID, PhysicsServer3D.BODY_STATE_TRANSFORM, _transform)
		server.body_set_mode(bodyRID, PhysicsServer3D.BODY_MODE_STATIC)
		server.body_set_state(bodyRID, PhysicsServer3D.BODY_STATE_SLEEPING, false)
		_body_rids[bodyRID] = i
		voxel_resource.colors[i] = multimesh.get_instance_color(i)


func _exit_tree():
	super()
