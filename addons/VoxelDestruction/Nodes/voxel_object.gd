@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

@export var voxel_resource: VoxelResource:
	set(value):
		voxel_resource = value
		update_configuration_warnings()
		if value:
			populate_mesh()
		else:
			multimesh.instance_count = 0
@export var invulnerable = false
@export var darkening = true
@export_subgroup("Debri")
@export_enum("None", "Multimesh", "Rigid Bodies") var debri_type = 0
@export var debri_weight = 1
@export_range(0, 1, .1) var debri_density = .2
@export var debri_lifetime = 5
@export_subgroup("Dithering")
@export_range(0, .20, .01) var dark_dithering = 0.0:
	set(value):
		dark_dithering = value
		populate_mesh()
@export_range(0, .20, .01) var light_dithering = 0.0:
	set(value):
		light_dithering = value
		populate_mesh()
@export_range(0, 1, .1) var dithering_bias = 0.5:
	set(value):
		dithering_bias = value
		populate_mesh()
@export var dithering_seed: int = 0:
	set(value):
		dithering_seed = value
		populate_mesh()
@export_subgroup("Experimental")
@export var remove_floating_voxels = true
@export var λ_φ_coloration = false:
	set(value):
		λ_φ_coloration = value
		update_configuration_warnings()
		populate_mesh()
var physics_object = false
var _shape_node: CollisionShape3D
var _debri_queue = Array()
var _debri_called = false
var _mutex: Mutex
var _semaphore: Semaphore
var _thread: Thread
var _exit_thread := false
var hp: float = 1


func _ready() -> void:
	if not Engine.is_editor_hint():
		if not voxel_resource:
			push_warning("Voxel object has no VoxelResource")
			return
		_mutex = Mutex.new()
		_semaphore = Semaphore.new()
		_exit_thread = false
		_thread = Thread.new()
		_thread.start(_flood_fill)
		if debri_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))
		call_deferred("_set_voxel_object")
		VoxelServer.voxel_objects.append(self)
		VoxelServer.total_active_voxels += voxel_resource.vox_count


func _process(delta: float) -> void:
	_debri_called = false


func _get_configuration_warnings():
	var warnings = []
	
	if not voxel_resource:
		warnings.append("Missing VoxelResource.")
	
	if λ_φ_coloration:
		warnings.append("Όσοι το χρησιμοποιούν έχουν τις ευχαριστίες μου.")
	
	return warnings


func populate_mesh():
	if voxel_resource and Engine.is_editor_hint():
		voxel_resource.buffer("positions")
		voxel_resource.buffer("color_index")
		voxel_resource.buffer("colors")
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.instance_count = voxel_resource.vox_count
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = voxel_resource.vox_size
		multimesh.mesh = mesh
		
		var random = RandomNumberGenerator.new()
		random.set_seed(dithering_seed)
			
		for i in multimesh.instance_count:
			var dark_variation = random.randf_range(0, dark_dithering)
			var light_variation = random.randf_range(0, light_dithering)
			var dithered_color = Color.WHITE
			if dark_dithering == 0 or light_dithering == 0:
				if dark_dithering == 0:
					dithered_color = get_vox_color(i).lightened(light_variation)
				elif light_dithering == 0:
					dithered_color = get_vox_color(i).darkened(dark_variation)
			else:
				dithered_color = get_vox_color(i).darkened(dark_variation) if randf() > dithering_bias else get_vox_color(i).lightened(light_variation)
			
			multimesh.set_instance_transform(i, Transform3D(Basis(), voxel_resource.positions[i]*voxel_resource.vox_size))
			multimesh.set_instance_color(i, dithered_color)

func reset():
	voxel_resource.valid_positions = voxel_resource.positions
	voxel_resource.valid_positions_dict = voxel_resource.positions_dict
	voxel_resource.buffer("health")
	voxel_resource.health.fill(100)
	_update_collision()
	populate_mesh()
	_set_hp()
	VoxelServer.call_deferred("set_object_memory", self)


func get_vox_color(voxid) -> Color:
	if λ_φ_coloration:
		var pos = voxel_resource.positions[voxid] + Vector3(voxel_resource.origin)
		return Color((pos.x+pos.z)/100, (pos.y+pos.x)/100, (pos.z+pos.y)/100)
	return voxel_resource.colors[voxel_resource.color_index[voxid]]

#**Update no rids**
#func _make_physics_object():
	#var server = PhysicsServer3D
	#var body = RigidBody3D.new()
	#var body_rid = body.get_rid()
	#body.freeze = true
	#body.name = name + " Physics"
	#body.global_position = global_position
	#position = Vector3.ZERO
	#add_sibling(body)
	#get_parent().remove_child(self)
	#body.add_child(self, true, Node.INTERNAL_MODE_FRONT)
	#await get_tree().process_frame
	#for rid in _body_rids:
		#server.body_add_collision_exception(rid, body_rid)
	#var mesh = Mesh.new()
	#body.freeze = false


func _set_voxel_object():
	voxel_resource.buffer("colors")
	voxel_resource.buffer("color_index")
	var static_body = StaticBody3D.new()
	add_child(static_body)
	for shape_info in voxel_resource.starting_shapes:
		var shape_node = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape_node.shape = shape
		shape.extents = shape_info["extents"]
		
		static_body.add_child(shape_node)
		shape_node.position = shape_info["position"]
		
	for i in multimesh.instance_count:
		# Update colors (they could be dithered)
		var color = multimesh.get_instance_color(i)
		if color not in voxel_resource.colors:
			voxel_resource.colors.append(color)
		voxel_resource.color_index[i] = voxel_resource.colors.find(color)
	VoxelServer.call_deferred("set_object_memory", self)
	#if physics_object:
		#_make_physics_object()
	return


func _damage_voxel(voxid: int, vox_postion: Vector3, damager: VoxelDamager):
	var decay := damager.global_pos.distance_to(vox_postion) / damager.range
	var base_damage := damager.base_damage
	var base_power := damager.base_power
	var decay_sample := damager.damage_curve.sample(decay)
	if decay_sample <= 0.01:
		return  # Skip processing if damage is negligible
	var power_sample := damager.power_curve.sample(decay)
	var damage := base_damage * decay_sample
	var power = (base_power * power_sample) / max(debri_weight, 0.1)
	var health = voxel_resource.health[voxid] - damage
	health = clamp(health, 0, 100)
	voxel_resource.health[voxid] = health
	if health > 0:
		if darkening:
			multimesh.set_instance_color(voxid, get_vox_color(voxid).darkened(1.0 - (health * 0.01)))
	else:
		var vox_pos := Vector3i(voxel_resource.positions[voxid])
		voxel_resource.valid_positions_dict.erase(vox_pos)
		multimesh.set_instance_transform(voxid, Transform3D())
		VoxelServer.total_active_voxels -= 1
		if power > 0.01:
			_debri_queue.append({ "pos": vox_postion, "origin": damager.global_pos, "power": power}) 
			match debri_type:
				1: 
					_start_debri("_create_debri_multimesh", true)
					_debri_called = true
				2: 
					_start_debri("_create_debri_rigid_bodies", true)
					_debri_called = true


func _update_collision():
	return


func _start_debri(function, check_floating):
	if _debri_called or debri_lifetime == 0 or debri_density == 0:
		return
	await get_tree().process_frame
	VoxelServer.call_deferred("set_object_memory", self)
	
	if hp == 0:
		visible = false
	
	if check_floating and remove_floating_voxels:
		call_deferred("_remove_detached_voxels_start")
	
	voxel_resource.valid_positions = PackedVector3Array(voxel_resource.valid_positions_dict.keys())
	
	call_deferred(function)
	call_deferred("_update_collision")
	_set_hp()
	await get_tree().process_frame
	VoxelServer.call_deferred("set_object_memory", self)


func create_boxes(chunk: PackedVector3Array) -> Array:
	var visited: Dictionary[Vector3, bool]
	var boxes = []

	var can_expand = func(box_min: Vector3, box_max: Vector3, axis: int, pos: int) -> bool:
		var start
		var end
		match axis:
			0: start = Vector3(pos, box_min.y, box_min.z); end = Vector3(pos, box_max.y, box_max.z)
			1: start = Vector3(box_min.x, pos, box_min.z); end = Vector3(box_max.x, pos, box_max.z)
			2: start = Vector3(box_min.x, box_min.y, pos); end = Vector3(box_max.x, box_max.y, pos)

		for x in range(int(start.x), int(end.x) + 1):
			for y in range(int(start.y), int(end.y) + 1):
				for z in range(int(start.z), int(end.z) + 1):
					var check_pos = Vector3(x, y, z)
					if not chunk.has(check_pos) or visited.get(check_pos, false):
						return false
		return true
	
	for pos in chunk:
		if visited.get(pos, false):
			continue
		
		var box_min = pos
		var box_max = pos
		
		# Expand along X, Y, Z greedily
		for axis in range(3):
			while true:
				var next_pos = box_max[axis] + 1
				if can_expand.call(box_min, box_max, axis, next_pos):
					box_max[axis] = next_pos
				else:
					break

		# Mark visited voxels
		for x in range(int(box_min.x), int(box_max.x) + 1):
			for y in range(int(box_min.y), int(box_max.y) + 1):
				for z in range(int(box_min.z), int(box_max.z) + 1):
					visited[Vector3(x, y, z)] = true

		boxes.append({"min": box_min, "max": box_max})

	return boxes

func _create_debri_multimesh():
	var gravity_magnitude : float = ProjectSettings.get_setting("physics/3d/default_gravity")
	var debri_states = []
	var multi_mesh_instance = MultiMeshInstance3D.new()
	var multi_mesh = MultiMesh.new()
	multi_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	multi_mesh_instance.top_level = true
	multi_mesh_instance.multimesh = multi_mesh
	multi_mesh.mesh = preload("res://addons/VoxelDestruction/Resources/debri.tres").duplicate()
	multi_mesh.mesh.size = voxel_resource.vox_size
	multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	multi_mesh.instance_count = _debri_queue.size()
	add_child(multi_mesh_instance)
	var idx = 0
	for debris_data in _debri_queue:
		# Control debri amount
		if randf() > debri_density: continue
		
		var debris_pos = debris_data.pos
		
		# Store data for manual physics update
		debri_states.append({
			"position": debris_pos,
			"velocity": (debris_pos - debris_data.origin).normalized() * -debris_data.power,
		})
		
		multi_mesh.set_instance_transform(idx, Transform3D(Basis(), debris_pos))
		idx += 1
	var current_lifetime = debri_lifetime
	_debri_queue.clear()
	while current_lifetime > 0:
		var delta = get_physics_process_delta_time()
		current_lifetime -= delta
		for i in debri_states.size():
			var data = debri_states[i]
			data["velocity"].x *= .98
			data["velocity"].z *= .98
			data["velocity"].y -= gravity_magnitude * delta * debri_weight
			data["position"] += data["velocity"] * delta * 2
			multi_mesh.set_instance_transform(i, Transform3D(Basis(), data["position"]))
		await get_tree().process_frame
	multi_mesh_instance.queue_free()


func _create_debri_rigid_bodies():
	# Pre-cache children
	var debri_objects = []  # To store all the debris
	for debris_data in _debri_queue:
		# Control debri amount
		if randf() > debri_density: continue
		# Retrieve/generate debri
		var debri = voxel_resource.get_debri()
		debri.name = "VoxelDebri"
		debri.top_level = true
		debri.show()
		# Cache shape and mesh if possible
		var shape = debri.get_child(0)
		var mesh = debri.get_child(1)
		# Set size/position in a single step
		add_child(debri, true, Node.INTERNAL_MODE_BACK)
		var debris_pos = debris_data.pos
		debri.global_position = debris_pos
		shape.shape.size = voxel_resource.vox_size
		mesh.mesh.size = voxel_resource.vox_size
		# Launch debri
		var velocity = (debris_pos - debris_data.origin).normalized() * debris_data.power
		debri.freeze = false
		debri.gravity_scale = debri_weight
		debri.apply_impulse(velocity)
		# Add the debri to list
		debri_objects.append(debri)
	_debri_called = false
	_debri_queue.clear()
	await get_tree().create_timer(debri_lifetime).timeout
	# Batch scale-down animation (single loop)
	if not debri_objects.is_empty():
		var tween = get_tree().create_tween()
		for debri in debri_objects:
			var shape = debri.get_child(0)
			var mesh = debri.get_child(1)
			tween.parallel().tween_property(shape, "scale", Vector3(.01, .01, .01), 1)
			tween.parallel().tween_property(mesh, "scale", Vector3(.01, .01, .01), 1)
		await get_tree().create_timer(1).timeout
	# Restore all debris in a batch
	for debri in debri_objects:
		_restore_debri_rigid_bodies(debri)


func _restore_debri_rigid_bodies(debri):
	if is_instance_valid(debri.get_parent()):
		debri.get_parent().remove_child(debri)
		debri.get_child(0).scale = Vector3(1, 1, 1)
		debri.get_child(1).scale = Vector3(1, 1, 1)
		debri.hide()
		voxel_resource.debri_pool.append(debri)


func _remove_detached_voxels_start():
	var res = voxel_resource
	var origin: Vector3i
	if not res.origin in res.valid_positions_dict:
		if not res.valid_positions.is_empty():
			res.origin = Vector3i(Array(res.valid_positions).pick_random())
	_semaphore.post()


func _flood_fill():
	while true:
		_semaphore.wait()
		
		_mutex.lock()
		var should_exit = _exit_thread
		_mutex.unlock()
		
		if should_exit:
			break
		
		var queue = [voxel_resource.origin]
		var visited = {}
		
		var damage_positions = voxel_resource.valid_positions
		var damage_positions_dict = voxel_resource.valid_positions_dict
		
		visited[voxel_resource.origin] = true
		
		var offsets = [Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
					   Vector3i(0, 1, 0), Vector3i(0, -1, 0),
					   Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
		
		while queue.size() > 0:
			var vox = queue.pop_front()
			
			for offset in offsets:
				var neighbor_vox: Vector3i = vox + offset
			
				if not visited.get(neighbor_vox) and damage_positions.has(Vector3(neighbor_vox)):
					visited[neighbor_vox] = true
					queue.append(neighbor_vox)
		
		var to_remove = []
		for vox in damage_positions:
			if not visited.has(Vector3i(vox)):  
				to_remove.append(vox)
		
		# Process voxel removal inside the thread
		if not to_remove.is_empty():
			_mutex.lock()
			voxel_resource.buffer("positions_dict")
			voxel_resource.buffer("valid_positions_dict")
			voxel_resource.buffer("valid_positions")
			for vox in to_remove:
				var voxid = voxel_resource.positions_dict[Vector3i(vox)]
				if voxid != -1:
					voxel_resource.valid_positions_dict.erase(Vector3i(vox))
					multimesh.set_instance_transform(voxid, Transform3D())
			voxel_resource.valid_positions = PackedVector3Array(voxel_resource.valid_positions_dict.keys())
			_mutex.unlock()
			call_deferred("_update_collision")
			call_deferred("_set_hp")
		damage_positions.clear()
		damage_positions_dict.clear()
		to_remove.clear()
		visited.clear()
		queue.clear()
		VoxelServer.call_deferred("set_object_memory", self)


func _set_hp():
	hp = float(int(float(voxel_resource.valid_positions.size())/float(voxel_resource.vox_count)*100))/100


func _exit_tree():
	if Engine.is_editor_hint():
		return
	if _thread != null:
		_mutex.lock()
		_exit_thread = true
		_mutex.unlock()
		
		_semaphore.post()
		
		_thread.wait_to_finish()
	
	voxel_resource = null
	voxel_resource = null
	VoxelServer.total_active_voxels -= voxel_resource.valid_positions.size()
	VoxelServer.voxel_objects.erase(self)
	VoxelServer.call_deferred("set_object_memory", self)
