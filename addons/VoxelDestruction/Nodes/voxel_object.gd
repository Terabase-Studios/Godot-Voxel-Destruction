@tool
@icon("voxel_object.svg")
extends MultiMeshInstance3D
class_name VoxelObject

## Displays and controls a [VoxelResource] or [CompactVoxelResource].
##
## Must be damaged by calling [method VoxelDamager.hit] on a nearby [VoxelDamager]

## Resource to display. Use an imported [VoxelResource] or [CompactVoxelResource]
@export var voxel_resource: VoxelResourceBase:
	set(value):
		voxel_resource = value
		update_configuration_warnings()
		if value:
			_populate_mesh()
		else:
			multimesh.instance_count = 0
## Prevents damage to self.
@export var invulnerable = false
## Darken damaged voxels based on voxel health.
@export var darkening = true
@export_subgroup("Debris")
## Type of debris generated [br]
## [b]None[/b]: No debris will be generated [br]
## [b]Multimesh[/b]: Debri has limited physics and no collision [br]
## [b]Rigid body[/b]: Debris are made up of rigid bodies, heavy performance reduction [br]
@export_enum("None", "Multimesh", "Rigid Bodies") var debris_type = 0
## Strength of gravity on debris
@export var debris_weight = 1
## Chance of generating debris per destroyed voxel
@export_range(0, 1, .1) var debris_density = .2
## Time in seconds before debris are deleted
@export var debris_lifetime = 5
@export_subgroup("Dithering")
## Maximum amount of random darkening.
@export_range(0, .20, .01) var dark_dithering = 0.0:
	set(value):
		dark_dithering = value
		_populate_mesh()
## Maximum amount of random lightening.
@export_range(0, .20, .01) var light_dithering = 0.0:
	set(value):
		light_dithering = value
		_populate_mesh()
## Ratio of random darkening to lightening.
@export_range(0, 1, .1) var dithering_bias = 0.5:
	set(value):
		dithering_bias = value
		_populate_mesh()
## Seed used when choosing if and to what extent a voxel is lightened or darkened.
@export var dithering_seed: int = 0:
	set(value):
		dithering_seed = value
		_populate_mesh()
var _collision_shapes = Dictionary()
var _collision_body: PhysicsBody3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		if not voxel_resource:
			push_warning("Voxel object has no VoxelResource")
			return
		
		# Preload rigid body debris (limit to 1000)
		if debris_type == 2:
			voxel_resource.pool_rigid_bodies(min(voxel_resource.vox_count, 1000))
		
		# Add to VoxelServer
		VoxelServer.voxel_objects.append(self)
		VoxelServer.total_active_voxels += voxel_resource.vox_count
		
		# Create collision body
		_collision_body = StaticBody3D.new()
		add_child(_collision_body)
		
		# Create starting shapes
		var shapes_dict = {}  # Cache for _collision_shapes
		for shape_info in voxel_resource.starting_shapes:
			var shape_node := CollisionShape3D.new()
			var shape := BoxShape3D.new()
			shape.extents = shape_info["extents"]
			shape_node.shape = shape
			shape_node.position = shape_info["position"]
			_collision_body.add_child(shape_node)
			
			var chunk = shape_info["chunk"]
			shapes_dict[chunk] = shapes_dict.get(chunk, []) + [shape_node]
		
		_collision_shapes.merge(shapes_dict)
		voxel_resource.starting_shapes.clear()
		
		# Update voxel colors for dithering
		if dark_dithering != 0 or light_dithering != 0:
			voxel_resource.buffer("colors")
			voxel_resource.buffer("color_index")
			var instance_count := multimesh.instance_count
			for i in instance_count:
				var color = multimesh.get_instance_color(i)
				if color not in voxel_resource.colors:
					voxel_resource.colors.append(color)
				voxel_resource.color_index[i] = voxel_resource.colors.find(color)


func _populate_mesh() -> void:
	if voxel_resource and Engine.is_editor_hint():
		# Buffers vars to prevent performence drop 
		# when finding vox color/position
		voxel_resource.buffer("positions")
		voxel_resource.buffer("color_index")
		voxel_resource.buffer("colors")
		
		# Create multimesh
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.instance_count = voxel_resource.vox_count
		
		# Create mesh
		var mesh = BoxMesh.new()
		mesh.material = preload("res://addons/VoxelDestruction/Resources/voxel_material.tres")
		mesh.size = voxel_resource.vox_size
		multimesh.mesh = mesh
		
		# Set dithering seed
		var random = RandomNumberGenerator.new()
		random.set_seed(dithering_seed)
		
		# Dither voxels and populate multimesh
		for i in multimesh.instance_count:
			var dark_variation = random.randf_range(0, dark_dithering)
			var light_variation = random.randf_range(0, light_dithering)
			var dithered_color = Color.WHITE
			if dark_dithering == 0 or light_dithering == 0:
				if dark_dithering == 0:
					dithered_color = _get_vox_color(i).lightened(light_variation)
				elif light_dithering == 0:
					dithered_color = _get_vox_color(i).darkened(dark_variation)
			else:
				dithered_color = _get_vox_color(i).darkened(dark_variation) if randf() > dithering_bias else _get_vox_color(i).lightened(light_variation)
			multimesh.set_instance_transform(i, Transform3D(Basis(), voxel_resource.positions[i]*voxel_resource.vox_size))
			multimesh.set_instance_color(i, dithered_color)


func _get_vox_color(voxid: int) -> Color:
	voxel_resource.buffer("colors")
	voxel_resource.buffer("color_index")
	return voxel_resource.colors[voxel_resource.color_index[voxid]]


func _damage_voxels(damager: VoxelDamager, voxel_count: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array) -> void:
	voxel_resource.buffer("health")
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("vox_chunk_indices")
	voxel_resource.buffer("chunks")
	# record damage results and create task pool
	var damage_results: Array
	# resize to make modifing thread-safe
	damage_results.resize(voxel_count)
	var group_id = WorkerThreadPool.add_group_task(
		_damage_voxel.bind(voxel_positions, global_voxel_positions, damager, damage_results), 
		voxel_count, -1, false, "Calculating Voxel Damage"
	)
	
	# Wait and buffer
	var last_buffer_time := Time.get_ticks_msec()
	var buffer_interval := 20

	while not WorkerThreadPool.is_group_task_completed(group_id):
		var current_time = Time.get_ticks_msec()
		
		# Buffer only if enough time has passed
		if current_time - last_buffer_time >= buffer_interval:
			voxel_resource.buffer("health")
			voxel_resource.buffer("positions_dict")
			voxel_resource.buffer("vox_chunk_indices")
			voxel_resource.buffer("chunks")
			last_buffer_time = current_time  # Update last buffer time
		
		await get_tree().process_frame  # Allow UI to update
	await _apply_damage_results(damage_results)


func _damage_voxel(voxel: int, voxel_positions: PackedVector3Array, global_voxel_positions: PackedVector3Array, damager: VoxelDamager, damage_results: Array) -> void: 
	# Get positions and vox_ids to modify later and calculate damage
	var vox_position: Vector3 = global_voxel_positions[voxel]
	var vox_pos3i: Vector3i = voxel_positions[voxel]
	var vox_id: int = voxel_resource.positions_dict.get(vox_pos3i, -1)
	
	# Skip if voxel ID is invalid
	if vox_id == -1:
		return  
	
	var decay: float = damager.global_pos.distance_squared_to(vox_position) / (damager.range * damager.range)
	var decay_sample: float = damager.damage_curve.sample(decay)
	
	# Skip processing if damage is negligible
	if decay_sample <= 0.01:
		return
	
	var power_sample: float = damager.power_curve.sample(decay)
	var damage: float = damager.base_damage * decay_sample
	
	# Compute new voxel health
	var new_health: float = clamp(voxel_resource.health[vox_id] - damage, 0, 100)
	
	var chunk = Vector3.ZERO
	var chunk_pos = 0
	if new_health == 0:
		chunk = voxel_resource.vox_chunk_indices[vox_id]
		var chunk_data = voxel_resource.chunks.get(chunk, [])
		chunk_pos = chunk_data.find(vox_pos3i) if chunk_data else -1
	
	# Store the result in a thread-safe dictionary
	damage_results[voxel] = {
		"vox_id": vox_id,
		"health": new_health,
		"pos": vox_pos3i,
		"chunk": chunk,
		"chunk_pos": chunk_pos
	}

func _apply_damage_results(damage_results: Array) -> void:
	voxel_resource.buffer("positions")
	voxel_resource.buffer("positions_dict")
	voxel_resource.buffer("chunks")
	var chunks_to_regen = PackedVector3Array()
	for result in damage_results:
		# Skip results
		if result == null:
			continue
		var vox_id: int = result["vox_id"]
		var health: float = result["health"]
		var vox_pos3i: Vector3i = result["pos"]
		
		# Set health, darken, remove voxels
		voxel_resource.health[vox_id] = health
		if health > 0:
			if darkening:
				multimesh.set_instance_color(vox_id, _get_vox_color(vox_id).darkened(1.0 - (health * 0.01)))
		else:
			# Remove voxel from valid positions, chunks, and multimesh
			multimesh.set_instance_transform(vox_id, Transform3D())
			voxel_resource.positions_dict.erase(vox_pos3i)
			VoxelServer.total_active_voxels -= 1
			
			var chunk = result["chunk"]
			voxel_resource.chunks[chunk][result["chunk_pos"]] = Vector3(-1, -7, -7)
			
			if chunk not in chunks_to_regen:
				chunks_to_regen.append(chunk)
	for chunk in chunks_to_regen:
		_regen_collision(chunk)


func _regen_collision(chunk_index: Vector3) -> void:
	var chunk: PackedVector3Array = voxel_resource.chunks[chunk_index]
	# Expand shapes to allow thread-safe modification
	var shapes = Array()
	shapes.resize(1000)
	# Create shape nodes
	var task_id = WorkerThreadPool.add_task(
		_create_shapes.bind(chunk, shapes), 
		false, "Calculating Collision Shapes"
	)
	while not WorkerThreadPool.is_task_completed(task_id):
		await get_tree().process_frame
	
	# Remove old shapes
	for shape in _collision_shapes[chunk_index]:
		shape.queue_free()
	_collision_shapes[chunk_index].clear()
	
	# Add shapes and record
	for shape_node in shapes:
		if shape_node == null:
			return
		_collision_body.add_child(shape_node)
		if chunk_index not in _collision_shapes:
			_collision_shapes[chunk_index] = Array()
		_collision_shapes[chunk_index].append(shape_node)


# This function is undocumented
func _create_shapes(chunk: PackedVector3Array, shapes) -> void:
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
		if pos == Vector3(-1, -7, -7):
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
	var i = -1
	for box in boxes:
		i += 1
		var min_pos = box["min"]
		var max_pos = box["max"]
		var center = (min_pos + max_pos) * 0.5 * voxel_resource.vox_size
		var shape_node = CollisionShape3D.new()
		var shape = BoxShape3D.new()
		shape_node.shape = shape
		shape.extents = ((max_pos - min_pos) + Vector3.ONE) * voxel_resource.vox_size * .5
		shape_node.position = center
		shapes[i] = shape_node

#
#func _create_debri_multimesh():
	#var gravity_magnitude : float = ProjectSettings.get_setting("physics/3d/default_gravity")
	#var debri_states = []
	#var multi_mesh_instance = MultiMeshInstance3D.new()
	#var multi_mesh = MultiMesh.new()
	#multi_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	#multi_mesh_instance.top_level = true
	#multi_mesh_instance.multimesh = multi_mesh
	#multi_mesh.mesh = preload("res://addons/VoxelDestruction/Resources/debri.tres").duplicate()
	#multi_mesh.mesh.size = voxel_resource.vox_size
	#multi_mesh.transform_format = MultiMesh.TRANSFORM_3D
	#multi_mesh.instance_count = _debris_queue.size()
	#add_child(multi_mesh_instance)
	#var idx = 0
	#for debris_data in _debris_queue:
		## Control debri amount
		#if randf() > debri_density: continue
		#
		#var debris_pos = debris_data.pos
		#
		## Store data for manual physics update
		#debri_states.append({
			#"position": debris_pos,
			#"velocity": (debris_pos - debris_data.origin).normalized() * -debris_data.power,
		#})
		#
		#multi_mesh.set_instance_transform(idx, Transform3D(Basis(), debris_pos))
		#idx += 1
	#var current_lifetime = debris_lifetime
	#_debris_called = false
	#_debris_queue.clear()
	#while current_lifetime > 0:
		#var delta = get_physics_process_delta_time()
		#current_lifetime -= delta
		#for i in debri_states.size():
			#var data = debri_states[i]
			#data["velocity"].x *= .98
			#data["velocity"].z *= .98
			#data["velocity"].y -= gravity_magnitude * delta * debris_weight
			#data["position"] += data["velocity"] * delta * 2
			#multi_mesh.set_instance_transform(i, Transform3D(Basis(), data["position"]))
		#await get_tree().process_frame
	#multi_mesh_instance.queue_free()
#
#
#func _create_debri_rigid_bodies(_debris_queue: Array) -> void:
	## Pre-cache children
	#var debri_objects = []  # To store all the debris
	#for debris_data in _debris_queue:
		## Control debri amount
		#if randf() > debris_density: continue
		## Retrieve/generate debri
		#var debri = voxel_resource.get_debri()
		#debri.name = "VoxelDebri"
		#debri.top_level = true
		#debri.show()
		## Cache shape and mesh if possible
		#var shape = debri.get_child(0)
		#var mesh = debri.get_child(1)
		## Set size/position in a single step
		#add_child(debri, true, Node.INTERNAL_MODE_BACK)
		#var debris_pos = debris_data.pos
		#debri.global_position = debris_pos
		#shape.shape.size = voxel_resource.vox_size
		#mesh.mesh.size = voxel_resource.vox_size
		## Launch debri
		#var velocity = (debris_pos - debris_data.origin).normalized() * debris_data.power
		#debri.freeze = false
		#debri.gravity_scale = debri_weight
		#debri.apply_impulse(velocity)
		## Add the debri to list
		#debri_objects.append(debri)
	#_debri_called = false
	#_debri_queue.clear()
	#await get_tree().create_timer(debri_lifetime).timeout
	## Batch scale-down animation (single loop)
	#if not debri_objects.is_empty():
		#var tween = get_tree().create_tween()
		#for debri in debri_objects:
			#var shape = debri.get_child(0)
			#var mesh = debri.get_child(1)
			#tween.parallel().tween_property(shape, "scale", Vector3(.01, .01, .01), 1)
			#tween.parallel().tween_property(mesh, "scale", Vector3(.01, .01, .01), 1)
		#await get_tree().create_timer(1).timeout
	## Restore all debris in a batch
	#for debri in debri_objects:
		#_restore_debri_rigid_bodies(debri)
